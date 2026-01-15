defmodule AxiomScheduler.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Axiom.Scheduler.LeaseManager, []},
      {Axiom.Scheduler.TaskQueue, []},
      {Axiom.Scheduler.Dispatcher, []}
    ]

    opts = [strategy: :one_for_one, name: AxiomScheduler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
