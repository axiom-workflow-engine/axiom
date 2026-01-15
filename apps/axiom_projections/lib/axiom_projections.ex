defmodule AxiomProjections do
  @moduledoc """
  API & Observability Layer.

  Provides REST and GraphQL APIs for workflow management,
  monitoring, and chaos engineering operations.
  """

  alias Axiom.API.{Router, Health, Metrics}

  @doc """
  Returns the Plug router for use with Cowboy/Bandit.
  """
  def router, do: Router

  @doc """
  Runs health checks.
  """
  defdelegate health(), to: Health, as: :check_all

  @doc """
  Collects all metrics.
  """
  defdelegate metrics(), to: Metrics, as: :collect

  @doc """
  Returns Prometheus-formatted metrics.
  """
  defdelegate prometheus_metrics(), to: Metrics, as: :prometheus_format

  @doc """
  Starts the HTTP server on the specified port.
  """
  def start_server(port \\ 4000) do
    children = [
      {Bandit, plug: Router, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
  end
end
