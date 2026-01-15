defmodule AxiomCli do
  @moduledoc """
  Terminal Control Plane for Axiom.

  If you need a browser to debug → system is immature.
  """

  alias Axiom.CLI.{Commands, Main}

  # Delegate to Commands module
  defdelegate workflow_list(opts \\ []), to: Commands
  defdelegate workflow_inspect(id), to: Commands
  defdelegate workflow_replay(id), to: Commands
  defdelegate task_list(opts \\ []), to: Commands
  defdelegate node_status(), to: Commands
  defdelegate log_tail(opts \\ []), to: Commands
  defdelegate metrics(), to: Commands
  defdelegate chaos_run(scenario, opts \\ []), to: Commands
  defdelegate verify(), to: Commands

  @doc """
  Main entry point for escript.
  """
  defdelegate main(args), to: Main
end
