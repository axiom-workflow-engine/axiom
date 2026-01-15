defmodule Axiom.WAL.LogAppendServer do
  @moduledoc """
  THE JUDGE - Only authority that makes events real.

  This is the most critical component. If this fails → company-ending bug.

  Responsibilities:
  - Append events with fsync guarantee
  - Enforce ordering & durability
  - No business logic

  Guarantees:
  - Event is fsync'd
  - Offset is final
  - Event will survive crashes
  - If crash before reply → event does not exist
  """

  use GenServer
  require Logger

  alias Axiom.WAL.{Entry, Segment}
  alias Axiom.Core.Event

  # STATE CONTRACT
  defstruct [
    :data_dir,
    :current_segment,
    :segment_id,
    current_offset: 0,
    subscribers: []
  ]

  @type t :: %__MODULE__{
          data_dir: String.t(),
          current_segment: Segment.t() | nil,
          segment_id: non_neg_integer(),
          current_offset: non_neg_integer(),
          subscribers: [pid()]
        }

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Starts the LogAppendServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Appends an event to the WAL. SYNC operation.

  Returns {:ok, offset} or {:error, :disk_failure}

  This is the commit operation. If this returns {:ok, offset}:
  - Event is fsync'd to disk
  - Offset is final and will never change
  - Event WILL survive crashes

  If this crashes before returning → event does not exist.
  """
  @spec append_event(GenServer.server(), binary(), Event.t()) ::
    {:ok, non_neg_integer()} | {:error, :disk_failure | term()}
  def append_event(server \\ __MODULE__, workflow_id, event) do
    GenServer.call(server, {:append_event, workflow_id, event}, :infinity)
  end

  @doc """
  Subscribes to new events (for projections).
  """
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  @doc """
  Replays all events for a workflow.
  """
  @spec replay(GenServer.server(), binary()) :: {:ok, [Event.t()]} | {:error, term()}
  def replay(server \\ __MODULE__, workflow_id) do
    GenServer.call(server, {:replay, workflow_id})
  end

  @doc """
  Returns current offset.
  """
  @spec current_offset(GenServer.server()) :: non_neg_integer()
  def current_offset(server \\ __MODULE__) do
    GenServer.call(server, :current_offset)
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(opts) do
    data_dir = Keyword.get(opts, :data_dir, "./data/wal")

    # Find the latest segment or start from 0
    segment_id = find_latest_segment(data_dir)

    case Segment.open(data_dir, segment_id) do
      {:ok, segment} ->
        state = %__MODULE__{
          data_dir: data_dir,
          current_segment: segment,
          segment_id: segment_id,
          current_offset: calculate_offset(data_dir, segment_id)
        }

        Logger.info("[WAL] LogAppendServer started. Data dir: #{data_dir}, Segment: #{segment_id}, Offset: #{state.current_offset}")
        {:ok, state}

      {:error, reason} ->
        {:stop, {:failed_to_open_segment, reason}}
    end
  end

  @impl true
  def handle_call({:append_event, workflow_id, event}, _from, state) do
    # Serialize event
    event_binary = Event.to_binary(event)
    timestamp = Event.logical_time()

    # Create WAL entry
    {entry_binary, entry_size} = Entry.serialize(event_binary, timestamp)

    # Check if we need to rotate segment
    state = maybe_rotate_segment(state, entry_size)

    # Write to segment with fsync
    case Segment.write(state.current_segment, entry_binary) do
      {:ok, updated_segment} ->
        new_offset = state.current_offset + entry_size

        new_state = %{state |
          current_segment: updated_segment,
          current_offset: new_offset
        }

        # Notify subscribers
        notify_subscribers(new_state.subscribers, {:event, new_offset, event})

        Logger.debug("[WAL] Event appended. Type: #{event.event_type}, Workflow: #{workflow_id}, Offset: #{new_offset}")
        {:reply, {:ok, new_offset}, new_state}

      {:error, reason} ->
        Logger.error("[WAL] Failed to write event: #{inspect(reason)}")
        {:reply, {:error, :disk_failure}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  @impl true
  def handle_call({:replay, workflow_id}, _from, state) do
    events = replay_workflow(state.data_dir, state.segment_id, workflow_id)
    {:reply, {:ok, events}, state}
  end

  @impl true
  def handle_call(:current_offset, _from, state) do
    {:reply, state.current_offset, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp find_latest_segment(data_dir) do
    case File.ls(data_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".wal"))
        |> Enum.map(fn f ->
          case Regex.run(~r/segment_(\d+)\.wal/, f) do
            [_, id] -> String.to_integer(id)
            _ -> 0
          end
        end)
        |> Enum.max(fn -> 0 end)

      {:error, :enoent} ->
        0
    end
  end

  defp calculate_offset(data_dir, segment_id) do
    # Sum up sizes of all segments up to current
    0..segment_id
    |> Enum.reduce(0, fn seg_id, acc ->
      path = Path.join(data_dir, "segment_#{String.pad_leading(Integer.to_string(seg_id), 8, "0")}.wal")
      case File.stat(path) do
        {:ok, %{size: size}} -> acc + size
        _ -> acc
      end
    end)
  end

  defp maybe_rotate_segment(state, entry_size) do
    if Segment.needs_rotation?(state.current_segment) or
       state.current_segment.size + entry_size > state.current_segment.max_size do
      rotate_segment(state)
    else
      state
    end
  end

  defp rotate_segment(state) do
    # Close current segment
    Segment.close(state.current_segment)

    # Open new segment
    new_segment_id = state.segment_id + 1
    {:ok, new_segment} = Segment.open(state.data_dir, new_segment_id)

    Logger.info("[WAL] Rotated to segment #{new_segment_id}")

    %{state |
      current_segment: new_segment,
      segment_id: new_segment_id
    }
  end

  defp notify_subscribers(subscribers, message) do
    Enum.each(subscribers, fn pid ->
      send(pid, message)
    end)
  end

  defp replay_workflow(data_dir, max_segment_id, workflow_id) do
    0..max_segment_id
    |> Enum.flat_map(fn seg_id ->
      case Segment.read_all(data_dir, seg_id) do
        {:ok, entries} ->
          entries
          |> Enum.map(fn entry ->
            case Event.from_binary(entry.payload) do
              {:ok, event} -> event
              _ -> nil
            end
          end)
          |> Enum.filter(fn
            nil -> false
            event -> event.workflow_id == workflow_id
          end)

        {:error, _} ->
          []
      end
    end)
    |> Enum.sort_by(& &1.sequence)
  end
end
