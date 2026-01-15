defmodule AxiomCore do
  @moduledoc """
  Shared types, protocols, and utilities for Axiom.

  This module re-exports core types for convenience.
  """

  defdelegate generate_uuid(), to: Axiom.Core.Event
  defdelegate logical_time(), to: Axiom.Core.Event
  defdelegate idempotency_key(workflow_id, step, attempt), to: Axiom.Core.Event
end
