defmodule Axiom.Scheduler.Watcher do
  @moduledoc """
  The Watcher drives the workflow engine by listening to WAL events.
  It bridges the gap between the Engine (State) and the Scheduler (Execution).
  """
  use GenServer
  require Logger
  alias Axiom.WAL.LogAppendServer
  alias Axiom.Scheduler.Dispatcher

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Subscribe to WAL
    LogAppendServer.subscribe()
    Logger.info("[Watcher] Started and subscribed to WAL")
    {:ok, %{}}
  end

  def handle_info({:event, _offset, event}, state) do
    handle_event(event)
    {:noreply, state}
  end

  defp handle_event(%{event_type: :workflow_created} = event) do
    Logger.info("[Watcher] New workflow created: #{event.workflow_id}. Advancing...")
    AxiomEngine.advance_workflow(event.workflow_id)
  end

  defp handle_event(%{event_type: :step_scheduled} = event) do
    Logger.info("[Watcher] Step scheduled: #{event.workflow_id}:#{event.payload.step}. Notifying dispatcher...")
    Dispatcher.schedule_step(event.workflow_id, event.payload.step, event.payload.attempt)
  end

  defp handle_event(%{event_type: :step_completed} = event) do
    Logger.info("[Watcher] Step completed: #{event.workflow_id}:#{event.payload.step}. Advancing workflow...")
    AxiomEngine.advance_workflow(event.workflow_id)
  end

  defp handle_event(%{event_type: :step_failed, payload: %{retryable: true}} = event) do
    Logger.warning("[Watcher] Step failed but retryable: #{event.workflow_id}:#{event.payload.step}. Retrying in 1s...")
    Process.send_after(self(), {:retry, event.workflow_id}, 1000)
  end

  defp handle_event(_), do: :ok

  def handle_info({:retry, workflow_id}, state) do
    AxiomEngine.advance_workflow(workflow_id)
    {:noreply, state}
  end
end
