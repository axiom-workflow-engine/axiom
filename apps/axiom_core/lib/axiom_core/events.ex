defmodule Axiom.Core.Events do
  @moduledoc """
  Core event type definitions (v1).

  All event payloads for the workflow engine.
  These are facts - things that happened.
  """

  alias Axiom.Core.Event

  # ============================================================================
  # WorkflowCreated (v1)
  # Emitted exactly once, sequence = 0
  # ============================================================================

  @doc """
  Creates a WorkflowCreated event.
  """
  @spec workflow_created(binary(), String.t(), map(), [atom()], keyword()) :: Event.t()
  def workflow_created(workflow_id, name, input, steps, opts \\ []) do
    Event.new(
      :workflow_created,
      workflow_id,
      0,
      %{
        name: name,
        input: input,
        steps: steps
      },
      opts
    )
  end

  # ============================================================================
  # StepScheduled (v1)
  # Must precede execution, attempt increments on retry
  # ============================================================================

  @doc """
  Creates a StepScheduled event.
  """
  @spec step_scheduled(binary(), non_neg_integer(), atom(), pos_integer(), keyword()) :: Event.t()
  def step_scheduled(workflow_id, sequence, step, attempt, opts \\ []) do
    Event.new(
      :step_scheduled,
      workflow_id,
      sequence,
      %{
        step: step,
        attempt: attempt
      },
      opts
    )
  end

  # ============================================================================
  # StepStarted (v1)
  # Lease must be valid, used for fencing
  # ============================================================================

  @doc """
  Creates a StepStarted event.
  """
  @spec step_started(binary(), non_neg_integer(), atom(), binary(), binary(), keyword()) :: Event.t()
  def step_started(workflow_id, sequence, step, lease_id, worker_id, opts \\ []) do
    Event.new(
      :step_started,
      workflow_id,
      sequence,
      %{
        step: step,
        lease_id: lease_id,
        worker_id: worker_id
      },
      opts
    )
  end

  # ============================================================================
  # StepCompleted (v1)
  # Idempotent by (workflow_id, step, attempt)
  # Only emitted after commit-safe execution
  # ============================================================================

  @doc """
  Creates a StepCompleted event.
  """
  @spec step_completed(binary(), non_neg_integer(), atom(), map(), non_neg_integer(), keyword()) :: Event.t()
  def step_completed(workflow_id, sequence, step, result, duration_ms, opts \\ []) do
    Event.new(
      :step_completed,
      workflow_id,
      sequence,
      %{
        step: step,
        result: result,
        duration_ms: duration_ms
      },
      opts
    )
  end

  # ============================================================================
  # StepFailed (v1)
  # Does not imply workflow failure, scheduler decides next move
  # ============================================================================

  @doc """
  Creates a StepFailed event.
  """
  @spec step_failed(binary(), non_neg_integer(), atom(), map(), boolean(), keyword()) :: Event.t()
  def step_failed(workflow_id, sequence, step, error, retryable, opts \\ []) do
    Event.new(
      :step_failed,
      workflow_id,
      sequence,
      %{
        step: step,
        error: error,
        retryable: retryable
      },
      opts
    )
  end

  # ============================================================================
  # WorkflowCompleted (v1)
  # Terminal event - no events allowed after this
  # ============================================================================

  @doc """
  Creates a WorkflowCompleted event.
  """
  @spec workflow_completed(binary(), non_neg_integer(), map(), keyword()) :: Event.t()
  def workflow_completed(workflow_id, sequence, output, opts \\ []) do
    Event.new(
      :workflow_completed,
      workflow_id,
      sequence,
      %{
        output: output
      },
      opts
    )
  end

  # ============================================================================
  # WorkflowFailed (v1)
  # Terminal - explicit failure only
  # ============================================================================

  @doc """
  Creates a WorkflowFailed event.
  """
  @spec workflow_failed(binary(), non_neg_integer(), map(), atom(), keyword()) :: Event.t()
  def workflow_failed(workflow_id, sequence, reason, final_step, opts \\ []) do
    Event.new(
      :workflow_failed,
      workflow_id,
      sequence,
      %{
        reason: reason,
        final_step: final_step
      },
      opts
    )
  end
  # ============================================================================
  # WorkflowCancelled (v1)
  # Terminal - user initiated validation
  # ============================================================================

  @doc """
  Creates a WorkflowCancelled event.
  """
  @spec workflow_cancelled(binary(), non_neg_integer(), keyword()) :: Event.t()
  def workflow_cancelled(workflow_id, sequence, opts \\ []) do
    Event.new(
      :workflow_cancelled,
      workflow_id,
      sequence,
      %{},
      opts
    )
  end
end
