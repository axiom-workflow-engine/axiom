defmodule AxiomEngine do
  @moduledoc """
  Workflow Engine - The core of Axiom.

  Manages workflow state machines through event-sourced GenServers.
  """

  alias Axiom.Engine.{WorkflowProcess, WorkflowSupervisor, StateMachine}
  alias Axiom.Core.Event

  @doc """
  Creates and starts a new workflow.
  """
  @spec create_workflow(String.t(), map(), [atom()], keyword()) ::
    {:ok, binary()} | {:error, term()}
  def create_workflow(name, input, steps, opts \\ []) do
    workflow_id = Event.generate_uuid()

    case WorkflowSupervisor.start_workflow(workflow_id, opts) do
      {:ok, pid} ->
        case WorkflowProcess.create(pid, name, input, steps) do
          {:ok, ^workflow_id} -> {:ok, workflow_id}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the state of a workflow by ID.
  """
  @spec get_workflow(binary()) :: {:ok, StateMachine.t()} | {:error, :not_found}
  def get_workflow(workflow_id) do
    case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
      [{pid, _}] -> {:ok, WorkflowProcess.get_state(pid)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Advances a workflow to the next step.
  """
  @spec advance_workflow(binary()) :: :ok | {:error, term()}
  def advance_workflow(workflow_id) do
    case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
      [{pid, _}] -> WorkflowProcess.advance(pid)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Reports step completion for a workflow.
  """
  @spec complete_step(binary(), atom(), map(), non_neg_integer(), keyword()) ::
    :ok | {:error, term()}
  def complete_step(workflow_id, step, result, duration_ms, opts \\ []) do
    case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
      [{pid, _}] -> WorkflowProcess.step_completed(pid, step, result, duration_ms, opts)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Reports step failure for a workflow.
  """
  @spec fail_step(binary(), atom(), map(), boolean(), keyword()) ::
    :ok | {:error, term()}
  def fail_step(workflow_id, step, error, retryable, opts \\ []) do
    case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
      [{pid, _}] -> WorkflowProcess.step_failed(pid, step, error, retryable, opts)
      [] -> {:error, :not_found}
    end
  end
end
