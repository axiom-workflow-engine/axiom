defmodule AxiomEngineTest do
  use ExUnit.Case

  alias Axiom.Engine.{StateMachine, WorkflowProcess, WorkflowSupervisor}
  alias Axiom.Core.Events
  alias Axiom.WAL.LogAppendServer

  @test_data_dir "./test_data/engine_test"

  setup do
    # Clean up test directory
    File.rm_rf!(@test_data_dir)
    File.mkdir_p!(@test_data_dir)

    # Start a test WAL server
    {:ok, wal_pid} = LogAppendServer.start_link(
      data_dir: @test_data_dir,
      name: :test_engine_wal
    )

    on_exit(fn ->
      if Process.alive?(wal_pid), do: GenServer.stop(wal_pid)
      File.rm_rf!(@test_data_dir)
    end)

    {:ok, wal_pid: wal_pid}
  end

  describe "StateMachine" do
    test "applies WorkflowCreated event" do
      sm = StateMachine.new("wf-1")
      event = Events.workflow_created("wf-1", "test_flow", %{x: 1}, [:step1, :step2])

      sm = StateMachine.apply_event(sm, event)

      assert sm.name == "test_flow"
      assert sm.steps == [:step1, :step2]
      assert sm.state == :pending
      assert sm.version == 1
      assert Map.get(sm.step_states, :step1) == :pending
      assert Map.get(sm.step_states, :step2) == :pending
    end

    test "applies step lifecycle events" do
      sm = StateMachine.new("wf-1")

      sm = sm
        |> StateMachine.apply_event(Events.workflow_created("wf-1", "flow", %{}, [:a, :b]))
        |> StateMachine.apply_event(Events.step_scheduled("wf-1", 1, :a, 1))
        |> StateMachine.apply_event(Events.step_started("wf-1", 2, :a, "lease-1", "worker-1"))
        |> StateMachine.apply_event(Events.step_completed("wf-1", 3, :a, %{ok: true}, 100))

      assert sm.version == 4
      assert Map.get(sm.step_states, :a) == :completed
      assert Map.get(sm.step_states, :b) == :pending
      assert sm.current_step_index == 1
    end

    test "hydrates from event list" do
      events = [
        Events.workflow_created("wf-1", "hydrate_test", %{}, [:x, :y]),
        Events.step_scheduled("wf-1", 1, :x, 1),
        Events.step_completed("wf-1", 2, :x, %{}, 50)
      ]

      sm = StateMachine.hydrate("wf-1", events)

      assert sm.version == 3
      assert sm.name == "hydrate_test"
      assert Map.get(sm.step_states, :x) == :completed
    end

    test "next_runnable_step returns first pending step" do
      sm = StateMachine.new("wf-1")
        |> StateMachine.apply_event(Events.workflow_created("wf-1", "flow", %{}, [:a, :b, :c]))
        |> StateMachine.apply_event(Events.step_scheduled("wf-1", 1, :a, 1))
        |> StateMachine.apply_event(Events.step_completed("wf-1", 2, :a, %{}, 100))

      assert StateMachine.next_runnable_step(sm) == :b
    end

    test "terminal states have no runnable steps" do
      sm = StateMachine.new("wf-1")
        |> StateMachine.apply_event(Events.workflow_created("wf-1", "flow", %{}, [:a]))
        |> StateMachine.apply_event(Events.step_completed("wf-1", 1, :a, %{}, 100))
        |> StateMachine.apply_event(Events.workflow_completed("wf-1", 2, %{}))

      assert StateMachine.terminal?(sm)
      assert StateMachine.next_runnable_step(sm) == nil
    end
  end

  describe "WorkflowProcess" do
    test "creates workflow and persists to WAL", %{wal_pid: wal_pid} do
      workflow_id = Axiom.Core.Event.generate_uuid()

      {:ok, pid} = WorkflowProcess.start_link(
        workflow_id: workflow_id,
        wal_server: wal_pid,
        auto_hydrate: false
      )

      {:ok, ^workflow_id} = WorkflowProcess.create(pid, "test_wf", %{input: 1}, [:step1, :step2])

      state = WorkflowProcess.get_state(pid)
      assert state.name == "test_wf"
      assert state.steps == [:step1, :step2]
      assert state.version == 1

      # Verify persisted to WAL
      {:ok, events} = LogAppendServer.replay(wal_pid, workflow_id)
      assert length(events) == 1
      assert hd(events).event_type == :workflow_created

      GenServer.stop(pid)
    end

    test "advances workflow through steps", %{wal_pid: wal_pid} do
      workflow_id = Axiom.Core.Event.generate_uuid()

      {:ok, pid} = WorkflowProcess.start_link(
        workflow_id: workflow_id,
        wal_server: wal_pid,
        auto_hydrate: false
      )

      {:ok, _} = WorkflowProcess.create(pid, "advance_test", %{}, [:a, :b])

      # Advance schedules first step
      :ok = WorkflowProcess.advance(pid)

      state = WorkflowProcess.get_state(pid)
      assert Map.get(state.step_states, :a) == :scheduled

      # Complete step
      :ok = WorkflowProcess.step_completed(pid, :a, %{result: "ok"}, 100)

      state = WorkflowProcess.get_state(pid)
      assert Map.get(state.step_states, :a) == :completed

      GenServer.stop(pid)
    end

    test "hydrates from WAL on restart", %{wal_pid: wal_pid} do
      workflow_id = Axiom.Core.Event.generate_uuid()

      # Create and advance
      {:ok, pid1} = WorkflowProcess.start_link(
        workflow_id: workflow_id,
        wal_server: wal_pid,
        auto_hydrate: false
      )

      {:ok, _} = WorkflowProcess.create(pid1, "hydrate_test", %{}, [:step1])
      :ok = WorkflowProcess.advance(pid1)
      :ok = WorkflowProcess.step_completed(pid1, :step1, %{}, 50)

      GenServer.stop(pid1)

      # Restart and verify hydration
      {:ok, pid2} = WorkflowProcess.start_link(
        workflow_id: workflow_id,
        wal_server: wal_pid,
        auto_hydrate: true
      )

      # Wait for hydration
      Process.sleep(100)

      state = WorkflowProcess.get_state(pid2)
      assert state.name == "hydrate_test"
      assert state.version == 3  # created + scheduled + completed
      assert Map.get(state.step_states, :step1) == :completed

      GenServer.stop(pid2)
    end

    test "rejects duplicate idempotency keys", %{wal_pid: wal_pid} do
      workflow_id = Axiom.Core.Event.generate_uuid()

      {:ok, pid} = WorkflowProcess.start_link(
        workflow_id: workflow_id,
        wal_server: wal_pid,
        auto_hydrate: false
      )

      {:ok, _} = WorkflowProcess.create(pid, "idemp_test", %{}, [:a])
      :ok = WorkflowProcess.advance(pid)

      key = "unique-key-123"

      # First completion succeeds
      :ok = WorkflowProcess.step_completed(pid, :a, %{}, 100, idempotency_key: key)

      # Duplicate is rejected
      {:error, :duplicate} = WorkflowProcess.step_completed(pid, :a, %{}, 100, idempotency_key: key)

      GenServer.stop(pid)
    end
  end
end
