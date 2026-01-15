defmodule Axiom.Scheduler.Dispatcher do
  @moduledoc """
  THE DEALER - Schedulers do not execute. They assign leases.

  Responsibilities:
  - Match runnable steps to workers
  - Enforce single-owner execution via leases
  - Handle task completion/failure routing
  """

  use GenServer
  require Logger

  alias Axiom.Scheduler.{LeaseManager, TaskQueue}
  alias Axiom.Core.Event

  defstruct [
    :task_queue,
    :lease_manager,
    workers: %{},           # %{worker_id => %{status, last_heartbeat, current_task}}
    worker_timeout_ms: 60_000
  ]

  @type worker_info :: %{
          status: :idle | :busy,
          last_heartbeat: non_neg_integer(),
          current_task: binary() | nil
        }

  @type t :: %__MODULE__{
          task_queue: GenServer.server(),
          lease_manager: GenServer.server(),
          workers: %{binary() => worker_info()},
          worker_timeout_ms: non_neg_integer()
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Schedules a step for execution.
  """
  @spec schedule_step(GenServer.server(), binary(), atom(), pos_integer()) :: {:ok, binary()}
  def schedule_step(server \\ __MODULE__, workflow_id, step, attempt) do
    GenServer.call(server, {:schedule_step, workflow_id, step, attempt})
  end

  @doc """
  Worker requests a task. Returns task with lease if available.
  """
  @spec request_task(GenServer.server(), binary()) ::
          {:task_lease, map(), Axiom.Core.Lease.t()} | :no_task
  def request_task(server \\ __MODULE__, worker_id) do
    GenServer.call(server, {:request_task, worker_id})
  end

  @doc """
  Worker reports task completion.
  """
  @spec report_completed(GenServer.server(), binary(), binary(), non_neg_integer(), map()) ::
          :ok | {:error, term()}
  def report_completed(server \\ __MODULE__, worker_id, lease_id, fencing_token, result) do
    GenServer.call(server, {:report_completed, worker_id, lease_id, fencing_token, result})
  end

  @doc """
  Worker reports task failure.
  """
  @spec report_failed(GenServer.server(), binary(), binary(), non_neg_integer(), map(), boolean()) ::
          :ok | {:error, term()}
  def report_failed(server \\ __MODULE__, worker_id, lease_id, fencing_token, error, retryable) do
    GenServer.call(server, {:report_failed, worker_id, lease_id, fencing_token, error, retryable})
  end

  @doc """
  Worker sends heartbeat.
  """
  @spec heartbeat(GenServer.server(), binary()) :: :ok
  def heartbeat(server \\ __MODULE__, worker_id) do
    GenServer.cast(server, {:heartbeat, worker_id})
  end

  @doc """
  Registers a worker.
  """
  @spec register_worker(GenServer.server(), binary()) :: :ok
  def register_worker(server \\ __MODULE__, worker_id) do
    GenServer.call(server, {:register_worker, worker_id})
  end

  @doc """
  Lists registered workers.
  """
  @spec list_workers(GenServer.server()) :: [{binary(), worker_info()}]
  def list_workers(server \\ __MODULE__) do
    GenServer.call(server, :list_workers)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    task_queue = Keyword.get(opts, :task_queue, TaskQueue)
    lease_manager = Keyword.get(opts, :lease_manager, LeaseManager)
    worker_timeout = Keyword.get(opts, :worker_timeout_ms, 60_000)

    # Schedule worker cleanup
    schedule_worker_cleanup()

    state = %__MODULE__{
      task_queue: task_queue,
      lease_manager: lease_manager,
      worker_timeout_ms: worker_timeout
    }

    Logger.info("[Dispatcher] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:schedule_step, workflow_id, step, attempt}, _from, state) do
    {:ok, task_id} = TaskQueue.enqueue(state.task_queue, workflow_id, step, attempt)
    Logger.info("[Dispatcher] Scheduled step #{workflow_id}:#{step} attempt #{attempt}")
    {:reply, {:ok, task_id}, state}
  end

  @impl true
  def handle_call({:request_task, worker_id}, _from, state) do
    # Update worker status
    state = update_worker_heartbeat(state, worker_id)

    # Try to pull a task
    case TaskQueue.pull(state.task_queue) do
      :empty ->
        {:reply, :no_task, state}

      {:ok, task} ->
        # Acquire lease for this task
        case LeaseManager.acquire_lease(
          state.lease_manager,
          task.workflow_id,
          task.step,
          task.attempt
        ) do
          {:ok, lease} ->
            # Update worker as busy
            state = put_in(state.workers[worker_id], %{
              status: :busy,
              last_heartbeat: Event.logical_time(),
              current_task: task.task_id
            })

            Logger.info("[Dispatcher] Assigned task #{short_id(task.task_id)} to worker #{short_id(worker_id)}")
            {:reply, {:task_lease, task, lease}, state}

          {:error, reason} ->
            # Re-enqueue the task
            TaskQueue.requeue(state.task_queue, task.task_id)
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:report_completed, worker_id, lease_id, fencing_token, _result}, _from, state) do
    # Validate lease and fencing token
    case LeaseManager.validate_for_commit(state.lease_manager, lease_id, fencing_token) do
      :ok ->
        # Release the lease
        LeaseManager.release_lease(state.lease_manager, lease_id)

        # Mark worker as idle
        state = put_in(state.workers[worker_id], %{
          status: :idle,
          last_heartbeat: Event.logical_time(),
          current_task: nil
        })

        Logger.info("[Dispatcher] Task completed by worker #{short_id(worker_id)}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("[Dispatcher] Completion rejected: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:report_failed, worker_id, lease_id, fencing_token, _error, retryable}, _from, state) do
    # Validate lease and fencing token
    case LeaseManager.validate_for_commit(state.lease_manager, lease_id, fencing_token) do
      :ok ->
        # Release the lease
        LeaseManager.release_lease(state.lease_manager, lease_id)

        # Mark worker as idle
        state = put_in(state.workers[worker_id], %{
          status: :idle,
          last_heartbeat: Event.logical_time(),
          current_task: nil
        })

        # Note: Retry logic would re-enqueue if retryable
        # For now, just log
        Logger.warning("[Dispatcher] Task failed by worker #{short_id(worker_id)}, retryable=#{retryable}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("[Dispatcher] Failure report rejected: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:register_worker, worker_id}, _from, state) do
    worker_info = %{
      status: :idle,
      last_heartbeat: Event.logical_time(),
      current_task: nil
    }

    state = put_in(state.workers[worker_id], worker_info)
    Logger.info("[Dispatcher] Worker registered: #{short_id(worker_id)}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list_workers, _from, state) do
    {:reply, Map.to_list(state.workers), state}
  end

  @impl true
  def handle_cast({:heartbeat, worker_id}, state) do
    state = update_worker_heartbeat(state, worker_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_workers, state) do
    now = Event.logical_time()
    timeout_ns = state.worker_timeout_ms * 1_000_000

    {stale, active} = state.workers
      |> Enum.split_with(fn {_id, info} ->
        now - info.last_heartbeat > timeout_ns
      end)

    if length(stale) > 0 do
      Logger.warning("[Dispatcher] Removed #{length(stale)} stale workers")
      # TODO: Re-enqueue their tasks
    end

    new_state = %{state | workers: Map.new(active)}

    schedule_worker_cleanup()
    {:noreply, new_state}
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp update_worker_heartbeat(state, worker_id) do
    case Map.get(state.workers, worker_id) do
      nil ->
        put_in(state.workers[worker_id], %{
          status: :idle,
          last_heartbeat: Event.logical_time(),
          current_task: nil
        })

      info ->
        put_in(state.workers[worker_id], %{info | last_heartbeat: Event.logical_time()})
    end
  end

  defp schedule_worker_cleanup do
    Process.send_after(self(), :cleanup_workers, 10_000)
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "unknown"
end
