defmodule AxiomGateway.Controllers.WebhookController do
  use Phoenix.Controller

  def unquote(:receive)(conn, %{"webhook_id" => webhook_id} = params) do
    event_type = Map.get(params, "event_type", "unknown")
    payload = Map.get(params, "payload", %{})

    json(conn, %{
      status: "accepted",
      webhook_id: webhook_id,
      event_type: event_type,
      payload_size_bytes: payload |> Jason.encode!() |> byte_size()
    })
  end
end
