defmodule AxiomGateway.Application do
  @moduledoc """
  OTP Application for the Axiom API Gateway.

  Supervises:
  - Telemetry supervisor
  - Phoenix PubSub
  - Idempotency cache (ETS-backed)
  - Rate limiter
  - Durable acceptor
  - Phoenix Endpoint (HTTP server)
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("[Gateway] Starting Axiom API Gateway...")

    children = [
      # Telemetry supervisor
      AxiomGateway.Telemetry,

      # Cluster Supervisor (Local/Gossip/K8s)
      {Cluster.Supervisor, [topologies(), [name: AxiomGateway.ClusterSupervisor]]},

      # PubSub for real-time events
      {Phoenix.PubSub, name: AxiomGateway.PubSub},

      # Idempotency key cache (Mnesia-backed)
      AxiomGateway.IdempotencyCache,

      # Secure API Key Store (Mnesia-backed)
      AxiomGateway.Auth.ApiKeyStore,

      # Schema Registry (Mnesia-backed)
      AxiomGateway.Schemas.Store,

      # Rate limiter state
      AxiomGateway.RateLimiter,

      # Durable request acceptor
      AxiomGateway.Durable.Acceptor,

      # Phoenix HTTP endpoint (must be last)
      AxiomGateway.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AxiomGateway.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("[Gateway] Axiom API Gateway started successfully")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("[Gateway] Failed to start: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    AxiomGateway.Endpoint.config_change(changed, removed)
    :ok
  end

  defp topologies do
    [
      axiom: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: []]
      ]
    ]
  end
end
