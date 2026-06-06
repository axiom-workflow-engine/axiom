defmodule AxiomGateway.Controllers.WebhookController do
  @moduledoc """
  Receives inbound webhooks from external systems.

  Webhooks are signed with HMAC-SHA256. The signature is verified
  against the secret registered for the webhook_id. Verified
  deliveries are recorded in the durable log and dispatched to the
  engine in the background.

  Auth is by signature, not by the standard auth pipeline. The
  secret lookup itself uses the durable registry.

  Required headers:
    X-Webhook-Signature: sha256=<hex> — HMAC-SHA256 of the raw body

  Optional headers:
    X-Idempotency-Key — duplicate deliveries return the original record
    X-Target-Workflow — fallback if no target was registered
  """

  use Phoenix.Controller

  alias AxiomGateway.Webhooks.{Registry, DeliveryLog, Dispatcher}
  alias Axiom.Core.Event

  # Cap the body we'll read into memory. Anything larger is rejected.
  @max_body_bytes 1_048_576  # 1 MiB

  def receive(conn, %{"webhook_id" => webhook_id} = params) do
    raw_body = read_raw_body(conn)

    cond do
      byte_size(raw_body) > @max_body_bytes ->
        reject(conn, 413, :payload_too_large, "Webhook body exceeds #{@max_body_bytes} bytes")

      true ->
        process(conn, webhook_id, raw_body, params)
    end
  end

  def receive(conn, _params) do
    reject(conn, 400, :bad_request, "Missing webhook_id")
  end

  # --------------------------------------------------------------------------

  defp process(conn, webhook_id, raw_body, params) do
    case Registry.lookup(webhook_id) do
      {:error, :not_found} ->
        reject(conn, 404, :webhook_not_found, "No webhook registered with id #{webhook_id}")

      {:ok, %{target_workflow: registered_target}} ->
        handle_verified(conn, webhook_id, raw_body, params, registered_target)
    end
  end

  defp handle_verified(conn, webhook_id, raw_body, params, registered_target) do
    signature = get_req_header(conn, "x-webhook-signature") |> List.first()
    idempotency_key = get_req_header(conn, "x-idempotency-key") |> List.first()
    header_target = get_req_header(conn, "x-target-workflow") |> List.first()

    target = header_target || registered_target
    event_type = Map.get(params, "event_type", "unknown")
    tenant_id = conn.assigns[:current_user][:tenant_id] || "default"

    case Dispatcher.verify(webhook_id, signature, raw_body) do
      {:ok, _body} ->
        deliver(conn, webhook_id, raw_body, params, target, tenant_id, event_type, idempotency_key)

      {:error, :not_found} ->
        reject(conn, 404, :webhook_not_found, "No webhook registered with id #{webhook_id}")

      {:error, :missing_signature} ->
        record_rejected(webhook_id, tenant_id, event_type, raw_body, :missing_signature)
        reject(conn, 401, :missing_signature, "X-Webhook-Signature header required")

      {:error, :invalid_signature} ->
        record_rejected(webhook_id, tenant_id, event_type, raw_body, :invalid_signature)
        reject(conn, 401, :invalid_signature, "Signature verification failed")

      {:error, :malformed_signature} ->
        record_rejected(webhook_id, tenant_id, event_type, raw_body, :malformed_signature)
        reject(conn, 401, :malformed_signature, "X-Webhook-Signature must be sha256=<64-hex>")
    end
  end

  defp deliver(
         conn,
         webhook_id,
         raw_body,
         params,
         target,
         tenant_id,
         event_type,
         idempotency_key
       ) do
    delivery_id = idempotency_key || Event.generate_uuid()
    payload = decode_payload(params, raw_body)

    case DeliveryLog.record(
           webhook_id,
           delivery_id,
           event_type,
           payload,
           :verified,
           signature_valid?: true,
           tenant_id: tenant_id
         ) do
      :ok ->
        # Mark as received first, then dispatch in the background.
        :ok = DeliveryLog.update_status(delivery_id, :received)
        Dispatcher.dispatch(delivery_id, webhook_id, event_type, payload, target)

        json(conn, %{
          status: "accepted",
          delivery_id: delivery_id,
          webhook_id: webhook_id,
          event_type: event_type,
          payload_size_bytes: byte_size(raw_body)
        })

      {:error, reason} ->
        reject(conn, 500, :persistence_failed, "Failed to record delivery: #{inspect(reason)}")
    end
  end

  # --------------------------------------------------------------------------

  defp read_raw_body(conn) do
    {:ok, body, _} = Plug.Conn.read_body(conn, length: @max_body_bytes)
    body || ""
  rescue
    _ -> ""
  end

  defp decode_payload(params, raw_body) do
    # Prefer parsed params; fall back to the raw JSON body if the
    # content-type didn't allow Phoenix to parse it.
    case Map.get(params, "payload") do
      nil ->
        case Jason.decode(raw_body) do
          {:ok, decoded} when is_map(decoded) -> decoded
          _ -> %{"_raw" => raw_body}
        end

      payload when is_map(payload) ->
        payload

      _ ->
        %{}
    end
  end

  defp record_rejected(webhook_id, tenant_id, event_type, raw_body, reason) do
    DeliveryLog.record(
      webhook_id,
      Event.generate_uuid(),
      event_type,
      decode_payload(%{}, raw_body),
      :rejected,
      signature_valid?: false,
      tenant_id: tenant_id,
      error: Atom.to_string(reason)
    )
  end

  defp reject(conn, status, code, detail) do
    conn
    |> put_status(status)
    |> json(%{
      type: "https://axiom.dev/errors/#{code}",
      title: code |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
      status: status,
      detail: detail
    })
  end
end
