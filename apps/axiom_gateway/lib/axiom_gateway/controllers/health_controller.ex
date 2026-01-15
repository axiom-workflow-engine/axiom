defmodule AxiomGateway.Controllers.HealthController do
  use Phoenix.Controller

  def liveness(conn, _params) do
    json(conn, %{status: "alive"})
  end

  def readiness(conn, _params) do
    # Verify critical dependencies are up
    case Process.whereis(Axiom.WAL.LogAppendServer) do
      pid when is_pid(pid) ->
        json(conn, %{status: "ready", wal: "connected"})
      nil ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "not_ready", error: "WAL service offline"})
    end
  end
end
