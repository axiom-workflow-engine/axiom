defmodule AxiomGateway.IdempotencyCache do
  @moduledoc """
  Distributed, durable idempotency key store backed by Mnesia.
  """
  use GenServer
  require Logger

  @table_name :axiom_gateway_idempotency_keys

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    init_mnesia()
    {:ok, %{}}
  end

  def get(fingerprint) do
    case :mnesia.dirty_read(@table_name, fingerprint) do
      [{_, ^fingerprint, data}] -> data
      [] -> nil
    end
  end

  def put(fingerprint, data) do
    :mnesia.dirty_write({@table_name, fingerprint, data})
    :ok
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:fingerprint, :data],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created Mnesia table #{@table_name}")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create Mnesia table: #{inspect(error)}")
    end

    :mnesia.wait_for_tables([@table_name], 5000)
  end
end
