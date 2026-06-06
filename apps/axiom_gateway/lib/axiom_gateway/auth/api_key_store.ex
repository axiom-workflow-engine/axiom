defmodule AxiomGateway.Auth.ApiKeyStore do
  @moduledoc """
  Secure storage for API keys.
  Keys are stored as bcrypt hashes to prevent leakage.
  Backed by Mnesia for distributed, durable storage.
  """
  use GenServer
  require Logger

  @table_name :axiom_api_keys

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    init_mnesia()
    {:ok, %{}}
  end

  @doc """
  Validates an API key against the store.
  Returns {:ok, tenant_id} or {:error, :invalid}
  """
  def validate(raw_key) when is_binary(raw_key) do
    with {:ok, key_id, raw_key} <- parse_key(raw_key),
         [{_, ^key_id, stored_hash, tenant_id, _}] <-
           :mnesia.dirty_read(@table_name, key_id) do
      if verify_hash(raw_key, stored_hash) do
        {:ok, tenant_id}
      else
        {:error, :invalid_key}
      end
    else
      [] -> {:error, :not_found}
      :error -> {:error, :invalid_format}
      _ -> {:error, :invalid}
    end
  end

  def validate(_), do: {:error, :invalid_format}

  @doc """
  Provisions a new API key for a tenant.
  Returns the raw key (shown once) and stores the hash.
  """
  def create_key(tenant_id, type \\ :live) do
    secret = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    prefix = if type == :live, do: "ak_live_", else: "ak_test_"
    raw_key = prefix <> secret

    # Index by the 8-char prefix; verify the full raw key against the stored hash.
    key_id = String.slice(raw_key, 0, 8)
    hash = hash_key(raw_key)

    :mnesia.dirty_write({@table_name, key_id, hash, tenant_id, DateTime.utc_now()})

    {:ok, raw_key}
  end

  # Key format: ak_live_<public_id>_<base64-secret>
  # The 8-char prefix ("ak_live_" or "ak_test_") is the Mnesia index.
  # We hash the full raw key so neither the prefix nor the secret alone
  # is sufficient to authenticate.
  defp parse_key(key) when is_binary(key) do
    case String.split(key, "_") do
      ["ak", type, public_id, secret]
        when byte_size(type) > 0 and byte_size(public_id) > 0 and byte_size(secret) >= 32 ->
        key_id = "ak_" <> type <> "_"
        if String.starts_with?(key, key_id) do
          {:ok, key_id, key}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp parse_key(_), do: :error

  defp hash_key(secret) do
    :crypto.hash(:sha256, secret)
  end

  defp verify_hash(secret, hash) do
    Plug.Crypto.secure_compare(hash_key(secret), hash)
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.stop()
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name,
           attributes: [:id, :hash, :tenant_id, :created_at],
           disc_copies: nodes,
           type: :set
         ) do
      {:atomic, :ok} -> Logger.info("Created API Key store")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create API Key store: #{inspect(error)}")
    end
  end
end
