defmodule Axiom.Engine.WorkflowProcess do
  @moduledoc """
  THE LAWYER - One workflow = one GenServer. Deterministic or die.

  Responsibilities:
  - Validate state transitions
  - Emit intent events
  - Never execute side effects

  Forbidden:
  - External calls
  - Randomness
  - Time-based branching
  """

  use GenServer
  require Logger

  alias Axiom.Engine.StateMachine
  alias Axiom.Core.Events
  alias Axiom.WAL.LogAppendServer

  # STATE CONTRACT
  defstruct [
    :workflow_id,
    :state_machine,
    :wal_server
  ]

  @type t :: %__MODULE__{
          workflow_id: binary(),
          state_machine: StateMachine.t(),
          wal_server: GenServer.server()
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Starts a workflow process.
  """
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    name = Keyword.get(opts, :name, via_tuple(workflow_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new workflow and starts executing.
  """
  @spec create(GenServer.server(), String.t(), map(), [atom()]) ::
    {:ok, binary()} | {:error, term()}
  def create(server, name, input, steps) do
    GenServer.call(server, {:create, name, input, steps})
  end

  @doc """
  Advances the workflow to the next step.
  Called after a step completes to schedule the next one.
  """
  @spec advance(GenServer.server()) :: :ok | {:error, term()}
  def advance(server) do
    GenServer.call(server, :advance)
  end

  @doc """
  Reports step completion. Called by scheduler after worker finishes.
  """
  @spec step_completed(GenServer.server(), atom(), map(), non_neg_integer(), keyword()) ::
    :ok | {:error, term()}
  def step_completed(server, step, result, duration_ms, opts \\ []) do
    GenServer.call(server, {:step_completed, step, result, duration_ms, opts})
  end

  @doc """
  Reports step failure.
  """
  @spec step_failed(GenServer.server(), atom(), map(), boolean(), keyword()) ::
    :ok | {:error, term()}
  def step_failed(server, step, error, retryable, opts \\ []) do
    GenServer.call(server, {:step_failed, step, error, retryable, opts})
  end

  @doc """
  Gets the current state of the workflow.
  """
  @spec get_state(GenServer.server()) :: StateMachine.t()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Hydrates a workflow from the event log.
  """
  @spec hydrate(GenServer.server()) :: :ok | {:error, term()}
  def hydrate(server) do
    GenServer.call(server, :hydrate)
  end

  @doc """
  Cancels a running workflow.
  """
  @spec cancel(GenServer.server()) :: :ok | {:error, term()}
  def cancel(server) do
    GenServer.call(server, :cancel)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    wal_server = Keyword.get(opts, :wal_server, LogAppendServer)

    state = %__MODULE__{
      workflow_id: workflow_id,
      state_machine: StateMachine.new(workflow_id),
      wal_server: wal_server
    }

    # If events exist, hydrate on startup
    case Keyword.get(opts, :auto_hydrate, true) do
      true -> {:ok, state, {:continue, :hydrate}}
      false -> {:ok, state}
    end
  end

  @impl true
  def handle_continue(:hydrate, state) do
    case do_hydrate(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_call({:create, name, input, steps}, _from, state) do
    workflow_id = state.workflow_id

    # Check if already created
    if state.state_machine.version > 0 do
      {:reply, {:error, :already_created}, state}
    else
      # Create the WorkflowCreated event
      event = Events.workflow_created(workflow_id, name, input, steps)

      # Commit to WAL first - this is the law
      case commit_event(state, event) do
        {:ok, _offset} ->
          # Apply to state machine
          new_sm = StateMachine.apply_event(state.state_machine, event)
          new_state = %{state | state_machine: new_sm}

          Logger.info("[Workflow:#{short_id(workflow_id)}] Created: #{name} with #{length(steps)} steps")
          {:reply, {:ok, workflow_id}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:advance, _from, state) do
    case StateMachine.next_runnable_step(state.state_machine) do
      nil ->
        # No more steps - check if we should complete
        if all_steps_completed?(state.state_machine) do
          complete_workflow(state)
        else
          {:reply, {:error, :no_runnable_step}, state}
        end

      step ->
        # Schedule the next step
        schedule_step(state, step)
    end
  end

  @impl true
  def handle_call({:step_completed, step, result, duration_ms, opts}, _from, state) do
    sm = state.state_machine
    idempotency_key = Keyword.get(opts, :idempotency_key)

    # Check idempotency FIRST - duplicates rejected regardless of step state
    if idempotency_key && StateMachine.idempotency_key_exists?(sm, idempotency_key) do
      {:reply, {:error, :duplicate}, state}
    else
      # Validate we're expecting this step
      unless Map.get(sm.step_states, step) in [:scheduled, :running] do
        {:reply, {:error, :unexpected_step}, state}
      else
        # Create event with idempotency key in metadata
        metadata = if idempotency_key, do: %{idempotency_key: idempotency_key}, else: %{}
        event = Events.step_completed(
          state.workflow_id,
          sm.version + 1,
          step,
          result,
          duration_ms,
          metadata: metadata
        )

        case commit_event(state, event) do
          {:ok, _offset} ->
            new_sm = StateMachine.apply_event(sm, event)
            new_state = %{state | state_machine: new_sm}

            Logger.info("[Workflow:#{short_id(state.workflow_id)}] Step :#{step} completed in #{duration_ms}ms")
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    end
  end

  @impl true
  def handle_call({:step_failed, step, error, retryable, opts}, _from, state) do
    sm = state.state_machine

    idempotency_key = Keyword.get(opts, :idempotency_key)
    if idempotency_key && StateMachine.idempotency_key_exists?(sm, idempotency_key) do
      {:reply, {:error, :duplicate}, state}
    else
      metadata = if idempotency_key, do: %{idempotency_key: idempotency_key}, else: %{}
      event = Events.step_failed(
        state.workflow_id,
        sm.version + 1,
        step,
        error,
        retryable,
        metadata: metadata
      )

      case commit_event(state, event) do
        {:ok, _offset} ->
          new_sm = StateMachine.apply_event(sm, event)
          new_state = %{state | state_machine: new_sm}

          Logger.warning("[Workflow:#{short_id(state.workflow_id)}] Step :#{step} failed: #{inspect(error)}")
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state_machine, state}
  end

  @impl true
  def handle_call(:hydrate, _from, state) do
    case do_hydrate(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    sm = state.state_machine

    if StateMachine.terminal?(sm) do
      {:reply, {:error, :already_terminal}, state}
    else
      event = Events.workflow_cancelled(state.workflow_id, sm.version + 1)

      case commit_event(state, event) do
        {:ok, _offset} ->
          new_sm = StateMachine.apply_event(sm, event)
          new_state = %{state | state_machine: new_sm}
          Logger.info("[Workflow:#{short_id(state.workflow_id)}] Cancelled")
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp via_tuple(workflow_id) do
    {:via, Registry, {Axiom.Engine.Registry, workflow_id}}
  end

  defp short_id(workflow_id) do
    String.slice(workflow_id, 0, 8)
  end

  defp commit_event(state, event) do
    LogAppendServer.append_event(state.wal_server, state.workflow_id, event)
  end

  defp do_hydrate(state) do
    case LogAppendServer.replay(state.wal_server, state.workflow_id) do
      {:ok, events} when events != [] ->
        new_sm = StateMachine.hydrate(state.workflow_id, events)
        Logger.info("[Workflow:#{short_id(state.workflow_id)}] Hydrated from #{length(events)} events, version: #{new_sm.version}")
        {:ok, %{state | state_machine: new_sm}}

      {:ok, []} ->
        {:ok, state}

      {:error, reason} ->
        Logger.error("[Workflow:#{short_id(state.workflow_id)}] Failed to hydrate: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_step(state, step) do
    sm = state.state_machine
    attempt = get_attempt_count(sm, step) + 1

    event = Events.step_scheduled(state.workflow_id, sm.version + 1, step, attempt)

    case commit_event(state, event) do
      {:ok, _offset} ->
        new_sm = StateMachine.apply_event(sm, event)
        new_state = %{state | state_machine: new_sm}

        Logger.info("[Workflow:#{short_id(state.workflow_id)}] Step :#{step} scheduled (attempt #{attempt})")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp complete_workflow(state) do
    sm = state.state_machine

    # Gather output from completed steps
    output = %{completed_steps: sm.steps}

    event = Events.workflow_completed(state.workflow_id, sm.version + 1, output)

    case commit_event(state, event) do
      {:ok, _offset} ->
        new_sm = StateMachine.apply_event(sm, event)
        new_state = %{state | state_machine: new_sm}

        Logger.info("[Workflow:#{short_id(state.workflow_id)}] Completed")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp all_steps_completed?(sm) do
    Enum.all?(sm.step_states, fn {_step, status} -> status == :completed end)
  end

  defp get_attempt_count(sm, step) do
    sm.history
    |> Enum.filter(fn e ->
      e.event_type == :step_scheduled and e.payload.step == step
    end)
    |> length()
  end
end
