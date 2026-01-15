defmodule Axiom.API.GraphQL.MetricsResolver do
  @moduledoc """
  GraphQL resolvers for metrics queries.
  """

  alias Axiom.API.Metrics

  def get(_parent, _args, _context) do
    metrics = Metrics.collect()

    {:ok, %{
      system: %{
        memory_total: metrics.system.memory.total,
        memory_processes: metrics.system.memory.processes,
        process_count: metrics.system.processes.count,
        schedulers_online: metrics.system.schedulers.online,
        uptime_ms: metrics.system.uptime_ms
      },
      wal: metrics.wal,
      scheduler: metrics.scheduler,
      engine: metrics.engine
    }}
  end
end
