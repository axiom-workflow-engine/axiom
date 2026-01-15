defmodule Axiom.Chaos.Scenario do
  @moduledoc """
  Behaviour for chaos scenarios.

  Each scenario defines:
  - What it injects
  - How long it runs
  - How to verify recovery
  """

  @doc """
  Starts the chaos scenario.
  """
  @callback start(opts :: keyword()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Stops the chaos scenario.
  """
  @callback stop(pid :: pid()) :: :ok

  @doc """
  Returns scenario metadata.
  """
  @callback info() :: %{
              name: String.t(),
              description: String.t(),
              default_duration_ms: non_neg_integer()
            }
end
