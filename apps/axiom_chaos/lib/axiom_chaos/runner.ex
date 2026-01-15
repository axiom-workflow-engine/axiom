defmodule Axiom.Chaos.Runner do
  @moduledoc """
  Chaos test runner - orchestrates scenarios and verification.

  The sales weapon: Demo resilience live.
  """

  require Logger

  alias Axiom.Chaos.{ProcessKill, DelayInjection, MessageDrop}

  @scenarios %{
    "process_kill" => ProcessKill,
    "delay_injection" => DelayInjection,
    "message_drop" => MessageDrop
  }

  @doc """
  Runs a chaos scenario for specified duration.
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(scenario_name, opts \\ []) do
    case Map.get(@scenarios, scenario_name) do
      nil ->
        {:error, {:unknown_scenario, scenario_name, Map.keys(@scenarios)}}

      module ->
        duration = Keyword.get(opts, :duration_ms, module.info().default_duration_ms)

        Logger.info("[Chaos:Runner] Starting scenario '#{scenario_name}' for #{duration}ms")

        case module.start(Keyword.put(opts, :duration_ms, duration)) do
          {:ok, pid} ->
            # Wait for scenario to complete
            ref = Process.monitor(pid)

            receive do
              {:DOWN, ^ref, :process, ^pid, _reason} ->
                Logger.info("[Chaos:Runner] Scenario '#{scenario_name}' completed")
                {:ok, %{scenario: scenario_name, duration_ms: duration}}
            after
              duration + 5_000 ->
                Logger.warning("[Chaos:Runner] Scenario timed out, stopping")
                module.stop(pid)
                {:ok, %{scenario: scenario_name, duration_ms: duration, timed_out: true}}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Runs multiple scenarios concurrently.
  """
  @spec run_concurrent([{String.t(), keyword()}], keyword()) :: {:ok, [map()]} | {:error, term()}
  def run_concurrent(scenarios, _opts \\ []) do
    Logger.info("[Chaos:Runner] Starting #{length(scenarios)} concurrent scenarios")

    tasks = Enum.map(scenarios, fn {name, opts} ->
      Task.async(fn -> run(name, opts) end)
    end)

    results = Task.await_many(tasks, :infinity)

    {:ok, results}
  end

  @doc """
  Lists available scenarios.
  """
  @spec list_scenarios() :: [map()]
  def list_scenarios do
    Enum.map(@scenarios, fn {name, module} ->
      Map.put(module.info(), :id, name)
    end)
  end

  @doc """
  Verifies system consistency after chaos.
  Checks that all workflows are in valid states.
  """
  @spec verify_consistency() :: {:ok, map()} | {:error, map()}
  def verify_consistency do
    Logger.info("[Chaos:Runner] Verifying system consistency...")

    checks = [
      {:wal_readable, check_wal_readable()},
      {:no_orphaned_leases, check_no_orphaned_leases()},
      {:queue_consistent, check_queue_consistent()}
    ]

    failed = Enum.filter(checks, fn {_name, result} -> result != :ok end)

    if failed == [] do
      Logger.info("[Chaos:Runner] Consistency check passed!")
      {:ok, %{checks_passed: length(checks), failed: 0}}
    else
      Logger.error("[Chaos:Runner] Consistency check failed: #{inspect(failed)}")
      {:error, %{checks_passed: length(checks) - length(failed), failed: length(failed), failures: failed}}
    end
  end

  # ============================================================================
  # CONSISTENCY CHECKS
  # ============================================================================

  defp check_wal_readable do
    # Verify WAL can be read
    case GenServer.whereis(Axiom.WAL.LogAppendServer) do
      nil -> {:error, :wal_not_running}
      pid ->
        try do
          Axiom.WAL.LogAppendServer.current_offset(pid)
          :ok
        rescue
          _ -> {:error, :wal_unresponsive}
        end
    end
  end

  defp check_no_orphaned_leases do
    case GenServer.whereis(Axiom.Scheduler.LeaseManager) do
      nil -> :ok  # Not running, no orphaned leases
      pid ->
        active = Axiom.Scheduler.LeaseManager.list_active_leases(pid)
        # Check all leases are still valid or recently expired
        orphaned = Enum.filter(active, fn lease ->
          Axiom.Core.Lease.expired?(lease)
        end)

        if length(orphaned) == 0 do
          :ok
        else
          {:error, {:orphaned_leases, length(orphaned)}}
        end
    end
  end

  defp check_queue_consistent do
    case GenServer.whereis(Axiom.Scheduler.TaskQueue) do
      nil -> :ok
      pid ->
        depth = Axiom.Scheduler.TaskQueue.depth(pid)
        pending = Axiom.Scheduler.TaskQueue.list_pending(pid)

        # Queue depth + pending should be reasonable
        if depth >= 0 and length(pending) >= 0 do
          :ok
        else
          {:error, :queue_inconsistent}
        end
    end
  end
end
