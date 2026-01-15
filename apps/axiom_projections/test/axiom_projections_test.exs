defmodule AxiomProjectionsTest do
  use ExUnit.Case

  alias Axiom.API.{Health, Metrics, Workflows, Tasks}

  describe "Health" do
    test "check_all returns status" do
      result = Health.check_all()

      assert is_boolean(result.healthy)
      assert is_map(result.checks)
      assert is_integer(result.timestamp)
    end
  end

  describe "Metrics" do
    test "collect returns metrics" do
      metrics = Metrics.collect()

      assert is_map(metrics.system)
      assert is_integer(metrics.system.memory.total)
      assert is_integer(metrics.system.processes.count)
    end

    test "prometheus_format returns string" do
      output = Metrics.prometheus_format()

      assert is_binary(output)
      assert String.contains?(output, "axiom_memory_bytes")
      assert String.contains?(output, "axiom_process_count")
    end
  end

  describe "Workflows API" do
    test "list returns ok" do
      {:ok, workflows} = Workflows.list()
      assert is_list(workflows)
    end
  end

  describe "Tasks API" do
    test "list handles scheduler not running" do
      result = Tasks.list()
      # Either succeeds or scheduler not running
      assert match?({:ok, _}, result) or match?({:error, :scheduler_not_running}, result)
    end
  end
end
