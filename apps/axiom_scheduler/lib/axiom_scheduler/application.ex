defmodule AxiomScheduler.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    lease_duration_ms = Application.get_env(:axiom_scheduler, :lease_duration_ms, 30_000)
    worker_timeout_ms = Application.get_env(:axiom_scheduler, :worker_timeout_ms, 60_000)

    children = [
      {Axiom.Scheduler.LeaseManager, [lease_duration_ms: lease_duration_ms]},
      {Axiom.Scheduler.TaskQueue, []},
      {Axiom.Scheduler.Dispatcher, [worker_timeout_ms: worker_timeout_ms]}
    ]

    opts = [strategy: :one_for_one, name: AxiomScheduler.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
