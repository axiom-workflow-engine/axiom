defmodule AxiomWal do
  @moduledoc """
  Write-Ahead Log (WAL) - The Spine of Axiom.

  If this fails → company-ending bug.
  """

  alias Axiom.WAL.LogAppendServer
  alias Axiom.Core.Event

  @doc """
  Appends an event to the WAL.
  """
  @spec append(binary(), Event.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def append(workflow_id, event) do
    LogAppendServer.append_event(workflow_id, event)
  end

  @doc """
  Replays all events for a workflow.
  """
  @spec replay(binary()) :: {:ok, [Event.t()]} | {:error, term()}
  def replay(workflow_id) do
    LogAppendServer.replay(workflow_id)
  end

  @doc """
  Subscribes to new events.
  """
  @spec subscribe() :: :ok
  def subscribe do
    LogAppendServer.subscribe()
  end
end
