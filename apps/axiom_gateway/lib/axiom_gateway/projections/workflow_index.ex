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

  @doc """
  Lists workflows with optional filters and pagination.

  Options:
    * `:limit` — max records to return (default 100, max 1_000)
    * `:offset` — records to skip (default 0)
    * `:status` — filter by status (string or nil)
    * `:name` — filter by workflow name (exact match, or nil)

  Returns most-recently-updated first. Mnesia set tables are not
  inherently ordered, so we sort at read time.
  """
  @spec list_workflows(keyword()) :: [map()]
  def list_workflows(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100) |> clamp(1, 1_000)
    offset = Keyword.get(opts, :offset, 0) |> max(0)
    status = Keyword.get(opts, :status)
    name = Keyword.get(opts, :name)

    match_spec = build_match_spec(status, name)

    :mnesia.dirty_select(@table_name, match_spec)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
    |> Stream.drop(offset)
    |> Enum.take(limit)
  end

  @doc """
  Returns the total number of workflows matching the given filters.
  """
  @spec count_workflows(keyword()) :: non_neg_integer()
  def count_workflows(opts \\ []) do
    status = Keyword.get(opts, :status)
    name = Keyword.get(opts, :name)
    match_spec = build_match_spec(status, name)
    :mnesia.dirty_select(@table_name, match_spec) |> length()
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

      :workflow_failed ->
        update_status(event.workflow_id, "failed", timestamp)

      _ ->
        :ok
    end
  end

  defp update_status(id, status, timestamp) do
    case :mnesia.dirty_read(@table_name, id) do
      [{__MODULE__, ^id, name, _old_status, created, _updated}] ->
        :mnesia.dirty_write(@table_name, {__MODULE__, id, name, status, created, timestamp})

      [] ->
        :ok
    end
  end

  defp build_match_spec(status, name) do
    guards = build_guards(status, name)

    [
      {{
         __MODULE__,
         :"$1",
         :"$2",
         :"$3",
         :"$4",
         :"$5"
       }, guards,
       [%{id: :"$1", name: :"$2", status: :"$3", created_at: :"$4", updated_at: :"$5"}]}
    ]
  end

  defp build_guards(nil, nil), do: []
  defp build_guards(status, nil), do: [{:===, :"$3", status}]
  defp build_guards(nil, name), do: [{:===, :"$2", name}]
  defp build_guards(status, name), do: [{:andalso, {:===, :"$3", status}, {:===, :"$2", name}}]

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.stop()
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:id, :name, :status, :created_at, :updated_at],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created WorkflowIndex projection")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create WorkflowIndex table: #{inspect(error)}")
    end
  end
end
