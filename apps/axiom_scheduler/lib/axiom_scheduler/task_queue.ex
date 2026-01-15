defmodule Axiom.Scheduler.TaskQueue do
  @moduledoc """
  Priority-based task queue with pull semantics.

  Workers pull tasks, they are not pushed.
  This enables backpressure and prevents orphaned tasks.
  """

  use GenServer
  require Logger

  defstruct [
    queue: :queue.new(),
    pending: %{},           # %{task_id => task}
    task_count: 0
  ]

  @type task :: %{
          task_id: binary(),
          workflow_id: binary(),
          step: atom(),
          attempt: pos_integer(),
          priority: non_neg_integer(),
          enqueued_at: non_neg_integer()
        }

  @type t :: %__MODULE__{
          queue: :queue.queue(),
          pending: %{binary() => task()},
          task_count: non_neg_integer()
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Enqueues a task for execution.
  """
  @spec enqueue(GenServer.server(), binary(), atom(), pos_integer(), keyword()) :: {:ok, binary()}
  def enqueue(server \\ __MODULE__, workflow_id, step, attempt, opts \\ []) do
    GenServer.call(server, {:enqueue, workflow_id, step, attempt, opts})
  end

  @doc """
  Pulls the next task from the queue.
  Returns nil if queue is empty.
  """
  @spec pull(GenServer.server()) :: {:ok, task()} | :empty
  def pull(server \\ __MODULE__) do
    GenServer.call(server, :pull)
  end

  @doc """
  Marks a task as completed and removes from pending.
  """
  @spec complete(GenServer.server(), binary()) :: :ok
  def complete(server \\ __MODULE__, task_id) do
    GenServer.cast(server, {:complete, task_id})
  end

  @doc """
  Re-enqueues a task (for retries).
  """
  @spec requeue(GenServer.server(), binary()) :: :ok | {:error, :not_found}
  def requeue(server \\ __MODULE__, task_id) do
    GenServer.call(server, {:requeue, task_id})
  end

  @doc """
  Returns queue depth.
  """
  @spec depth(GenServer.server()) :: non_neg_integer()
  def depth(server \\ __MODULE__) do
    GenServer.call(server, :depth)
  end

  @doc """
  Lists pending tasks (pulled but not completed).
  """
  @spec list_pending(GenServer.server()) :: [task()]
  def list_pending(server \\ __MODULE__) do
    GenServer.call(server, :list_pending)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("[TaskQueue] Started")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:enqueue, workflow_id, step, attempt, opts}, _from, state) do
    task_id = Axiom.Core.Event.generate_uuid()
    priority = Keyword.get(opts, :priority, 0)

    task = %{
      task_id: task_id,
      workflow_id: workflow_id,
      step: step,
      attempt: attempt,
      priority: priority,
      enqueued_at: Axiom.Core.Event.logical_time()
    }

    new_queue = :queue.in(task, state.queue)
    new_state = %{state |
      queue: new_queue,
      task_count: state.task_count + 1
    }

    Logger.debug("[TaskQueue] Enqueued task #{short_id(task_id)} for #{workflow_id}:#{step}")
    {:reply, {:ok, task_id}, new_state}
  end

  @impl true
  def handle_call(:pull, _from, state) do
    case :queue.out(state.queue) do
      {{:value, task}, new_queue} ->
        new_state = %{state |
          queue: new_queue,
          pending: Map.put(state.pending, task.task_id, task)
        }

        Logger.debug("[TaskQueue] Pulled task #{short_id(task.task_id)}")
        {:reply, {:ok, task}, new_state}

      {:empty, _} ->
        {:reply, :empty, state}
    end
  end

  @impl true
  def handle_call({:requeue, task_id}, _from, state) do
    case Map.pop(state.pending, task_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {task, new_pending} ->
        # Increment attempt and re-enqueue
        updated_task = %{task | attempt: task.attempt + 1}
        new_queue = :queue.in(updated_task, state.queue)

        new_state = %{state |
          queue: new_queue,
          pending: new_pending
        }

        Logger.debug("[TaskQueue] Requeued task #{short_id(task_id)}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:depth, _from, state) do
    {:reply, :queue.len(state.queue), state}
  end

  @impl true
  def handle_call(:list_pending, _from, state) do
    {:reply, Map.values(state.pending), state}
  end

  @impl true
  def handle_cast({:complete, task_id}, state) do
    new_state = %{state | pending: Map.delete(state.pending, task_id)}
    Logger.debug("[TaskQueue] Completed task #{short_id(task_id)}")
    {:noreply, new_state}
  end

  defp short_id(id), do: String.slice(id, 0, 8)
end
