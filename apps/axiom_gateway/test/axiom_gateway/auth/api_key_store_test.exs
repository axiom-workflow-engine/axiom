defmodule AxiomGateway.Auth.ApiKeyStoreTest do
  use ExUnit.Case
  alias AxiomGateway.Auth.ApiKeyStore

  setup do
    # Ensure Mnesia is clean or unique for test
    # Ideally we'd wrap this, but for now we trust the GenServer start
    :ok
  end

  test "can provision and validate a live key" do
    {:ok, raw_key} = ApiKeyStore.create_key("tenant_123", :live)

    assert String.starts_with?(raw_key, "ak_live_")

    # Valid key
    assert {:ok, "tenant_123"} = ApiKeyStore.validate(raw_key)
  end

  test "can provision and validate a test key" do
    {:ok, raw_key} = ApiKeyStore.create_key("tenant_456", :test)

    assert String.starts_with?(raw_key, "ak_test_")
    assert {:ok, "tenant_456"} = ApiKeyStore.validate(raw_key)
  end

  test "returns error for invalid key format" do
     assert {:error, :invalid_format} = ApiKeyStore.validate("bad_format")
  end

  test "returns error for non-existent key" do
     assert {:error, :not_found} = ApiKeyStore.validate("ak_live_00000000_fakekey")
  end

  test "returns error for wrong secret" do
     {:ok, raw_key} = ApiKeyStore.create_key("tenant_789", :live)
     "ak_live_" <> rest = raw_key
     [id, _secret] = String.split(rest, "_")

     bad_key = "ak_live_#{id}_badsecret"
     assert {:error, :invalid_key} = ApiKeyStore.validate(bad_key)
  end
end
