defmodule AxiomGateway.Schemas.Store do
  @moduledoc """
  Durable storage for Workflow Input Schemas.
  Backed by Mnesia.
  """
  use GenServer
  require Logger

  @table_name :axiom_schemas

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    init_mnesia()
    {:ok, %{}}
  end

  def register_schema(name, schema_map) do
    # Validate that it is a valid JSON schema first
    case ExJsonSchema.Schema.resolve(schema_map) do
      %ExJsonSchema.Schema{} ->
        timestamp = DateTime.utc_now()
        # Persist the schema definition
        :mnesia.dirty_write({@table_name, name, schema_map, timestamp})
        {:ok, name}

      _ ->
        {:error, :invalid_json_schema}
    end
  end

  def get_schema(name) do
    case :mnesia.dirty_read(@table_name, name) do
      [{_, ^name, schema, _ts}] -> {:ok, schema}
      [] -> {:error, :not_found}
    end
  end

  def list_schemas do
    # Select all names
    :mnesia.dirty_all_keys(@table_name)
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:name, :schema, :updated_at],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created Schema Registry store")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create Schema Registry store: #{inspect(error)}")
    end
  end
end
