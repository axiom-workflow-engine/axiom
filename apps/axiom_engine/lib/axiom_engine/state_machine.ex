defmodule Axiom.Engine.StateMachine do
  @moduledoc """
  Deterministic state machine for workflow transitions.

  State transitions are pure functions - no side effects.
  Given the same events, you get the same state. Always.
  """

  alias Axiom.Core.Event

  @type workflow_state :: :pending | :running | :waiting | :completed | :failed | :cancelled
  @type step_state :: :pending | :scheduled | :running | :completed | :failed

  defstruct [
    :workflow_id,
    :name,
    :input,
    :steps,
    :current_step_index,
    :step_states,
    :output,
    :error,
    state: :pending,
    version: 0,
    history: []
  ]

  @type t :: %__MODULE__{
          workflow_id: binary(),
          name: String.t() | nil,
          input: map() | nil,
          steps: [atom()],
          current_step_index: non_neg_integer(),
          step_states: %{atom() => step_state()},
          output: map() | nil,
          error: map() | nil,
          state: workflow_state(),
          version: non_neg_integer(),
          history: [Event.t()]
        }

  @doc """
  Creates a new empty state machine.
  """
  @spec new(binary()) :: t()
  def new(workflow_id) do
    %__MODULE__{
      workflow_id: workflow_id,
      steps: [],
      current_step_index: 0,
      step_states: %{}
    }
  end

  @doc """
  Applies an event to the state machine.
  Returns the new state. Pure function - no side effects.
  """
  @spec apply_event(t(), Event.t()) :: t()
  def apply_event(state, %Event{event_type: :workflow_created} = event) do
    %{state |
      name: event.payload.name,
      input: event.payload.input,
      steps: event.payload.steps,
      step_states: Map.new(event.payload.steps, fn step -> {step, :pending} end),
      current_step_index: 0,
      state: :pending,
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :step_scheduled} = event) do
    step = event.payload.step

    %{state |
      step_states: Map.put(state.step_states, step, :scheduled),
      state: :running,
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :step_started} = event) do
    step = event.payload.step

    %{state |
      step_states: Map.put(state.step_states, step, :running),
      state: :running,
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :step_completed} = event) do
    step = event.payload.step
    new_step_states = Map.put(state.step_states, step, :completed)

    # Find the next step
    current_idx = Enum.find_index(state.steps, &(&1 == step)) || 0
    next_idx = current_idx + 1

    %{state |
      step_states: new_step_states,
      current_step_index: next_idx,
      state: if(next_idx >= length(state.steps), do: :waiting, else: :running),
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :step_failed} = event) do
    step = event.payload.step

    %{state |
      step_states: Map.put(state.step_states, step, :failed),
      error: event.payload.error,
      state: if(event.payload.retryable, do: :waiting, else: :failed),
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :workflow_completed} = event) do
    %{state |
      output: event.payload.output,
      state: :completed,
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  def apply_event(state, %Event{event_type: :workflow_failed} = event) do
    %{state |
      error: event.payload.reason,
      state: :failed,
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  # Fallback for unknown events - just record in history
  def apply_event(state, event) do
    %{state |
      version: state.version + 1,
      history: [event | state.history]
    }
  end

  @doc """
  Hydrates state from a list of events (replay).
  Events must be in sequence order.
  """
  @spec hydrate(binary(), [Event.t()]) :: t()
  def hydrate(workflow_id, events) do
    initial = new(workflow_id)

    events
    |> Enum.sort_by(& &1.sequence)
    |> Enum.reduce(initial, &apply_event(&2, &1))
  end

  @doc """
  Returns the current step to execute, if any.
  """
  @spec current_step(t()) :: atom() | nil
  def current_step(%__MODULE__{steps: steps, current_step_index: idx}) do
    Enum.at(steps, idx)
  end

  @doc """
  Returns the next step that needs scheduling.
  """
  @spec next_runnable_step(t()) :: atom() | nil
  def next_runnable_step(%__MODULE__{state: state}) when state in [:completed, :failed, :cancelled] do
    nil
  end

  def next_runnable_step(%__MODULE__{steps: steps, step_states: step_states}) do
    Enum.find(steps, fn step ->
      Map.get(step_states, step) == :pending
    end)
  end

  @doc """
  Checks if the workflow is in a terminal state.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}) do
    state in [:completed, :failed, :cancelled]
  end

  @doc """
  Checks if the workflow can accept more events.
  """
  @spec active?(t()) :: boolean()
  def active?(state), do: not terminal?(state)

  @doc """
  Checks if an idempotency key has already been used.
  """
  @spec idempotency_key_exists?(t(), binary()) :: boolean()
  def idempotency_key_exists?(%__MODULE__{history: history}, key) do
    Enum.any?(history, fn event ->
      Map.get(event.metadata, :idempotency_key) == key
    end)
  end
end
