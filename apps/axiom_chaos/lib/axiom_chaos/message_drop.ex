defmodule Axiom.Chaos.MessageDrop do
  @moduledoc """
  Simulates message loss between processes.

  This simulates:
  - Network partitions
  - UDP packet loss
  - Overloaded mailboxes
  """

  @behaviour Axiom.Chaos.Scenario

  use GenServer
  require Logger

  defstruct [
    :drop_probability,
    :target_pids,
    drop_count: 0,
    active: true
  ]

  @default_drop_probability 0.2

  # ============================================================================
  # SCENARIO BEHAVIOUR
  # ============================================================================

  @impl Axiom.Chaos.Scenario
  def info do
    %{
      name: "message_drop",
      description: "Simulates message loss between processes",
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
  Wraps a send operation - may drop the message.
  Returns true if sent, false if dropped.
  """
  @spec maybe_send(pid(), any()) :: boolean()
  def maybe_send(target, message) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        send(target, message)
        true

      chaos_pid ->
        case GenServer.call(chaos_pid, {:should_drop, target}) do
          true ->
            false
          false ->
            send(target, message)
            true
        end
    end
  end

  @doc """
  Returns drop statistics.
  """
  @spec stats(pid()) :: %{drop_count: non_neg_integer()}
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    probability = Keyword.get(opts, :drop_probability, @default_drop_probability)
    target_pids = Keyword.get(opts, :target_pids, [])
    duration = Keyword.get(opts, :duration_ms, 30_000)

    state = %__MODULE__{
      drop_probability: probability,
      target_pids: target_pids
    }

    if duration > 0 do
      Process.send_after(self(), :auto_stop, duration)
    end

    Logger.warning("[Chaos:MessageDrop] Started - drop probability #{probability * 100}%")
    {:ok, state}
  end

  @impl true
  def handle_call({:should_drop, target}, _from, %{active: false} = state) do
    {:reply, false, state}
  end

  @impl true
  def handle_call({:should_drop, target}, _from, state) do
    # Only drop if target_pids is empty (drop all) or target is in list
    should_consider = state.target_pids == [] or target in state.target_pids

    should_drop = should_consider and :rand.uniform() < state.drop_probability

    new_state = if should_drop do
      Logger.debug("[Chaos:MessageDrop] Dropped message to #{inspect(target)}")
      %{state | drop_count: state.drop_count + 1}
    else
      state
    end

    {:reply, should_drop, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, %{drop_count: state.drop_count}, state}
  end

  @impl true
  def handle_info(:auto_stop, state) do
    Logger.info("[Chaos:MessageDrop] Duration complete. Dropped #{state.drop_count} messages")
    {:stop, :normal, %{state | active: false}}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("[Chaos:MessageDrop] Stopped. Total drops: #{state.drop_count}")
    :ok
  end
end
