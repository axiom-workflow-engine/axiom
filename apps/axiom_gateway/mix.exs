defmodule AxiomGateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :axiom_gateway,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {AxiomGateway.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:cors_plug, "~> 3.0"},

      # Authentication
      {:joken, "~> 2.6"},

      # Rate Limiting
      {:hammer, "~> 6.2"},

      # GraphQL
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},

      # Schema Validation
      {:ex_json_schema, "~> 0.9"},

      # Observability
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},

      # Clustering & Distribution
      {:libcluster, "~> 3.3"},
      {:libring, "~> 1.7"},

      # Internal dependencies
      {:axiom_core, in_umbrella: true},
      {:axiom_engine, in_umbrella: true},
      {:axiom_wal, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
