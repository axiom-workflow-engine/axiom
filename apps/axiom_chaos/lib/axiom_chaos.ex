defmodule AxiomChaos do
  @moduledoc """
  Chaos Engineering - Built-in Failure Injection.

  The sales weapon: You can demo resilience live. That sells contracts.
  """

  alias Axiom.Chaos.{Runner, ProcessKill, DelayInjection, MessageDrop}

  @doc """
  Runs a chaos scenario.

  ## Examples

      # Run process kill for 10 seconds
      AxiomChaos.run("process_kill", duration_ms: 10_000)

      # Run delay injection
      AxiomChaos.run("delay_injection", min_delay_ms: 100, max_delay_ms: 1000)
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate run(scenario, opts \\ []), to: Runner

  @doc """
  Lists available scenarios.
  """
  @spec scenarios() :: [map()]
  defdelegate scenarios(), to: Runner, as: :list_scenarios

  @doc """
  Verifies system consistency after chaos.
  """
  @spec verify() :: {:ok, map()} | {:error, map()}
  defdelegate verify(), to: Runner, as: :verify_consistency

  @doc """
  Starts process kill scenario.
  """
  @spec start_process_kill(keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_process_kill(opts \\ []), to: ProcessKill, as: :start

  @doc """
  Starts delay injection scenario.
  """
  @spec start_delay_injection(keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_delay_injection(opts \\ []), to: DelayInjection, as: :start

  @doc """
  Starts message drop scenario.
  """
  @spec start_message_drop(keyword()) :: {:ok, pid()} | {:error, term()}
  defdelegate start_message_drop(opts \\ []), to: MessageDrop, as: :start
end
