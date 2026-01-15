defmodule Axiom.Engine.WorkflowSupervisor do
  @moduledoc """
  Dynamic supervisor for workflow processes.

  Each workflow gets its own GenServer, supervised dynamically.
  Crashes trigger replay from the WAL.
  """

  use DynamicSupervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new workflow process.
  """
  @spec start_workflow(DynamicSupervisor.supervisor(), binary(), keyword()) ::
    {:ok, pid()} | {:error, term()}
  def start_workflow(supervisor \\ __MODULE__, workflow_id, opts \\ []) do
    child_spec = {
      Axiom.Engine.WorkflowProcess,
      Keyword.merge([workflow_id: workflow_id], opts)
    }

    DynamicSupervisor.start_child(supervisor, child_spec)
  end

  @doc """
  Stops a workflow process.
  """
  @spec stop_workflow(DynamicSupervisor.supervisor(), pid()) :: :ok | {:error, :not_found}
  def stop_workflow(supervisor \\ __MODULE__, pid) do
    DynamicSupervisor.terminate_child(supervisor, pid)
  end

  @doc """
  Lists all running workflow processes.
  """
  @spec list_workflows(DynamicSupervisor.supervisor()) :: [{binary(), pid()}]
  def list_workflows(supervisor \\ __MODULE__) do
    DynamicSupervisor.which_children(supervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end
end
