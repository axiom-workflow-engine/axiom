defmodule AxiomGateway.Webhooks.Registry do
  @moduledoc """
  Registry of webhook endpoints and their signing secrets.

  The raw secret is kept in a process-local ETS table for HMAC
  verification (HMAC is one-way; we need the original secret to
  recompute the digest). The hash is kept in Mnesia for durability
  so we can detect tampering after a restart.
  """

  use GenServer
  require Logger

  @table_name :axiom_webhook_secrets
  @raw_table :axiom_webhook_secrets_raw

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@raw_table, [:set, :named_table, :public, read_concurrency: true])
    init_mnesia()
    {:ok, %{}}
  end

  @doc """
  Registers a webhook endpoint with a freshly generated signing secret.

  Returns `{:ok, webhook_id, secret}` where `secret` is shown once
  and must be stored by the caller to compute the signature header.
  """
  @spec register(String.t(), keyword()) :: {:ok, String.t(), String.t()} | {:error, term()}
  def register(webhook_id, opts \\ []) when is_binary(webhook_id) do
    target_workflow = Keyword.get(opts, :target_workflow)
    secret = generate_secret()
    hash = :crypto.hash(:sha256, secret)
    created_at = DateTime.utc_now()

    record = {webhook_id, hash, target_workflow, created_at}

    case :mnesia.transaction(fn -> :mnesia.write({@table_name, record}) end) do
      {:atomic, :ok} ->
        :ets.insert(@raw_table, {webhook_id, secret})
        {:ok, webhook_id, secret}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Looks up a webhook by ID. Returns metadata, or `{:error, :not_found}`.
  Does not return the secret.
  """
  @spec lookup(String.t()) ::
          {:ok, %{secret_hash: binary(), target_workflow: String.t() | nil}} | {:error, :not_found}
  def lookup(webhook_id) when is_binary(webhook_id) do
    case :mnesia.dirty_read(@table_name, webhook_id) do
      [{_, ^webhook_id, secret_hash, target_workflow, _created_at}] ->
        {:ok, %{secret_hash: secret_hash, target_workflow: target_workflow}}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the raw signing secret for a webhook, or `nil` if not
  registered. Used by the dispatcher to recompute HMAC.

  This must not be exposed via any public API.
  """
  @spec fetch_secret(String.t()) :: String.t() | nil
  def fetch_secret(webhook_id) do
    case :ets.lookup(@raw_table, webhook_id) do
      [{^webhook_id, secret}] -> secret
      [] -> nil
    end
  end

  @doc """
  Verifies that a provided secret matches the stored hash. Constant-time.
  """
  @spec verify_secret?(String.t(), String.t()) :: boolean()
  def verify_secret?(webhook_id, provided_secret) do
    case lookup(webhook_id) do
      {:ok, %{secret_hash: stored_hash}} ->
        candidate = :crypto.hash(:sha256, provided_secret)
        Plug.Crypto.secure_compare(candidate, stored_hash)

      {:error, :not_found} ->
        false
    end
  end

  # --------------------------------------------------------------------------

  defp generate_secret do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.stop()
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:webhook_id, :secret_hash, :target_workflow, :created_at],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created WebhookRegistry table")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create WebhookRegistry table: #{inspect(error)}")
    end

    :mnesia.wait_for_tables([@table_name], 5_000)
  end
end
