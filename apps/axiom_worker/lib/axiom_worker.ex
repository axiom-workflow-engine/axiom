defmodule AxiomWorker do
  @moduledoc """
  Worker Runtime - Execute side effects, report outcomes.

  Workers are liars until proven correct.
  """

  alias Axiom.Worker.Executor

  @doc """
  Starts a new worker.
  """
  @spec start_worker(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_worker(opts \\ []) do
    Executor.start_link(opts)
  end

  @doc """
  Stops a worker.
  """
  @spec stop_worker(pid()) :: :ok
  def stop_worker(pid) do
    Executor.stop(pid)
  end
end
