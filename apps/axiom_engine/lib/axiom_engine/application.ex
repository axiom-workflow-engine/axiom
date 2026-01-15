defmodule AxiomEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for workflow processes
      {Registry, keys: :unique, name: Axiom.Engine.Registry},
      # Dynamic supervisor for workflows
      {Axiom.Engine.WorkflowSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: AxiomEngine.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
