defmodule AxiomProjections.MixProject do
  use Mix.Project

  def project do
    [
      app: :axiom_projections,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AxiomProjections.Application, []}
    ]
  end

  defp deps do
    [
      # Umbrella deps
      {:axiom_core, in_umbrella: true},
      {:axiom_wal, in_umbrella: true},
      {:axiom_engine, in_umbrella: true},
      {:axiom_scheduler, in_umbrella: true},
      {:axiom_chaos, in_umbrella: true},

      # HTTP server
      {:plug, "~> 1.14"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},

      # GraphQL
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"}
    ]
  end
end
