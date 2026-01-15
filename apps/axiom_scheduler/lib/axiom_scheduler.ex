defmodule AxiomScheduler do
  @moduledoc """
  Task Scheduling with Exactly-Once Execution.

  The Scheduler assigns leases, not tasks.
  Leases are time-bounded, not trust-based.
  """

  alias Axiom.Scheduler.{Dispatcher, LeaseManager, TaskQueue}

  @doc """
  Schedules a workflow step for execution.
  """
  @spec schedule(binary(), atom(), pos_integer()) :: {:ok, binary()}
  def schedule(workflow_id, step, attempt \\ 1) do
    Dispatcher.schedule_step(workflow_id, step, attempt)
  end

  @doc """
  Gets queue depth.
  """
  @spec queue_depth() :: non_neg_integer()
  def queue_depth do
    TaskQueue.depth()
  end

  @doc """
  Lists active leases.
  """
  @spec active_leases() :: [Axiom.Core.Lease.t()]
  def active_leases do
    LeaseManager.list_active_leases()
  end

  @doc """
  Lists registered workers.
  """
  @spec workers() :: list()
  def workers do
    Dispatcher.list_workers()
  end
end
