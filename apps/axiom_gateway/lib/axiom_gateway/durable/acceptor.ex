defmodule AxiomGateway.Durable.Acceptor do
  @moduledoc """
  The Durable Acceptor is the gateway's write interface to the engine.

  It guarantees that if a request is accepted, it is durably persisted.
  It routes requests to the authoritative node for the workflow using consistent hashing.
  """

  require Logger
  alias Axiom.Engine.WorkflowSupervisor
  alias Axiom.Engine.WorkflowProcess
  alias AxiomGateway.Distribution.NodeSelector
  alias AxiomGateway.Schemas.Validator

  @doc """
  Accepts a workflow creation request.
  """
  def accept_workflow(params, _identity) do
    with {:ok, name} <- validate_required(params, "name"),
         {:ok, steps} <- validate_steps(params["steps"]),
         input = params["input"] || %{},
         :ok <- Validator.validate_input(name, input) do

      workflow_id = params["id"] || UUID.uuid4()

      target_node = NodeSelector.select_node(workflow_id)

      if target_node == Node.self() do
        start_and_create_local(workflow_id, name, input, steps)
      else
        rpc_create_remote(target_node, workflow_id, name, input, steps)
      end
    else
      {:error, {:schema_validation_failed, errors}} ->
        {:error, {:bad_request, errors}}
      {:error, reason} ->
        {:error, {:bad_request, reason}}
    end
  end

  def accept_cancellation(workflow_id, _identity) do
    target_node = NodeSelector.select_node(workflow_id)

    if target_node == Node.self() do
      cancel_local(workflow_id)
    else
      :erpc.call(target_node, __MODULE__, :cancel_local, [workflow_id])
    end
  end

  def accept_advancement(workflow_id, _identity) do
    target_node = NodeSelector.select_node(workflow_id)

    if target_node == Node.self() do
      advance_local(workflow_id)
    else
      :erpc.call(target_node, __MODULE__, :advance_local, [workflow_id])
    end
  end

  # Public internal API for RPC calls

  def cancel_local(workflow_id) do
    case find_process(workflow_id) do
      {:ok, pid} -> WorkflowProcess.cancel(pid)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def advance_local(workflow_id) do
    case find_process(workflow_id) do
       {:ok, pid} -> WorkflowProcess.advance(pid)
       {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Private helpers

  defp start_and_create_local(workflow_id, name, input, steps) do
    case WorkflowSupervisor.start_workflow(Axiom.Engine.WorkflowSupervisor, workflow_id) do
      {:ok, pid} ->
         create_in_process(pid, workflow_id, name, input, steps)

      {:error, {:already_started, pid}} ->
         create_in_process(pid, workflow_id, name, input, steps)

      {:error, reason} ->
         Logger.error("Failed to start workflow process locally: #{inspect(reason)}")
         {:error, :internal_server_error}
    end
  end

  defp rpc_create_remote(node, workflow_id, name, input, steps) do
    # 5 second timeout for remote creation to prevent locking the gateway
    try do
      :erpc.call(node, fn ->
        start_and_create_local(workflow_id, name, input, steps)
      end, 5000)
    rescue
      e in [ErlangError] ->
        Logger.error("RPC to node #{inspect(node)} failed: #{inspect(e)}")
        {:error, :rpc_failure}
    end
  end

  defp create_in_process(pid, _id, name, input, atom_steps) do
    case WorkflowProcess.create(pid, name, input, atom_steps) do
      {:ok, id} -> {:ok, id}
      {:error, :already_created} -> {:error, :conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_process(workflow_id) do
    case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp validate_required(params, field) do
    case Map.get(params, field) do
      nil -> {:error, "Missing required field: #{field}"}
      val -> {:ok, val}
    end
  end

  defp validate_steps(steps) when is_list(steps) and length(steps) > 0 do
    atom_steps = Enum.map(steps, fn s ->
      if is_atom(s), do: s, else: String.to_atom(s)
    end)
    {:ok, atom_steps}
  end

  defp validate_steps(_), do: {:error, "Steps must be a non-empty list"}
end
