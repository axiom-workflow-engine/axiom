defmodule AxiomGateway.Webhooks.Dispatcher do
  @moduledoc """
  Fan-out and signature verification for inbound webhooks.

  Each webhook has its own secret, stored hashed in the registry.
  External systems sign payloads with `HMAC-SHA256(secret, body)` and
  send the hex digest in `X-Webhook-Signature: sha256=<hex>`.

  Verified deliveries are persisted to the durable log, then
  dispatched to the engine in a background task so the HTTP
  handler can return 202 quickly. Dispatch failures do not
  propagate to the caller — the delivery is durably recorded and
  the engine can re-replay from the WAL when the workflow starts.
  """

  require Logger

  alias AxiomGateway.Webhooks.{Registry, DeliveryLog}
  alias Axiom.Core.Event

  @signature_prefix "sha256="

  @doc """
  Verifies the HMAC-SHA256 signature on a raw webhook body against
  the per-webhook secret stored in the registry.

  Returns `{:ok, raw_body}` on success. The provided `raw_body` is
  echoed back so callers can use it without re-reading the conn.
  """
  @spec verify(String.t(), String.t() | nil, String.t()) ::
          {:ok, String.t()} | {:error, :not_found | :missing_signature | :invalid_signature | :malformed_signature}
  def verify(webhook_id, signature_header, raw_body) do
    with {:ok, secret} <- fetch_secret(webhook_id),
         {:ok, provided_hex} <- parse_signature(signature_header) do
      expected = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

      if Plug.Crypto.secure_compare(expected, String.downcase(provided_hex)) do
        {:ok, raw_body}
      else
        {:error, :invalid_signature}
      end
    end
  end

  @doc """
  Spawns a background task to dispatch a verified webhook to the engine.
  Returns `:ok` immediately. The task records its own status updates
  on the delivery log.
  """
  @spec dispatch(String.t(), String.t(), String.t(), map(), String.t() | nil) :: :ok
  def dispatch(delivery_id, webhook_id, event_type, payload, target_workflow) do
    parent = self()

    Task.start(fn ->
      result = do_dispatch(webhook_id, event_type, payload, target_workflow)

      case result do
        :ok ->
          DeliveryLog.update_status(delivery_id, :dispatched)

        {:error, reason} ->
          Logger.warning("[Webhook:#{webhook_id}] Dispatch failed: #{inspect(reason)}")
          DeliveryLog.update_status(delivery_id, :failed, error: inspect(reason))
      end

      send(parent, {:webhook_dispatched, delivery_id})
    end)

    :ok
  end

  # --------------------------------------------------------------------------
  # Internal
  # --------------------------------------------------------------------------

  defp fetch_secret(webhook_id) do
    case Registry.fetch_secret(webhook_id) do
      nil ->
        case Registry.lookup(webhook_id) do
          {:ok, _} -> {:error, :invalid_signature}
          {:error, :not_found} -> {:error, :not_found}
        end

      secret ->
        {:ok, secret}
    end
  end

  defp parse_signature(@signature_prefix <> hex) when byte_size(hex) == 64 do
    {:ok, hex}
  end

  defp parse_signature(@signature_prefix <> _), do: {:error, :malformed_signature}
  defp parse_signature(nil), do: {:error, :missing_signature}
  defp parse_signature(""), do: {:error, :missing_signature}
  defp parse_signature(_), do: {:error, :malformed_signature}

  defp do_dispatch(webhook_id, _event_type, payload, target_workflow) do
    cond do
      is_nil(target_workflow) or target_workflow == "" ->
        Logger.info("[Webhook:#{webhook_id}] No target workflow declared; recording only")
        :ok

      true ->
        workflow_id = derive_workflow_id(target_workflow, payload)

        case Registry.lookup(Axiom.Engine.Registry, workflow_id) do
          [{pid, _}] ->
            # Workflow is running. Advance it so the engine pulls the
            # next step from the queue. Errors other than :no_runnable_step
            # (e.g. already terminal) are surfaced so the delivery log
            # captures them.
            case Axiom.Engine.WorkflowProcess.advance(pid) do
              :ok -> :ok
              {:error, :no_runnable_step} -> :ok
              {:error, reason} -> {:error, reason}
            end

          [] ->
            # Workflow not running; delivery is durably persisted in the
            # log. The engine can re-replay from the WAL on hydrate.
            Logger.info(
              "[Webhook:#{webhook_id}] Workflow #{workflow_id} not running; delivery recorded for later replay"
            )

            :ok
        end
    end
  end

  # If the payload includes an explicit workflow_id, use it. Otherwise
  # derive a deterministic id from (target_workflow, event_type) so
  # re-deliveries hit the same workflow.
  defp derive_workflow_id(target_workflow, payload) when is_map(payload) do
    case Map.get(payload, "workflow_id") do
      id when is_binary(id) and byte_size(id) > 0 ->
        id

      _ ->
        hash = :crypto.hash(:sha256, "#{target_workflow}:#{Map.get(payload, "event_type", "")}")
        "wh_" <> binary_part(Base.encode16(hash, case: :lower), 0, 32)
    end
  end

  defp derive_workflow_id(target_workflow, _), do: "wh_#{target_workflow}"
end
