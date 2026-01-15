defmodule AxiomWorker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for worker processes
      {Registry, keys: :unique, name: Axiom.Worker.Registry}
    ]

    opts = [strategy: :one_for_one, name: AxiomWorker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
