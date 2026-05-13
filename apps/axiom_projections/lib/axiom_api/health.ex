defmodule Axiom.API.Health do
  @moduledoc """
  Health check endpoints for load balancers and orchestrators.
  """

  @doc """
  Runs all health checks and returns status.
  """
  def check_all do
    checks = [
      {:wal, check_wal()},
      {:scheduler, check_scheduler()},
      {:memory, check_memory()}
    ]

    failed = Enum.filter(checks, fn {_name, status} -> status != :ok end)

    %{
      healthy: failed == [],
      checks:
        Map.new(checks, fn {name, status} ->
          {name, if(status == :ok, do: "ok", else: "failed")}
        end),
      timestamp: System.system_time(:millisecond)
    }
  end

  defp check_wal do
    case GenServer.whereis(Axiom.WAL.LogAppendServer) do
      nil -> :error
      _pid -> :ok
    end
  end

  defp check_scheduler do
    case GenServer.whereis(Axiom.Scheduler.Dispatcher) do
      nil -> :error
      _pid -> :ok
    end
  end

  defp check_memory do
    total_memory = :erlang.memory(:total)

    # Default limit of 2GB if not specified elsewhere
    limit = Application.get_env(:axiom_projections, :memory_limit_bytes, 2_147_483_648)

    if total_memory < limit * 0.9, do: :ok, else: :error
  end
end
