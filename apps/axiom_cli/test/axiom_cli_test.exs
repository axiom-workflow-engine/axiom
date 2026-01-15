defmodule AxiomCliTest do
  use ExUnit.Case

  alias Axiom.CLI.{Commands, Main}

  describe "Commands" do
    test "workflow_list returns ok" do
      assert :ok = Commands.workflow_list()
    end

    test "task_list handles missing scheduler" do
      # When scheduler isn't running
      result = Commands.task_list()
      assert result in [:ok, {:error, :not_running}]
    end

    test "node_status shows nodes" do
      assert :ok = Commands.node_status()
    end

    test "metrics shows system info" do
      assert :ok = Commands.metrics()
    end
  end

  describe "Main" do
    test "parse help flag" do
      # Just verify it doesn't crash
      Main.main(["--help"])
    end

    test "parse unknown command" do
      # Should print error but not crash
      Main.main(["unknown_command"])
    end
  end
end
