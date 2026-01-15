defmodule AxiomWalTest do
  use ExUnit.Case

  alias Axiom.WAL.{Entry, Segment, LogAppendServer}
  alias Axiom.Core.{Event, Events}

  @test_data_dir "./test_data/wal_test"

  setup do
    # Clean up test directory
    File.rm_rf!(@test_data_dir)
    File.mkdir_p!(@test_data_dir)

    on_exit(fn ->
      File.rm_rf!(@test_data_dir)
    end)

    :ok
  end

  describe "Entry" do
    test "serializes and deserializes with CRC32" do
      payload = "test payload data"
      timestamp = Event.logical_time()

      {binary, size} = Entry.serialize(payload, timestamp)

      assert is_binary(binary)
      assert size == byte_size(binary)

      {:ok, {entry, rest}} = Entry.deserialize(binary, 0)

      assert entry.payload == payload
      assert entry.timestamp == timestamp
      assert rest == <<>>
    end

    test "detects corruption" do
      payload = "test payload"
      timestamp = Event.logical_time()

      {binary, _size} = Entry.serialize(payload, timestamp)

      # Corrupt the payload
      corrupted = binary <> <<0>>
      <<header::binary-size(16), _rest::binary>> = binary
      corrupted = header <> "corrupted data!"

      assert {:error, :corrupted} = Entry.deserialize(corrupted, 0)
    end

    test "handles incomplete data" do
      assert {:error, :incomplete} = Entry.deserialize(<<1, 2, 3>>, 0)
    end
  end

  describe "Segment" do
    test "opens and writes to segment" do
      {:ok, segment} = Segment.open(@test_data_dir, 0)

      assert segment.segment_id == 0
      assert segment.size == 0

      {:ok, updated} = Segment.write(segment, "test data")

      assert updated.size > 0
      assert updated.entry_count == 1

      Segment.close(updated)
    end

    test "reads all entries from segment" do
      {:ok, segment} = Segment.open(@test_data_dir, 0)

      # Write some entries
      timestamp = Event.logical_time()
      {entry1, _} = Entry.serialize("data 1", timestamp)
      {entry2, _} = Entry.serialize("data 2", timestamp + 1)

      {:ok, segment} = Segment.write(segment, entry1)
      {:ok, segment} = Segment.write(segment, entry2)
      Segment.close(segment)

      # Read back
      {:ok, entries} = Segment.read_all(@test_data_dir, 0)

      assert length(entries) == 2
      assert Enum.at(entries, 0).payload == "data 1"
      assert Enum.at(entries, 1).payload == "data 2"
    end

    test "detects need for rotation" do
      {:ok, segment} = Segment.open(@test_data_dir, 0, max_size: 100)

      refute Segment.needs_rotation?(segment)

      # Write data exceeding max size
      {:ok, segment} = Segment.write(segment, String.duplicate("x", 120))

      assert Segment.needs_rotation?(segment)

      Segment.close(segment)
    end
  end

  describe "LogAppendServer" do
    test "appends events and returns offset" do
      {:ok, pid} = LogAppendServer.start_link(
        data_dir: Path.join(@test_data_dir, "log_test"),
        name: :test_log_server
      )

      event = Events.workflow_created("wf-test", "test_flow", %{}, [:step1])

      {:ok, offset} = LogAppendServer.append_event(pid, "wf-test", event)

      assert is_integer(offset)
      assert offset > 0

      GenServer.stop(pid)
    end

    test "replays events for workflow" do
      {:ok, pid} = LogAppendServer.start_link(
        data_dir: Path.join(@test_data_dir, "replay_test"),
        name: :test_replay_server
      )

      # Append multiple events
      event1 = Events.workflow_created("wf-replay", "flow", %{}, [:a, :b])
      event2 = Events.step_scheduled("wf-replay", 1, :a, 1)
      event3 = Events.step_completed("wf-replay", 2, :a, %{}, 100)

      {:ok, _} = LogAppendServer.append_event(pid, "wf-replay", event1)
      {:ok, _} = LogAppendServer.append_event(pid, "wf-replay", event2)
      {:ok, _} = LogAppendServer.append_event(pid, "wf-replay", event3)

      # Replay
      {:ok, events} = LogAppendServer.replay(pid, "wf-replay")

      assert length(events) == 3
      assert Enum.at(events, 0).event_type == :workflow_created
      assert Enum.at(events, 1).event_type == :step_scheduled
      assert Enum.at(events, 2).event_type == :step_completed

      GenServer.stop(pid)
    end
  end
end
