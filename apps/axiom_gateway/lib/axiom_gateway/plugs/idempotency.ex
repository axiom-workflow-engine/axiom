defmodule AxiomGateway.Plugs.Idempotency do
  @moduledoc """
  Idempotency plug.
  """
  import Plug.Conn
  require Logger
  alias AxiomGateway.IdempotencyCache

  def init(opts), do: opts

  def call(conn, _opts) do
    key = get_req_header(conn, "idempotency-key") |> List.first()

    if is_nil(key) do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(400, Jason.encode!(%{
        type: "https://axiom.dev/errors/missing-idempotency-key",
        title: "Idempotency-Key Header Missing",
        detail: "This endpoint requires an Idempotency-Key header to ensure at-least-once processing guarantees."
      }))
      |> halt()
    else
      handle_idempotency(conn, key)
    end
  end

  defp handle_idempotency(conn, key) do
    user = conn.assigns[:current_user]
    payload_hash = hash_payload(conn)

    # Robust fingerprint includes payload hash to detect conflicts
    fingerprint = :crypto.hash(:sha256, "#{key}:#{user[:tenant_id]}:#{conn.request_path}")

    case IdempotencyCache.get(fingerprint) do
      nil ->
        # New request.
        # Register a BEFORE SEND callback to cache the response.

        # We store the payload hash inside the value to verify it against future requests.
        storage_key = "#{user[:tenant_id]}:#{key}"

        case IdempotencyCache.get(storage_key) do
           nil ->
              register_before_send(conn, fn conn ->
                cache_response(storage_key, payload_hash, conn)
                conn
              end)

           %{payload_hash: stored_hash} when stored_hash != payload_hash ->
              conn
              |> result_conflict()

           %{status: status, response_body: body} ->
              # Hash matches, replay
              Logger.info("Replaying idempotent request #{key}")
              conn
              |> put_resp_header("x-idempotent-replay", "true")
              |> send_resp(status, body)
              |> halt()
        end

      # This path shouldn't be hit with the new logic above, but keeping for safety if we revert
      _ -> conn
    end
  end

  defp hash_payload(conn) do
    # Deterministic hash of body params
    # We rely on Jason.encode to be relatively stable, or we could sort keys.
    # For Phase 1, encoding the parsed params is sufficient.
    :crypto.hash(:sha256, Jason.encode!(conn.body_params))
  end

  defp result_conflict(conn) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(409, Jason.encode!(%{
      type: "https://axiom.dev/errors/idempotency-key-mismatch",
      title: "Idempotency Key Mismatch",
      detail: "The Idempotency-Key provided has already been used with a different request payload."
    }))
    |> halt()
  end

  defp cache_response(storage_key, payload_hash, conn) do
    # Only cache successful responses 2xx
    if conn.status >= 200 and conn.status < 300 do
       IdempotencyCache.put(storage_key, %{
         status: conn.status,
         response_body: conn.resp_body,
         payload_hash: payload_hash
       })
    end
  end
end
