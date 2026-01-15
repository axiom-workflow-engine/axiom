defmodule Axiom.Chaos.DelayInjection do
  @moduledoc """
  Injects random delays into process message handling.

  This simulates:
  - Network latency
  - Disk I/O delays
  - CPU contention
  """

  @behaviour Axiom.Chaos.Scenario

  use GenServer
  require Logger

  defstruct [
    :min_delay_ms,
    :max_delay_ms,
    :target_messages,
    injection_count: 0,
    active: true
  ]

  @default_min_delay 50
  @default_max_delay 500

  # ============================================================================
  # SCENARIO BEHAVIOUR
  # ============================================================================

  @impl Axiom.Chaos.Scenario
  def info do
    %{
      name: "delay_injection",
      description: "Injects random delays into system operations",
      default_duration_ms: 30_000
    }
  end

  @impl Axiom.Chaos.Scenario
  def start(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Axiom.Chaos.Scenario
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Applies delay if chaos is active.
  Call this in hot paths to simulate latency.
  """
  @spec maybe_delay() :: :ok
  def maybe_delay do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, :maybe_delay)
    end
  end

  @doc """
  Returns injection statistics.
  """
  @spec stats(pid()) :: %{injection_count: non_neg_integer()}
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    min_delay = Keyword.get(opts, :min_delay_ms, @default_min_delay)
    max_delay = Keyword.get(opts, :max_delay_ms, @default_max_delay)
    duration = Keyword.get(opts, :duration_ms, 30_000)

    state = %__MODULE__{
      min_delay_ms: min_delay,
      max_delay_ms: max_delay
    }

    if duration > 0 do
      Process.send_after(self(), :auto_stop, duration)
    end

    Logger.warning("[Chaos:DelayInjection] Started - delays #{min_delay}-#{max_delay}ms")
    {:ok, state}
  end

  @impl true
  def handle_call(:maybe_delay, _from, %{active: false} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:maybe_delay, _from, state) do
    delay = :rand.uniform(state.max_delay_ms - state.min_delay_ms) + state.min_delay_ms
    Process.sleep(delay)

    new_state = %{state | injection_count: state.injection_count + 1}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{injection_count: state.injection_count}, state}
  end

  @impl true
  def handle_info(:auto_stop, state) do
    Logger.info("[Chaos:DelayInjection] Duration complete. Injected #{state.injection_count} delays")
    {:stop, :normal, %{state | active: false}}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[Chaos:DelayInjection] Stopped. Total injections: #{state.injection_count}")
    :ok
  end
end
