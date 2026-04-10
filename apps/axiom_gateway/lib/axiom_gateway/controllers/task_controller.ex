defmodule AxiomGateway.Controllers.TaskController do
  use Phoenix.Controller

  action_fallback AxiomGateway.Controllers.FallbackController

  def index(conn, _params) do
    tasks = list_tasks()
    json(conn, %{data: tasks})
  end

  def show(conn, %{"id" => id}) do
    case Enum.find(list_tasks(), fn task -> task.task_id == id end) do
      nil ->
        {:error, :not_found}

      task ->
        json(conn, %{data: task})
    end
  end

  defp list_tasks do
    if Code.ensure_loaded?(Axiom.Scheduler.TaskQueue) and
         function_exported?(Axiom.Scheduler.TaskQueue, :list_pending, 1) do
      Axiom.Scheduler.TaskQueue.list_pending(Axiom.Scheduler.TaskQueue)
    else
      []
    end
  end
end
