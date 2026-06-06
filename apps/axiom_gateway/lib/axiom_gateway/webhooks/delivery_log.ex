defmodule AxiomGateway.Webhooks.DeliveryLog do
  @moduledoc """
  Append-only delivery log for inbound webhooks.

  Every received webhook is recorded with a unique delivery_id,
  timestamp, signature verification result, and processing status.
  Used for at-least-once delivery to downstream workflows and for
  audit trails.
  """

  use GenServer
  require Logger

  @table_name :axiom_webhook_deliveries

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    init_mnesia()
    {:ok, %{}}
  end

  @type status :: :received | :verified | :dispatched | :failed | :rejected

  @doc """
  Records a new webhook delivery and returns the generated delivery_id.
  """
  @spec record(String.t(), String.t(), String.t(), map(), status(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def record(webhook_id, delivery_id, event_type, payload, status, opts \\ []) do
    signature_valid? = Keyword.get(opts, :signature_valid?, false)
    error = Keyword.get(opts, :error)
    tenant_id = Keyword.get(opts, :tenant_id, "default")

    record = {
      delivery_id,
      webhook_id,
      tenant_id,
      event_type,
      serialize(payload),
      status,
      signature_valid?,
      error,
      DateTime.utc_now()
    }

    case :mnesia.transaction(fn -> :mnesia.write({@table_name, record}) end) do
      {:atomic, :ok} -> {:ok, delivery_id}
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates the status of a previously recorded delivery.
  """
  @spec update_status(String.t(), status(), keyword()) :: :ok | {:error, term()}
  def update_status(delivery_id, status, opts \\ []) do
    error = Keyword.get(opts, :error)

    case :mnesia.transaction(fn ->
           case :mnesia.read({@table_name, delivery_id}) do
             [{_, ^delivery_id, webhook_id, tenant_id, event_type, payload, _old_status, sig_valid?, _, received_at}] ->
               :mnesia.write(
                 {@table_name, delivery_id, webhook_id, tenant_id, event_type, payload, status,
                  sig_valid?, error, received_at}
               )

             [] ->
               {:error, :not_found}
           end
         end) do
      {:atomic, :ok} -> :ok
      {:atomic, {:error, _} = err} -> err
      {:aborted, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns recent deliveries, most recent first (up to `limit`).
  """
  @spec recent(non_neg_integer(), keyword()) :: [map()]
  def recent(limit \\ 100, opts \\ []) do
    webhook_id = Keyword.get(opts, :webhook_id)
    status = Keyword.get(opts, :status)

    match_spec = build_match_spec(webhook_id, status)
    :mnesia.dirty_select(@table_name, match_spec) |> Enum.take(limit)
  end

  # --------------------------------------------------------------------------

  defp build_match_spec(webhook_id, status) do
    # {delivery_id, webhook_id, tenant_id, event_type, payload, status, sig_valid?, error, received_at}
    guard =
      [
        {{:andalso, {:==, :"$2", webhook_id}, {:andalso, {:==, :"$6", status}, {:const, true}}}},
        {{:andalso, {:==, :"$6", status}, {:const, true}}},
        {{:==, :"$2", webhook_id}},
        {{:const, true}}
      ]
      |> Enum.find(&match?([_], &1))

    case {webhook_id, status} do
      {nil, nil} ->
        [{
          {@table_name, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
          [{{:const, true}}],
          [deliver_record()]
        }]

      {wid, nil} ->
        [{
          {@table_name, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
          [{:===, :"$2", {:const, wid}}],
          [deliver_record()]
        }]

      {nil, st} ->
        [{
          {@table_name, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
          [{:===, :"$6", {:const, st}}],
          [deliver_record()]
        }]

      {wid, st} ->
        [{
          {@table_name, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8", :"$9"},
          [{:andalso, {:===, :"$2", {:const, wid}}, {:===, :"$6", {:const, st}}}],
          [deliver_record()]
        }]
    end
  end

  defp deliver_record do
    %{
      delivery_id: :"$1",
      webhook_id: :"$2",
      tenant_id: :"$3",
      event_type: :"$4",
      payload: :"$5",
      status: :"$6",
      signature_valid: :"$7",
      error: :"$8",
      received_at: :"$9"
    }
  end

  defp serialize(payload), do: :erlang.term_to_binary(payload)

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.stop()
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [
             :delivery_id,
             :webhook_id,
             :tenant_id,
             :event_type,
             :payload,
             :status,
             :signature_valid,
             :error,
             :received_at
           ],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created WebhookDeliveryLog table")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create WebhookDeliveryLog table: #{inspect(error)}")
    end

    :mnesia.wait_for_tables([@table_name], 5_000)
  end
end
