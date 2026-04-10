defmodule AxiomGateway.RuntimeChecks do
  @moduledoc """
  Runtime health and readiness checks for production probes.
  """

  @critical_processes [
    wal: Axiom.WAL.LogAppendServer,
    scheduler_dispatcher: Axiom.Scheduler.Dispatcher,
    scheduler_lease_manager: Axiom.Scheduler.LeaseManager,
    workflow_registry: Axiom.Engine.Registry
  ]

  @spec readiness() :: map()
  def readiness do
    process_checks =
      Enum.map(@critical_processes, fn {name, process_name} ->
        {name, process_status(process_name)}
      end)

    memory_check = memory_status()
    checks = process_checks ++ [memory: memory_check]
    failed = Enum.filter(checks, fn {_name, status} -> status != :ok end)

    %{
      status: if(failed == [], do: "ready", else: "not_ready"),
      checks: Map.new(checks, fn {name, status} -> {name, Atom.to_string(status)} end),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp process_status(process_name) do
    case Process.whereis(process_name) do
      pid when is_pid(pid) -> :ok
      _ -> :down
    end
  end

  defp memory_status do
    total = :erlang.memory(:total)
    limit = Application.get_env(:axiom_gateway, :memory_limit_bytes, 1_073_741_824)
    max_ratio = Application.get_env(:axiom_gateway, :readiness_max_memory_ratio, 0.9)
    ratio = total / limit

    if ratio < max_ratio, do: :ok, else: :memory_pressure
  end
end
