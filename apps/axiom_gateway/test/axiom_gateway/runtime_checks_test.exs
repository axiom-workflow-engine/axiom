defmodule AxiomGateway.RuntimeChecksTest do
  use ExUnit.Case, async: false

  alias AxiomGateway.RuntimeChecks

  test "readiness returns expected shape" do
    result = RuntimeChecks.readiness()

    assert is_map(result)
    assert result.status in ["ready", "not_ready"]
    assert is_map(result.checks)
    assert Map.has_key?(result.checks, :wal)
    assert Map.has_key?(result.checks, :scheduler_dispatcher)
    assert Map.has_key?(result.checks, :scheduler_lease_manager)
    assert Map.has_key?(result.checks, :workflow_registry)
    assert Map.has_key?(result.checks, :memory)
    assert is_binary(result.timestamp)
  end

  test "readiness reports memory pressure when threshold is exceeded" do
    Application.put_env(:axiom_gateway, :memory_limit_bytes, 1)
    Application.put_env(:axiom_gateway, :readiness_max_memory_ratio, 0.5)

    result = RuntimeChecks.readiness()
    assert result.checks.memory == "memory_pressure"
  after
    Application.delete_env(:axiom_gateway, :memory_limit_bytes)
    Application.delete_env(:axiom_gateway, :readiness_max_memory_ratio)
  end
end
