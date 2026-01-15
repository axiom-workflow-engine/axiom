defmodule Axiom.Chaos.ProcessKill do
  @moduledoc """
  Randomly kills GenServer processes.

  This simulates:
  - OOM kills
  - Hardware failures
  - Supervisor restarts
  """

  @behaviour Axiom.Chaos.Scenario

  use GenServer
  require Logger

  defstruct [
    :target_modules,
    :interval_ms,
    :kill_probability,
    kill_count: 0,
    active: true
  ]

  @default_interval 1_000
  @default_probability 0.3

  # ============================================================================
  # SCENARIO BEHAVIOUR
  # ============================================================================

  @impl Axiom.Chaos.Scenario
  def info do
    %{
      name: "process_kill",
      description: "Randomly terminates GenServer processes",
      default_duration_ms: 30_000
    }
  end

  @impl Axiom.Chaos.Scenario
  def start(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl Axiom.Chaos.Scenario
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Get statistics about kills performed.
  """
  @spec stats(pid()) :: %{kill_count: non_neg_integer()}
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    target_modules = Keyword.get(opts, :target_modules, [
      Axiom.Engine.WorkflowProcess,
      Axiom.Worker.Executor
    ])
    interval = Keyword.get(opts, :interval_ms, @default_interval)
    probability = Keyword.get(opts, :kill_probability, @default_probability)
    duration = Keyword.get(opts, :duration_ms, 30_000)

    state = %__MODULE__{
      target_modules: target_modules,
      interval_ms: interval,
      kill_probability: probability
    }

    # Schedule first kill attempt
    schedule_kill(interval)

    # Schedule auto-stop if duration specified
    if duration > 0 do
      Process.send_after(self(), :auto_stop, duration)
    end

    Logger.warning("[Chaos:ProcessKill] Started - targeting #{length(target_modules)} module types")
    {:ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{kill_count: state.kill_count}, state}
  end

  @impl true
  def handle_info(:kill_attempt, %{active: false} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:kill_attempt, state) do
    new_state = if :rand.uniform() < state.kill_probability do
      case find_random_target(state.target_modules) do
        nil ->
          state

        {pid, module} ->
          Logger.warning("[Chaos:ProcessKill] Killing #{inspect(module)} pid=#{inspect(pid)}")
          Process.exit(pid, :chaos_kill)
          %{state | kill_count: state.kill_count + 1}
      end
    else
      state
    end

    schedule_kill(state.interval_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:auto_stop, state) do
    Logger.info("[Chaos:ProcessKill] Duration complete. Killed #{state.kill_count} processes")
    {:stop, :normal, %{state | active: false}}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[Chaos:ProcessKill] Stopped. Total kills: #{state.kill_count}")
    :ok
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp schedule_kill(interval) do
    Process.send_after(self(), :kill_attempt, interval)
  end

  defp find_random_target(target_modules) do
    # Get all processes
    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} ->
          case Keyword.get(dict, :"$initial_call") do
            {mod, _fun, _arity} -> mod in target_modules
            _ -> false
          end
        _ ->
          false
      end
    end)
    |> case do
      [] -> nil
      pids ->
        pid = Enum.random(pids)
        {:dictionary, dict} = Process.info(pid, :dictionary)
        {mod, _, _} = Keyword.get(dict, :"$initial_call")
        {pid, mod}
    end
  end
end
