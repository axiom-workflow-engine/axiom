defmodule AxiomGateway.Projections.WorkflowIndex do
  @moduledoc """
  CQRS Projection maintaining a secondary index of workflows in Mnesia.

  Subscribes to the WAL and updates the status of workflows.
  Source of truth for list/query operations.
  """
  use GenServer
  require Logger
  alias Axiom.WAL.LogAppendServer

  @table_name :axiom_workflow_index

  defmodule Record do
    defstruct [:id, :name, :status, :created_at, :updated_at]
  end

  # API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_workflows(limit \\ 100) do
    # Select most recent workflows.
    # Note: Mnesia set tables are not ordered, so this returns an arbitrary set of records.
    # For strict ordering, an ordered_set or secondary index on timestamp would be required.
    # Given the constraints, we select effectively.
    match_spec = [{
      {__MODULE__, :"$1", :"$2", :"$3", :"$4", :"$5"},
      [],
      [%{id: :"$1", name: :"$2", status: :"$3", created_at: :"$4", updated_at: :"$5"}]
    }]

    :mnesia.dirty_select(@table_name, match_spec)
    |> Enum.take(limit)
  end

  def get_workflow(id) do
    case :mnesia.dirty_read(@table_name, id) do
      [{__MODULE__, ^id, name, status, created, updated}] ->
        {:ok, %{id: id, name: name, status: status, created_at: created, updated_at: updated}}
      [] ->
        {:error, :not_found}
    end
  end

  # Callbacks

  def init(_) do
    init_mnesia()

    # Subscribe to WAL events
    LogAppendServer.subscribe()

    {:ok, %{}}
  end

  def handle_info({:event, _offset, event}, state) do
    update_index(event)
    {:noreply, state}
  end

  defp update_index(event) do
    # Handle specific events to update status
    timestamp = DateTime.utc_now()

    case event.event_type do
      :workflow_created ->
        record = {
          __MODULE__,
          event.workflow_id,
          event.payload.name,
          "running",
          timestamp,
          timestamp
        }
        :mnesia.dirty_write(@table_name, record)

      :workflow_completed ->
        update_status(event.workflow_id, "completed", timestamp)

      :workflow_cancelled ->
        update_status(event.workflow_id, "cancelled", timestamp)

      :step_failed ->
         # Optional: track detailed status?
         # For index, maybe just keep it simple.
         :ok

       _ -> :ok
    end
  end

  defp update_status(id, status, timestamp) do
    case :mnesia.dirty_read(@table_name, id) do
      [{__MODULE__, ^id, name, _old_status, created, _updated}] ->
        :mnesia.dirty_write(@table_name, {__MODULE__, id, name, status, created, timestamp})
      [] ->
        # Should not happen unless gap in hydration
        :ok
    end
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:id, :name, :status, :created_at, :updated_at],
           disc_copies: nodes,
           type: :set # ID is primary key
         ]) do
      {:atomic, :ok} -> Logger.info("Created WorkflowIndex projection")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create WorkflowIndex table: #{inspect(error)}")
    end
  end
end
