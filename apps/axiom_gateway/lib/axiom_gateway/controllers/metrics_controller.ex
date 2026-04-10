defmodule AxiomGateway.Controllers.MetricsController do
  use Phoenix.Controller

  def index(conn, _params) do
    metrics =
      if Code.ensure_loaded?(Axiom.API.Metrics) and function_exported?(Axiom.API.Metrics, :collect, 0) do
        Axiom.API.Metrics.collect()
      else
        fallback_metrics()
      end

    json(conn, %{data: metrics})
  end

  def prometheus(conn, _params) do
    payload =
      if Code.ensure_loaded?(Axiom.API.Metrics) and
           function_exported?(Axiom.API.Metrics, :prometheus_format, 0) do
        Axiom.API.Metrics.prometheus_format()
      else
        """
        # HELP axiom_gateway_up Gateway process availability
        # TYPE axiom_gateway_up gauge
        axiom_gateway_up 1
        """
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, payload)
  end

  defp fallback_metrics do
    %{
      node: to_string(Node.self()),
      memory_bytes: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count),
      scheduler_count: :erlang.system_info(:schedulers_online)
    }
  end
end
