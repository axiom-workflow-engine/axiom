defmodule Axiom.Scheduler.LeaseManager do
  @moduledoc """
  THE CLOCK POLICE - Logical time, fencing tokens.

  No system trusts wall clocks. Leases are time-bounded, not trust-based.

  Responsibilities:
  - Issue leases with fencing tokens
  - Track active leases
  - Expire stale leases
  - Reject results from expired leases
  """

  use GenServer
  require Logger

  alias Axiom.Core.Lease

  defstruct [
    :name,
    active_leases: %{},          # %{lease_id => Lease.t()}
    fencing_tokens: %{},         # %{{workflow_id, step} => current_token}
    lease_duration_ms: 30_000
  ]

  @type t :: %__MODULE__{
          name: atom(),
          active_leases: %{binary() => Lease.t()},
          fencing_tokens: %{{binary(), atom()} => non_neg_integer()},
          lease_duration_ms: non_neg_integer()
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Acquires a lease for a task. Returns the new lease with fencing token.
  """
  @spec acquire_lease(GenServer.server(), binary(), atom(), pos_integer()) ::
          {:ok, Lease.t()} | {:error, term()}
  def acquire_lease(server \\ __MODULE__, workflow_id, step, attempt) do
    GenServer.call(server, {:acquire_lease, workflow_id, step, attempt})
  end

  @doc """
  Checks if a lease is still valid.
  """
  @spec check_lease(GenServer.server(), binary()) :: :lease_valid | :lease_expired | :lease_unknown
  def check_lease(server \\ __MODULE__, lease_id) do
    GenServer.call(server, {:check_lease, lease_id})
  end

  @doc """
  Validates a lease and fencing token for commit.
  Returns :ok if valid, error otherwise.
  """
  @spec validate_for_commit(GenServer.server(), binary(), non_neg_integer()) ::
          :ok | {:error, :lease_expired | :fencing_token_stale | :lease_unknown}
  def validate_for_commit(server \\ __MODULE__, lease_id, fencing_token) do
    GenServer.call(server, {:validate_for_commit, lease_id, fencing_token})
  end

  @doc """
  Releases a lease after successful commit.
  """
  @spec release_lease(GenServer.server(), binary()) :: :ok
  def release_lease(server \\ __MODULE__, lease_id) do
    GenServer.cast(server, {:release_lease, lease_id})
  end

  @doc """
  Gets the current fencing token for a workflow step.
  """
  @spec get_fencing_token(GenServer.server(), binary(), atom()) :: non_neg_integer()
  def get_fencing_token(server \\ __MODULE__, workflow_id, step) do
    GenServer.call(server, {:get_fencing_token, workflow_id, step})
  end

  @doc """
  Lists all active leases.
  """
  @spec list_active_leases(GenServer.server()) :: [Lease.t()]
  def list_active_leases(server \\ __MODULE__) do
    GenServer.call(server, :list_active_leases)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    lease_duration = Keyword.get(opts, :lease_duration_ms, 30_000)
    name = Keyword.get(opts, :name, __MODULE__)

    # Schedule periodic cleanup of expired leases
    schedule_cleanup()

    state = %__MODULE__{
      name: name,
      lease_duration_ms: lease_duration
    }

    Logger.info("[LeaseManager] Started with #{lease_duration}ms lease duration")
    {:ok, state}
  end

  @impl true
  def handle_call({:acquire_lease, workflow_id, step, attempt}, _from, state) do
    key = {workflow_id, step}

    # Increment fencing token
    current_token = Map.get(state.fencing_tokens, key, 0)
    new_token = current_token + 1

    # Create new lease
    lease = Lease.new(workflow_id, step, attempt, new_token,
      duration_ms: state.lease_duration_ms
    )

    # Update state
    new_state = %{state |
      active_leases: Map.put(state.active_leases, lease.lease_id, lease),
      fencing_tokens: Map.put(state.fencing_tokens, key, new_token)
    }

    Logger.debug("[LeaseManager] Lease acquired: #{short_id(lease.lease_id)} for #{workflow_id}:#{step} (token=#{new_token})")
    {:reply, {:ok, lease}, new_state}
  end

  @impl true
  def handle_call({:check_lease, lease_id}, _from, state) do
    result = case Map.get(state.active_leases, lease_id) do
      nil -> :lease_unknown
      lease -> if Lease.valid?(lease), do: :lease_valid, else: :lease_expired
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:validate_for_commit, lease_id, fencing_token}, _from, state) do
    result = case Map.get(state.active_leases, lease_id) do
      nil ->
        {:error, :lease_unknown}

      lease ->
        current_highest = Map.get(state.fencing_tokens, {lease.workflow_id, lease.step}, 0)

        cond do
          Lease.expired?(lease) ->
            {:error, :lease_expired}

          lease.fencing_token != fencing_token ->
            {:error, :fencing_token_stale}

          fencing_token < current_highest ->
            {:error, :fencing_token_stale}

          true ->
            :ok
        end
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_fencing_token, workflow_id, step}, _from, state) do
    token = Map.get(state.fencing_tokens, {workflow_id, step}, 0)
    {:reply, token, state}
  end

  @impl true
  def handle_call(:list_active_leases, _from, state) do
    active = state.active_leases
      |> Map.values()
      |> Enum.filter(&Lease.valid?/1)
    {:reply, active, state}
  end

  @impl true
  def handle_cast({:release_lease, lease_id}, state) do
    new_state = %{state | active_leases: Map.delete(state.active_leases, lease_id)}
    Logger.debug("[LeaseManager] Lease released: #{short_id(lease_id)}")
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    # Remove expired leases
    {expired, active} = state.active_leases
      |> Enum.split_with(fn {_id, lease} -> Lease.expired?(lease) end)

    if length(expired) > 0 do
      Logger.info("[LeaseManager] Cleaned up #{length(expired)} expired leases")
    end

    new_state = %{state | active_leases: Map.new(active)}

    schedule_cleanup()
    {:noreply, new_state}
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, 5_000)
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "unknown"
end
