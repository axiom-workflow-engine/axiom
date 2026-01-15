defmodule Axiom.Worker.Executor do
  @moduledoc """
  THE MERCENARY - Workers are liars until proven correct.

  Workers:
  - Execute side effects
  - Report outcomes
  - NEVER commit state

  Worker crashes = acceptable
  Double execution = NOT acceptable
  """

  use GenServer
  require Logger

  alias Axiom.Core.Event
  alias Axiom.Scheduler.Dispatcher

  defstruct [
    :worker_id,
    :dispatcher,
    :current_task,
    :current_lease,
    :handler_fn,
    poll_interval_ms: 1_000,
    execution_timeout_ms: 30_000
  ]

  @type t :: %__MODULE__{
          worker_id: binary(),
          dispatcher: GenServer.server(),
          current_task: map() | nil,
          current_lease: Axiom.Core.Lease.t() | nil,
          handler_fn: (atom(), map() -> {:ok, map()} | {:error, map()}),
          poll_interval_ms: non_neg_integer(),
          execution_timeout_ms: non_neg_integer()
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  def start_link(opts) do
    worker_id = Keyword.get_lazy(opts, :worker_id, &Event.generate_uuid/0)
    name = Keyword.get(opts, :name, via_tuple(worker_id))
    GenServer.start_link(__MODULE__, Keyword.put(opts, :worker_id, worker_id), name: name)
  end

  @doc """
  Gets the worker's current state.
  """
  @spec get_state(GenServer.server()) :: t()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Manually triggers task polling.
  """
  @spec poll_now(GenServer.server()) :: :ok
  def poll_now(server) do
    GenServer.cast(server, :poll_now)
  end

  @doc """
  Stops the worker gracefully.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    dispatcher = Keyword.get(opts, :dispatcher, Dispatcher)
    handler_fn = Keyword.get(opts, :handler_fn, &default_handler/2)
    poll_interval = Keyword.get(opts, :poll_interval_ms, 1_000)
    timeout = Keyword.get(opts, :execution_timeout_ms, 30_000)

    state = %__MODULE__{
      worker_id: worker_id,
      dispatcher: dispatcher,
      handler_fn: handler_fn,
      poll_interval_ms: poll_interval,
      execution_timeout_ms: timeout
    }

    # Register with dispatcher
    Dispatcher.register_worker(dispatcher, worker_id)

    # Start polling
    schedule_poll(poll_interval)

    Logger.info("[Worker:#{short_id(worker_id)}] Started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:poll_now, state) do
    state = do_poll(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = if state.current_task == nil do
      do_poll(state)
    else
      state
    end

    schedule_poll(state.poll_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:execute_result, result}, state) do
    state = handle_execution_result(state, result)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[Worker:#{short_id(state.worker_id)}] Shutting down")
    :ok
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp via_tuple(worker_id) do
    {:via, Registry, {Axiom.Worker.Registry, worker_id}}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp do_poll(state) do
    # Send heartbeat
    Dispatcher.heartbeat(state.dispatcher, state.worker_id)

    # Request task
    case Dispatcher.request_task(state.dispatcher, state.worker_id) do
      :no_task ->
        state

      {:task_lease, task, lease} ->
        Logger.info("[Worker:#{short_id(state.worker_id)}] Received task #{task.step}")
        execute_task(state, task, lease)

      {:error, reason} ->
        Logger.warning("[Worker:#{short_id(state.worker_id)}] Failed to get task: #{reason}")
        state
    end
  end

  defp execute_task(state, task, lease) do
    start_time = Event.logical_time()

    # Execute in a separate process for isolation
    parent = self()

    spawn(fn ->
      result = try do
        # Call the handler function
        state.handler_fn.(task.step, %{
          workflow_id: task.workflow_id,
          attempt: task.attempt
        })
      rescue
        e ->
          {:error, %{exception: Exception.message(e), stacktrace: Exception.format_stacktrace()}}
      catch
        :exit, reason ->
          {:error, %{exit: inspect(reason)}}
      end

      duration_ms = div(Event.logical_time() - start_time, 1_000_000)
      send(parent, {:execute_result, {result, duration_ms}})
    end)

    %{state | current_task: task, current_lease: lease}
  end

  defp handle_execution_result(state, {result, duration_ms}) do
    task = state.current_task
    lease = state.current_lease

    unless task && lease do
      Logger.warning("[Worker:#{short_id(state.worker_id)}] Received result with no active task")
      state
    else
      case result do
        {:ok, output} ->
          Logger.info("[Worker:#{short_id(state.worker_id)}] Task #{task.step} succeeded in #{duration_ms}ms")

          Dispatcher.report_completed(
            state.dispatcher,
            state.worker_id,
            lease.lease_id,
            lease.fencing_token,
            output
          )

        {:error, error} ->
          Logger.warning("[Worker:#{short_id(state.worker_id)}] Task #{task.step} failed: #{inspect(error)}")

          Dispatcher.report_failed(
            state.dispatcher,
            state.worker_id,
            lease.lease_id,
            lease.fencing_token,
            error,
            true  # retryable by default
          )
      end

      %{state | current_task: nil, current_lease: nil}
    end
  end

  defp default_handler(step, _context) do
    # Default handler just succeeds after a small delay
    Process.sleep(10)
    {:ok, %{step: step, executed_at: Event.logical_time()}}
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "unknown"
end
