defmodule AxiomGateway.RateLimiter do
  @moduledoc """
  A stateful rate limiter worker that integrates with Hammer.
  This allows for global rate limit monitoring and dynamic adjustments.
  """
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Logger.info("[Gateway] RateLimiter initialized")
    {:ok, %{}}
  end

  @doc """
  Check if a request is allowed for a given ID.
  """
  def check_rate(id, scale_ms, limit) do
    Hammer.check_rate(id, scale_ms, limit)
  end

  @doc """
  Inspect current rate limit status for an ID.
  """
  def inspect_rate(id, scale_ms) do
    Hammer.inspect_rate(id, scale_ms)
  end
end
