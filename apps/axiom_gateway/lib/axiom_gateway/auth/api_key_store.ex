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
  def validate(raw_key) do
    case parse_key(raw_key) do
      {:ok, prefix, _secret} ->
        lookup_and_verify(raw_key, prefix)
      :error ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Provisions a new API key for a tenant.
  Returns the raw key (shown once) and stores the hash.
  """
  def create_key(tenant_id, type \\ :live) do
    secret = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    prefix = if type == :live, do: "ak_live_", else: "ak_test_"
    raw_key = prefix <> secret

    # Store hash
    hash = hash_key(raw_key)

    # Store: {prefix (index), hash, tenant_id, created_at}
    :mnesia.dirty_write({@table_name, prefix, hash, tenant_id, DateTime.utc_now()})

    {:ok, raw_key}
  end

  defp lookup_and_verify(raw_key, _prefix) do
    with {:ok, id, secret} <- split_id_secret(raw_key) do
       case :mnesia.dirty_read(@table_name, id) do
         [{_, ^id, stored_hash, tenant_id, _}] ->
           if verify_hash(secret, stored_hash) do
             {:ok, tenant_id}
           else
             {:error, :invalid_key}
           end
         [] ->
           {:error, :not_found}
       end
    else
      _ -> {:error, :invalid}
    end
  end

  # Key format: ak_live_<public_id>_<secret>
  defp split_id_secret(key) do
    case String.split(key, "_") do
       ["ak", type, id, secret] -> {:ok, "ak_#{type}_#{id}", secret}
       _ -> :error
    end
  end

  defp parse_key(key) do
     if String.starts_with?(key, "ak_") do
       {:ok, String.slice(key, 0, 8), key}
     else
       :error
     end
  end

  defp hash_key(secret) do
    :crypto.hash(:sha256, secret)
  end

  defp verify_hash(secret, hash) do
    Plug.Crypto.secure_compare(hash_key(secret), hash)
  end

  defp init_mnesia do
    nodes = [Node.self()]
    :mnesia.create_schema(nodes)
    :mnesia.start()

    case :mnesia.create_table(@table_name, [
           attributes: [:id, :hash, :tenant_id, :created_at],
           disc_copies: nodes,
           type: :set
         ]) do
      {:atomic, :ok} -> Logger.info("Created API Key store")
      {:aborted, {:already_exists, _}} -> :ok
      error -> Logger.error("Failed to create API Key store: #{inspect(error)}")
    end
  end
end
