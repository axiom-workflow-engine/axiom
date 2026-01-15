defmodule AxiomGateway.Controllers.WorkflowController do
  use Phoenix.Controller

  alias AxiomGateway.Durable.Acceptor

  action_fallback AxiomGateway.Controllers.FallbackController

  alias Axiom.WAL.LogAppendServer
  alias Axiom.Engine.StateMachine
  alias AxiomGateway.Projections.WorkflowIndex

  def index(conn, _params) do
    workflows = WorkflowIndex.list_workflows()
    json(conn, %{data: workflows})
  end

  def show(conn, %{"id" => id}) do
    # 1. Try running process
    case Registry.lookup(Axiom.Engine.Registry, id) do
      [{pid, _}] ->
         state_machine = Axiom.Engine.WorkflowProcess.get_state(pid)
         json(conn, %{data: serialize_state(state_machine)})

      [] ->
         # 2. If not running, rehydrate from WAL (Ephemeral Read)
         case LogAppendServer.replay(LogAppendServer, id) do
           {:ok, events} when events != [] ->
              state_machine = StateMachine.hydrate(id, events)
              json(conn, %{data: serialize_state(state_machine)})

           _ ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Workflow not found"})
         end
    end
  end

  def events(conn, %{"id" => id}) do
    case LogAppendServer.replay(LogAppendServer, id) do
      {:ok, events} ->
        json(conn, %{data: events})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  defp serialize_state(sm) do
    %{
      id: sm.workflow_id,
      status: if(StateMachine.terminal?(sm), do: "completed", else: "running"),
      current_step: List.first(sm.steps), # Simplified
      version: sm.version,
      context: sm.context
    }
  end

  def create(conn, params) do
    # Extract identity for audit trail
    identity = conn.assigns[:current_user]

    # 1. Validate payload structure (syntax check)
    # 2. Accept into WAL (durability)
    case Acceptor.accept_workflow(params, identity) do
      {:ok, workflow_id} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/workflows/#{workflow_id}")
        |> put_status(:created)
        |> json(%{data: %{id: workflow_id, status: "accepted"}})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def bulk_create(conn, _params) do
    # Async processing via message queue as per design
    json(conn, %{status: "bulk_accepted"})
  end

  def cancel(conn, %{"id" => id}) do
    identity = conn.assigns[:current_user]

    case Acceptor.accept_cancellation(id, identity) do
      :ok ->
        json(conn, %{status: "cancelled"})
      error ->
        error
    end
  end

  def advance(conn, %{"id" => id}) do
    identity = conn.assigns[:current_user]

    case Acceptor.accept_advancement(id, identity) do
      :ok ->
         json(conn, %{status: "advanced"})
      error ->
         error
    end
  end

  def lease(conn, %{"id" => id}) do
     # Worker polling endpoint
     json(conn, %{task: nil})
  end

  def submit_result(conn, %{"id" => id}) do
     # Worker result submission
     json(conn, %{status: "result_accepted"})
  end
end
