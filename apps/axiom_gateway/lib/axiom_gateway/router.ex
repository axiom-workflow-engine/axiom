defmodule AxiomGateway.Router do
  @moduledoc """
  Phoenix Router for the Axiom API Gateway.

  Routes are organized into:
  - Health checks (unauthenticated)
  - API v1 (authenticated)
  - Metrics (configurable authentication)
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  # Pipelines
  pipeline :api do
    plug :accepts, ["json"]
    plug AxiomGateway.Plugs.RequestLogger
  end

  pipeline :authenticated do
    plug AxiomGateway.Plugs.Auth
    plug AxiomGateway.Plugs.RateLimiter
  end

  pipeline :idempotent do
    plug AxiomGateway.Plugs.Idempotency
  end

  # Health checks (unauthenticated)
  scope "/", AxiomGateway.Controllers do
    pipe_through :api

    get "/health", HealthController, :liveness
    get "/ready", HealthController, :readiness
  end

  # API v1
  scope "/api/v1", AxiomGateway.Controllers do
    pipe_through [:api, :authenticated]

    # Metrics (read-only)
    get "/metrics", MetricsController, :index
    get "/metrics/prometheus", MetricsController, :prometheus

    # Tasks (read-only)
    get "/tasks", TaskController, :index
    get "/tasks/:id", TaskController, :show

    # Workflows (read)
    get "/workflows", WorkflowController, :index
    get "/workflows/:id", WorkflowController, :show
    get "/workflows/:id/events", WorkflowController, :events

    # Workflows (write - idempotent)
    pipe_through :idempotent

    post "/workflows", WorkflowController, :create
    post "/workflows/bulk", WorkflowController, :bulk_create
    post "/workflows/:id/cancel", WorkflowController, :cancel
    post "/workflows/:id/advance", WorkflowController, :advance

    # Data plane (worker operations)
    get "/workflows/:id/lease", WorkflowController, :lease
    post "/workflows/:id/result", WorkflowController, :submit_result

    # Schemas
    get "/schemas/workflows", SchemaController, :index
    get "/schemas/workflows/:name", SchemaController, :show
    post "/schemas/workflows", SchemaController, :create

    # Admin operations
    post "/chaos/run", AdminController, :run_chaos
    post "/verify", AdminController, :verify_consistency

    # Cluster Ops
    get "/sys/cluster", ClusterController, :index
    post "/sys/cluster/join", ClusterController, :join
  end

  # Webhooks (separate auth)
  scope "/api/v1/webhooks", AxiomGateway.Controllers do
    pipe_through :api

    post "/:webhook_id", WebhookController, :receive
  end

  # OpenAPI specification
  scope "/api/v1", AxiomGateway.Controllers do
    pipe_through :api

    get "/openapi.json", OpenApiController, :spec
  end

  # GraphQL
  pipeline :graphql do
    plug AxiomGateway.GraphQL.Context
  end

  scope "/graphql" do
    pipe_through [:api, :authenticated, :graphql]

    forward "/", Absinthe.Plug,
      schema: AxiomGateway.GraphQL.Schema
  end

  # GraphiQL (interface)
  if Mix.env() == :dev do
    scope "/graphiql" do
      pipe_through [:api, :graphql] # Relaxed auth for dev UI? Or require basic auth?
                                    # For dev, we often skip strict auth or mock it.
                                    # Let's keep it open or assume dev has headers.

      forward "/", Absinthe.Plug.GraphiQL,
        schema: AxiomGateway.GraphQL.Schema,
        interface: :playground
    end
  end

  # Catch-all for 404
  match :*, "/*path", AxiomGateway.Controllers.FallbackController, :not_found
end
