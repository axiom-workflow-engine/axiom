defmodule AxiomChaosTest do
  use ExUnit.Case

  alias Axiom.Chaos.{ProcessKill, DelayInjection, MessageDrop, Runner}

  describe "ProcessKill" do
    test "returns correct info" do
      info = ProcessKill.info()

      assert info.name == "process_kill"
      assert is_binary(info.description)
      assert is_integer(info.default_duration_ms)
    end

    test "starts and stops" do
      {:ok, pid} = ProcessKill.start(duration_ms: 50)

      assert Process.alive?(pid)

      # Wait for auto-stop
      Process.sleep(150)
      refute Process.alive?(pid)
    end

    test "tracks kill count" do
      {:ok, pid} = ProcessKill.start(
        duration_ms: 0,
        interval_ms: 10,
        kill_probability: 0
      )

      Process.sleep(50)
      stats = ProcessKill.stats(pid)

      assert stats.kill_count == 0
    end
  end

  describe "DelayInjection" do
    test "returns correct info" do
      info = DelayInjection.info()

      assert info.name == "delay_injection"
    end

    test "starts and stops" do
      {:ok, pid} = DelayInjection.start(duration_ms: 100)

      assert Process.alive?(pid)

      Process.sleep(200)
      refute Process.alive?(pid)
    end

    test "injects delays when called" do
      {:ok, pid} = DelayInjection.start(
        duration_ms: 5000,
        min_delay_ms: 10,
        max_delay_ms: 20
      )

      start = System.monotonic_time(:millisecond)
      DelayInjection.maybe_delay()
      elapsed = System.monotonic_time(:millisecond) - start

      assert elapsed >= 10

      stats = DelayInjection.stats(pid)
      assert stats.injection_count == 1

      DelayInjection.stop(pid)
    end
  end

  describe "MessageDrop" do
    test "returns correct info" do
      info = MessageDrop.info()

      assert info.name == "message_drop"
    end

    test "drops messages based on probability" do
      {:ok, pid} = MessageDrop.start(
        duration_ms: 5000,
        drop_probability: 1.0  # Always drop
      )

      result = MessageDrop.maybe_send(self(), :test_message)

      assert result == false  # Message was dropped

      stats = MessageDrop.stats(pid)
      assert stats.drop_count == 1

      MessageDrop.stop(pid)
    end

    test "sends messages when probability is 0" do
      {:ok, pid} = MessageDrop.start(
        duration_ms: 5000,
        drop_probability: 0.0  # Never drop
      )

      result = MessageDrop.maybe_send(self(), :test_message)

      assert result == true
      assert_receive :test_message

      MessageDrop.stop(pid)
    end
  end

  describe "Runner" do
    test "lists scenarios" do
      scenarios = Runner.list_scenarios()

      assert length(scenarios) == 3

      names = Enum.map(scenarios, & &1.id)
      assert "process_kill" in names
      assert "delay_injection" in names
      assert "message_drop" in names
    end

    test "runs scenario" do
      {:ok, result} = Runner.run("delay_injection", duration_ms: 100)

      assert result.scenario == "delay_injection"
      assert result.duration_ms == 100
    end

    test "returns error for unknown scenario" do
      {:error, {:unknown_scenario, "fake", _available}} = Runner.run("fake")
    end

    test "verifies consistency" do
      {:ok, result} = Runner.verify_consistency()

      assert result.failed == 0
    end
  end
end
