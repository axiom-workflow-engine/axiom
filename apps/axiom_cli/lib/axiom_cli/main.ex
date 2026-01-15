defmodule Axiom.CLI.Main do
  @moduledoc """
  Main CLI entry point - escript compatible.
  """

  alias Axiom.CLI.Commands

  @doc """
  Main entry point for escript.
  """
  def main(args) do
    case parse_args(args) do
      {:ok, {command, subcommand, opts}} ->
        run_command(command, subcommand, opts)

      {:error, :help} ->
        print_help()

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args([]) do
    {:error, :help}
  end

  defp parse_args(["--help" | _]) do
    {:error, :help}
  end

  defp parse_args(["-h" | _]) do
    {:error, :help}
  end

  defp parse_args([command | rest]) do
    valid_commands = ["workflow", "task", "node", "log", "chaos", "metrics", "verify"]

    if command in valid_commands do
      case rest do
        [] when command in ["metrics", "verify"] ->
          {:ok, {command, nil, []}}

        [] ->
          {:error, "Missing subcommand for #{command}"}

        [subcommand | opts] ->
          {:ok, {command, subcommand, opts}}
      end
    else
      {:error, "Unknown command: #{command}"}
    end
  end

  defp run_command("workflow", "list", opts), do: Commands.workflow_list(parse_opts(opts))
  defp run_command("workflow", "inspect", [id | _]), do: Commands.workflow_inspect(id)
  defp run_command("workflow", "replay", [id | _]), do: Commands.workflow_replay(id)
  defp run_command("task", "list", opts), do: Commands.task_list(parse_opts(opts))
  defp run_command("node", "status", _), do: Commands.node_status()
  defp run_command("log", "tail", opts), do: Commands.log_tail(parse_opts(opts))
  defp run_command("chaos", "run", [scenario | opts]), do: Commands.chaos_run(scenario, parse_opts(opts))
  defp run_command("metrics", _, _), do: Commands.metrics()
  defp run_command("verify", _, _), do: Commands.verify()
  defp run_command(cmd, sub, _) do
    IO.puts("Unknown command: #{cmd} #{sub}")
    {:error, :unknown_command}
  end

  defp parse_opts(opts) do
    opts
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn
      ["--" <> key, value], acc ->
        [{String.to_atom(key), parse_value(value)} | acc]
      _, acc ->
        acc
    end)
  end

  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp print_help do
    IO.puts("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║                         AXIOM CLI                             ║
    ║        Fault-Tolerant Distributed Workflow Engine             ║
    ╚═══════════════════════════════════════════════════════════════╝

    USAGE:
        axiom <command> [subcommand] [options]

    COMMANDS:
        workflow list              List all workflows
        workflow inspect <id>      Inspect workflow details
        workflow replay <id>       Replay workflow from event log

        task list                  List active tasks

        node status                Show cluster node status

        log tail                   Tail the event log

        chaos run <scenario>       Run chaos scenario
                                   Scenarios: process_kill, delay_injection, message_drop

        metrics                    Show system metrics
        verify                     Verify system consistency

    OPTIONS:
        -h, --help                 Show this help

    EXAMPLES:
        axiom workflow list
        axiom workflow inspect abc12345
        axiom chaos run process_kill --duration 30000
        axiom verify

    """)
  end
end
