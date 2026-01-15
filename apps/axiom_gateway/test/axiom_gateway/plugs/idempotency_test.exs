defmodule AxiomGateway.Plugs.IdempotencyTest do
  use ExUnit.Case
  use Plug.Test

  alias AxiomGateway.Plugs.Idempotency
  alias AxiomGateway.IdempotencyCache

  # Mock user assignment since plug expects it
  defp assign_user(conn, tenant_id) do
    assign(conn, :current_user, %{tenant_id: tenant_id, role: "service"})
  end

  setup do
    # Ensure cache is clean-ish or keys specific
    :ok
  end

  test "returns 400 if idempotency key is missing" do
    conn = conn(:post, "/api/v1/workflows")
           |> assign_user("tenant_A")
           |> Idempotency.call([])

    assert conn.status == 400
    assert conn.resp_body =~ "Idempotency-Key Header Missing"
  end

  test "proceeds if key is present (new request)" do
    key = UUID.uuid4()

    conn = conn(:post, "/api/v1/workflows", %{"name" => "test"})
           |> put_req_header("idempotency-key", key)
           |> assign_user("tenant_A")
           |> Idempotency.call([])

    # Should not be halted
    refute conn.halted

    # Simulate the controller finishing and caching
    # We can't easily simulate the "before_send" in a unit test of just the plug
    # unless we trigger send_resp.

    conn = send_resp(conn, 201, "OK")

    # Check if it was cached
    stored = IdempotencyCache.get("tenant_A:#{key}")
    assert stored != nil
    assert stored.status == 201
  end

  test "returns cached response on replay" do
    key = UUID.uuid4()
    storage_key = "tenant_A:#{key}"
    payload = %{"name" => "test"}
    encoded_payload = Jason.encode!(payload)
    payload_hash = :crypto.hash(:sha256, encoded_payload)

    # Pre-seed cache
    IdempotencyCache.put(storage_key, %{
      status: 201,
      response_body: "Saved Response",
      payload_hash: payload_hash
    })

    conn = conn(:post, "/api/v1/workflows", payload)
           |> put_req_header("idempotency-key", key)
           |> assign_user("tenant_A")
           |> Idempotency.call([])

    assert conn.halted
    assert conn.status == 201
    assert conn.resp_body == "Saved Response"
    assert get_resp_header(conn, "x-idempotent-replay") == ["true"]
  end

  test "returns 409 Conflict on payload mismatch" do
    key = UUID.uuid4()
    storage_key = "tenant_A:#{key}"

    # Seed with hash of {"a": 1}
    payload_hash = :crypto.hash(:sha256, Jason.encode!(%{"a" => 1}))
    IdempotencyCache.put(storage_key, %{status: 200, response_body: "d", payload_hash: payload_hash})

    # Send request with {"b": 2}
    conn = conn(:post, "/api/v1/workflows", %{"b" => 2})
           |> put_req_header("idempotency-key", key)
           |> assign_user("tenant_A")
           |> Idempotency.call([])

    assert conn.halted
    assert conn.status == 409
    assert conn.resp_body =~ "Idempotency Key Mismatch"
  end
end
