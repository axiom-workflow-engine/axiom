import Config

defmodule Axiom.RuntimeEnv do
  @moduledoc false

  def fetch_int(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  def fetch_float(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_float(value)
    end
  end
end

if config_env() == :prod do
  port =
    "PORT"
    |> System.get_env("4000")
    |> String.to_integer()

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "missing required env var SECRET_KEY_BASE"

  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise "missing required env var JWT_SECRET"

  release_cookie =
    System.get_env("RELEASE_COOKIE") ||
      raise "missing required env var RELEASE_COOKIE"

  wal_data_dir = System.get_env("WAL_DATA_DIR", "/var/lib/axiom/wal")
  lease_duration_ms = Axiom.RuntimeEnv.fetch_int("LEASE_DURATION_MS", 30_000)
  worker_timeout_ms = Axiom.RuntimeEnv.fetch_int("WORKER_TIMEOUT_MS", 60_000)
  readiness_memory_ratio = Axiom.RuntimeEnv.fetch_float("READINESS_MAX_MEMORY_RATIO", 0.9)
  cors_origins = System.get_env("CORS_ORIGINS", "*") |> String.split(",")

  hammer_expiry_ms = Axiom.RuntimeEnv.fetch_int("HAMMER_EXPIRY_MS", 60_000)
  hammer_cleanup_interval_ms = Axiom.RuntimeEnv.fetch_int("HAMMER_CLEANUP_INTERVAL_MS", 60_000)

  config :axiom_gateway, AxiomGateway.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true,
    load_from_system_env: true

  config :axiom_gateway,
    jwt_secret: jwt_secret,
    cors_origins: cors_origins,
    readiness_max_memory_ratio: readiness_memory_ratio,
    release_cookie: release_cookie

  config :hammer,
    backend: {Hammer.Backend.ETS,
            [expiry_ms: hammer_expiry_ms,
             cleanup_interval_ms: hammer_cleanup_interval_ms]}

  config :axiom_wal,
    data_dir: wal_data_dir

  config :axiom_scheduler,
    lease_duration_ms: lease_duration_ms,
    worker_timeout_ms: worker_timeout_ms
end
