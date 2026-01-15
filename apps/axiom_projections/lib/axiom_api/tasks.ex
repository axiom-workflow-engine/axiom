defmodule Axiom.API.Tasks do
  @moduledoc """
  Task API handlers.
  """

  alias Axiom.Scheduler.TaskQueue

  @doc """
  Lists all tasks in queue.
  """
  def list do
    case GenServer.whereis(TaskQueue) do
      nil ->
        {:error, :scheduler_not_running}

      _pid ->
        depth = TaskQueue.depth()
        pending = TaskQueue.list_pending()

        {:ok, %{
          queue_depth: depth,
          pending_count: length(pending),
          pending: format_tasks(pending)
        }}
    end
  end

  @doc """
  Lists pending (in-flight) tasks.
  """
  def list_pending do
    case GenServer.whereis(TaskQueue) do
      nil ->
        {:error, :scheduler_not_running}

      _pid ->
        pending = TaskQueue.list_pending()
        {:ok, format_tasks(pending)}
    end
  end

  defp format_tasks(tasks) do
    Enum.map(tasks, fn task ->
      %{
        id: task.task_id,
        workflow_id: task.workflow_id,
        step: to_string(task.step),
        attempt: task.attempt,
        enqueued_at: task.enqueued_at
      }
    end)
  end
end
