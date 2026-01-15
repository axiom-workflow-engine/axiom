defmodule AxiomCoreTest do
  use ExUnit.Case
  doctest AxiomCore

  alias Axiom.Core.{Event, Events, Lease}

  describe "Event" do
    test "generates unique UUIDs" do
      uuid1 = Event.generate_uuid()
      uuid2 = Event.generate_uuid()

      assert is_binary(uuid1)
      assert is_binary(uuid2)
      assert uuid1 != uuid2
      assert String.length(uuid1) == 36
    end

    test "creates event with required fields" do
      event = Event.new(:step_completed, "wf-123", 1, %{result: "ok"})

      assert event.event_type == :step_completed
      assert event.workflow_id == "wf-123"
      assert event.sequence == 1
      assert event.payload == %{result: "ok"}
      assert event.schema_version == 1
      assert is_binary(event.event_id)
      assert is_binary(event.correlation_id)
      assert is_integer(event.timestamp)
    end

    test "serializes and deserializes events" do
      event = Event.new(:workflow_created, "wf-456", 0, %{name: "test"})
      binary = Event.to_binary(event)

      assert is_binary(binary)
      assert {:ok, restored} = Event.from_binary(binary)
      assert restored.event_type == event.event_type
      assert restored.workflow_id == event.workflow_id
    end

    test "generates idempotency key" do
      key1 = Event.idempotency_key("wf-1", :step_a, 1)
      key2 = Event.idempotency_key("wf-1", :step_a, 1)
      key3 = Event.idempotency_key("wf-1", :step_a, 2)

      assert key1 == key2  # Same inputs = same key
      assert key1 != key3  # Different attempt = different key
    end
  end

  describe "Events factory" do
    test "creates WorkflowCreated event" do
      event = Events.workflow_created("wf-1", "payment_flow", %{amount: 100}, [:validate, :charge])

      assert event.event_type == :workflow_created
      assert event.sequence == 0
      assert event.payload.name == "payment_flow"
      assert event.payload.steps == [:validate, :charge]
    end

    test "creates StepCompleted event" do
      event = Events.step_completed("wf-1", 5, :charge, %{success: true}, 150)

      assert event.event_type == :step_completed
      assert event.sequence == 5
      assert event.payload.step == :charge
      assert event.payload.duration_ms == 150
    end
  end

  describe "Lease" do
    test "creates lease with fencing token" do
      lease = Lease.new("wf-1", :step_a, 1, 42)

      assert lease.workflow_id == "wf-1"
      assert lease.step == :step_a
      assert lease.attempt == 1
      assert lease.fencing_token == 42
      assert is_binary(lease.lease_id)
    end

    test "lease is initially valid" do
      lease = Lease.new("wf-1", :step_a, 1, 1)

      assert Lease.valid?(lease)
      refute Lease.expired?(lease)
    end

    test "lease expires after duration" do
      # Create lease with 0ms duration (already expired)
      lease = Lease.new("wf-1", :step_a, 1, 1, duration_ms: 0)

      # Give it a moment to expire
      Process.sleep(1)

      assert Lease.expired?(lease)
      refute Lease.valid?(lease)
    end
  end
end
