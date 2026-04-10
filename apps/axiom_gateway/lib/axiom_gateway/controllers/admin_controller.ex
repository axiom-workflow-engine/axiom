defmodule AxiomGateway.Controllers.AdminController do
  use Phoenix.Controller

  action_fallback AxiomGateway.Controllers.FallbackController

  def run_chaos(conn, %{"scenario" => scenario} = params) do
    duration_ms = Map.get(params, "duration_ms", 10_000)

    if Code.ensure_loaded?(AxiomChaos) and function_exported?(AxiomChaos, :run, 2) do
      Task.start(fn -> AxiomChaos.run(scenario, duration_ms: duration_ms) end)
      json(conn, %{status: "started", scenario: scenario, duration_ms: duration_ms})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "Chaos module unavailable"})
    end
  end

  def run_chaos(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required field: scenario"})
  end

  def verify_consistency(conn, _params) do
    if Code.ensure_loaded?(AxiomChaos) and function_exported?(AxiomChaos, :verify, 0) do
      case AxiomChaos.verify() do
        {:ok, result} ->
          json(conn, %{status: "passed", data: result})

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{status: "failed", error: inspect(reason)})
      end
    else
      json(conn, %{status: "unknown", reason: "consistency verifier unavailable"})
    end
  end
end
