defmodule AxiomCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :axiom_cli,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  def escript do
    [main_module: AxiomCli]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:axiom_core, in_umbrella: true},
      {:axiom_wal, in_umbrella: true},
      {:axiom_scheduler, in_umbrella: true},
      {:axiom_chaos, in_umbrella: true}
    ]
  end
end
