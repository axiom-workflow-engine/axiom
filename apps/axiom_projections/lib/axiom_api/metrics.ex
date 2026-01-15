defmodule Axiom.API.Metrics do
  @moduledoc """
  Metrics collection and export.
  """

  @doc """
  Collects all system metrics.
  """
  def collect do
    %{
      system: system_metrics(),
      wal: wal_metrics(),
      scheduler: scheduler_metrics(),
      engine: engine_metrics()
    }
  end

  @doc """
  Formats metrics in Prometheus format.
  """
  def prometheus_format do
    metrics = collect()

    lines = [
      "# HELP axiom_memory_bytes Total memory usage in bytes",
      "# TYPE axiom_memory_bytes gauge",
      "axiom_memory_bytes #{metrics.system.memory.total}",
      "",
      "# HELP axiom_process_count Number of Erlang processes",
      "# TYPE axiom_process_count gauge",
      "axiom_process_count #{metrics.system.processes.count}",
      "",
      "# HELP axiom_wal_offset Current WAL offset",
      "# TYPE axiom_wal_offset counter",
      "axiom_wal_offset #{metrics.wal.offset}",
      "",
      "# HELP axiom_queue_depth Number of tasks in queue",
      "# TYPE axiom_queue_depth gauge",
      "axiom_queue_depth #{metrics.scheduler.queue_depth}",
      "",
      "# HELP axiom_active_leases Number of active leases",
      "# TYPE axiom_active_leases gauge",
      "axiom_active_leases #{metrics.scheduler.active_leases}",
      "",
      "# HELP axiom_workers Number of registered workers",
      "# TYPE axiom_workers gauge",
      "axiom_workers #{metrics.scheduler.workers}"
    ]

    Enum.join(lines, "\n")
  end

  defp system_metrics do
    memory = :erlang.memory()

    %{
      memory: %{
        total: memory[:total],
        processes: memory[:processes],
        ets: memory[:ets],
        binary: memory[:binary]
      },
      processes: %{
        count: :erlang.system_info(:process_count),
        limit: :erlang.system_info(:process_limit)
      },
      schedulers: %{
        online: :erlang.system_info(:schedulers_online),
        total: :erlang.system_info(:schedulers)
      },
      uptime_ms: :erlang.statistics(:wall_clock) |> elem(0)
    }
  end

  defp wal_metrics do
    case GenServer.whereis(Axiom.WAL.LogAppendServer) do
      nil -> %{status: "not_running", offset: 0}
      pid ->
        offset = Axiom.WAL.LogAppendServer.current_offset(pid)
        %{status: "running", offset: offset}
    end
  rescue
    _ -> %{status: "error", offset: 0}
  end

  defp scheduler_metrics do
    case GenServer.whereis(Axiom.Scheduler.Dispatcher) do
      nil ->
        %{status: "not_running", queue_depth: 0, active_leases: 0, workers: 0}

      _pid ->
        queue_depth = Axiom.Scheduler.TaskQueue.depth()
        active_leases = length(Axiom.Scheduler.LeaseManager.list_active_leases())
        workers = length(Axiom.Scheduler.Dispatcher.list_workers())

        %{
          status: "running",
          queue_depth: queue_depth,
          active_leases: active_leases,
          workers: workers
        }
    end
  rescue
    _ -> %{status: "error", queue_depth: 0, active_leases: 0, workers: 0}
  end

  defp engine_metrics do
    # Would track workflow counts in production
    %{
      active_workflows: 0,
      completed_workflows: 0,
      failed_workflows: 0
    }
  end
end
