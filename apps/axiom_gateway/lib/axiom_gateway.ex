defmodule AxiomGateway do
  @moduledoc """
  Axiom API Gateway - Durable ingress layer for the Axiom Workflow Engine.

  The gateway provides:
  - Protocol unification (REST & GraphQL → internal request model)
  - Durability guarantees (requests are fsync'd before acknowledgment)
  - Security enforcement (authentication, authorization, rate limiting)
  - Schema governance (workflow definition validation)

  ## Core Guarantee

  A `200 OK` from the gateway means the request is persisted and will be
  processed exactly once, even if the gateway crashes immediately after.

  ## Architecture

      ┌─────────────────────────────────────────────────────────────────┐
      │                     CLIENTS (REST / GraphQL)                    │
      └───────────────────────────┬─────────────────────────────────────┘
                                  │
      ┌───────────────────────────▼─────────────────────────────────────┐
      │                   API GATEWAY (Phoenix Application)             │
      │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                │
      │  │  Protocol   │ │  Schema     │ │   Durable   │                │
      │  │  Router     │ │  Registry   │ │   Acceptor  │                │
      │  └─────────────┘ └─────────────┘ └─────────────┘                │
      └───────────────────────────┬─────────────────────────────────────┘
                                  │
      ┌───────────────────────────▼─────────────────────────────────────┐
      │              WORKFLOW ENGINE (axiom_engine)                     │
      └─────────────────────────────────────────────────────────────────┘
  """

  @doc """
  Returns the current gateway version.
  """
  def version, do: "0.1.0"

  @doc """
  Returns gateway configuration.
  """
  def config do
    Application.get_all_env(:axiom_gateway)
  end

  @doc """
  Returns paths for static assets.
  """
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
