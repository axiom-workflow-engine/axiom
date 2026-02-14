defmodule AxiomGateway.Endpoint do
  @moduledoc """
  Phoenix Endpoint for the Axiom API Gateway.

  Handles HTTP/HTTPS connections, WebSocket upgrades for subscriptions,
  and serves as the entry point for all gateway traffic.
  """

  use Phoenix.Endpoint, otp_app: :axiom_gateway

  # Session configuration (for potential web UI)
  @session_options [
    store: :cookie,
    key: "_axiom_gateway_key",
    signing_salt: "axiom_gateway_salt",
    same_site: "Lax"
  ]

  # Serve static assets if needed
  plug Plug.Static,
    at: "/",
    from: :axiom_gateway,
    gzip: false,
    only: AxiomGateway.static_paths()

  # Request ID for tracing
  plug Plug.RequestId

  # Telemetry for request timing
  plug Plug.Telemetry, event_prefix: [:axiom, :gateway, :endpoint]

  # Parse request body
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: 10_000_000  # 10MB max body

  # Method override for HTML forms
  plug Plug.MethodOverride

  # Enable sessions
  plug Plug.Session, @session_options

  # CORS for cross-origin requests
  plug CORSPlug,
    origin: &AxiomGateway.Endpoint.cors_origins/0,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    headers: ["Authorization", "Content-Type", "X-Api-Key", "Idempotency-Key", "X-Request-Id"]

  # Main router
  plug AxiomGateway.Router

  @doc """
  Returns allowed CORS origins from configuration.
  """
  def cors_origins do
    Application.get_env(:axiom_gateway, :cors_origins, ["*"])
  end

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: String.to_integer(port)])}
    else
      {:ok, config}
    end
  end
end
