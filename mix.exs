defmodule Axiom.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp releases do
    [
      axiom: [
        include_executables_for: [:unix],
        applications: [
          axiom_chaos: :permanent,
          axiom_core: :permanent,
          axiom_engine: :permanent,
          axiom_gateway: :permanent,
          axiom_projections: :permanent,
          axiom_scheduler: :permanent,
          axiom_wal: :permanent,
          axiom_worker: :permanent
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end
end
