# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :logger, :default_handler,
  level: :info

config :logger, :default_formatter,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:request_id, :workflow_id, :worker_id]

config :phoenix, :json_library, Jason

config :axiom_wal,
  data_dir: "./data/wal"

config :axiom_scheduler,
  lease_duration_ms: 30_000,
  worker_timeout_ms: 60_000

config :axiom_gateway,
  enforce_auth: true,
  readiness_max_memory_ratio: 0.9,
  jwt_secret: nil,
  cors_origins: ["*"]

config :axiom_gateway, AxiomGateway.Endpoint,
  url: [host: "localhost"],
  pubsub_server: AxiomGateway.PubSub,
  secret_key_base: "change-me-dev-secret-key-base",
  server: true,
  load_from_system_env: true
