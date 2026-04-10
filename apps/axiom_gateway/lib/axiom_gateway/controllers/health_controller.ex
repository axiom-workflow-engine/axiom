defmodule AxiomGateway.Controllers.HealthController do
  use Phoenix.Controller

  def liveness(conn, _params) do
    json(conn, %{
      status: "alive",
      node: Node.self(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def readiness(conn, _params) do
    readiness = AxiomGateway.RuntimeChecks.readiness()

    if readiness.status == "ready" do
      json(conn, readiness)
    else
      conn
      |> put_status(:service_unavailable)
      |> json(readiness)
    end
  end
end
