defmodule Axiom.CLI.Commands do
  @moduledoc """
  CLI command implementations.

  Terminal-first: If you need a browser to debug → system is immature.
  """

  alias Axiom.Core.Event

  @doc """
  Lists all workflows.
  """
  def workflow_list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # In production, this would query the projections
    case get_workflows(limit) do
      {:ok, workflows} ->
        if workflows == [] do
          IO.puts("No workflows found.")
        else
          print_table(
            ["ID", "Name", "State", "Steps", "Created"],
            Enum.map(workflows, fn wf ->
              [
                short_id(wf.id),
                wf.name,
                state_badge(wf.state),
                "#{wf.completed_steps}/#{wf.total_steps}",
                format_time(wf.created_at)
              ]
            end)
          )
        end
        :ok

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Inspects a specific workflow.
  """
  def workflow_inspect(workflow_id) do
    case get_workflow(workflow_id) do
      {:ok, wf} ->
        IO.puts("""

        ┌─────────────────────────────────────────────────────────────┐
        │ Workflow: #{String.pad_trailing(wf.name, 47)} │
        └─────────────────────────────────────────────────────────────┘

        ID:          #{wf.id}
        State:       #{state_badge(wf.state)}
        Created:     #{format_time(wf.created_at)}

        Steps:
        #{format_steps(wf.steps, wf.step_states)}

        Event History: #{length(wf.events)} events
        """)
        :ok

      {:error, :not_found} ->
        IO.puts("Workflow not found: #{workflow_id}")
        {:error, :not_found}
    end
  end

  @doc """
  Replays a workflow from event log.
  """
  def workflow_replay(workflow_id) do
    IO.puts("Replaying workflow #{short_id(workflow_id)}...")

    case Axiom.WAL.LogAppendServer.replay(workflow_id) do
      {:ok, events} ->
        IO.puts("Found #{length(events)} events")

        Enum.each(events, fn event ->
          IO.puts("  [#{event.sequence}] #{event.event_type} @ #{format_time(event.timestamp)}")
        end)

        {:ok, events}

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists active tasks.
  """
  def task_list(_opts \\ []) do
    case GenServer.whereis(Axiom.Scheduler.TaskQueue) do
      nil ->
        IO.puts("Scheduler not running")
        {:error, :not_running}

      _pid ->
        depth = Axiom.Scheduler.TaskQueue.depth()
        pending = Axiom.Scheduler.TaskQueue.list_pending()

        IO.puts("Queue Depth: #{depth}")
        IO.puts("Pending (in-flight): #{length(pending)}")

        if pending != [] do
          IO.puts("\nPending Tasks:")
          print_table(
            ["Task ID", "Workflow", "Step", "Attempt"],
            Enum.map(pending, fn t ->
              [short_id(t.task_id), short_id(t.workflow_id), to_string(t.step), to_string(t.attempt)]
            end)
          )
        end

        :ok
    end
  end

  @doc """
  Shows cluster node status.
  """
  def node_status do
    nodes = [Node.self() | Node.list()]

    IO.puts("""

    Cluster Status
    ══════════════
    """)

    Enum.each(nodes, fn node ->
      status = if node == Node.self(), do: "● SELF", else: "○ CONNECTED"
      IO.puts("  #{status}  #{node}")
    end)

    IO.puts("\nTotal Nodes: #{length(nodes)}")
    :ok
  end

  @doc """
  Tails the event log.
  """
  def log_tail(opts \\ []) do
    count = Keyword.get(opts, :count, 10)

    IO.puts("Last #{count} events:")
    IO.puts("─────────────────────")

    # Subscribe and show recent
    case GenServer.whereis(Axiom.WAL.LogAppendServer) do
      nil ->
        IO.puts("WAL not running")
        {:error, :not_running}

      pid ->
        offset = Axiom.WAL.LogAppendServer.current_offset(pid)
        IO.puts("Current offset: #{offset}")

        # Show recent events by replaying from the WAL
        case Axiom.WAL.LogAppendServer.replay_all(pid) do
          {:ok, events} when events != [] ->
            events
            |> Enum.take(-count)
            |> Enum.each(fn event ->
              IO.puts("  [#{event.sequence}] #{event.event_type} wf=#{short_id(event.workflow_id)} @ #{format_time(event.timestamp)}")
            end)

          _ ->
            IO.puts("No events found.")
        end

        :ok
    end
  end

  @doc """
  Shows system metrics.
  """
  def metrics do
    IO.puts("""

    System Metrics
    ══════════════
    """)

    # Memory
    memory = :erlang.memory()
    IO.puts("Memory:")
    IO.puts("  Total:     #{format_bytes(memory[:total])}")
    IO.puts("  Processes: #{format_bytes(memory[:processes])}")
    IO.puts("  ETS:       #{format_bytes(memory[:ets])}")

    # Processes
    IO.puts("\nProcesses:")
    IO.puts("  Count:     #{:erlang.system_info(:process_count)}")
    IO.puts("  Limit:     #{:erlang.system_info(:process_limit)}")

    # Schedulers
    IO.puts("\nSchedulers:")
    IO.puts("  Online:    #{:erlang.system_info(:schedulers_online)}")

    :ok
  end

  @doc """
  Runs chaos scenario.
  """
  def chaos_run(scenario, opts \\ []) do
    duration = Keyword.get(opts, :duration_ms, 10_000)

    IO.puts("Starting chaos scenario: #{scenario}")
    IO.puts("Duration: #{duration}ms")
    IO.puts("─────────────────────────")

    case AxiomChaos.run(scenario, duration_ms: duration) do
      {:ok, result} ->
        IO.puts("\n✓ Scenario completed")
        IO.puts("  Duration: #{result.duration_ms}ms")
        :ok

      {:error, {:unknown_scenario, name, available}} ->
        IO.puts("Unknown scenario: #{name}")
        IO.puts("Available: #{Enum.join(available, ", ")}")
        {:error, :unknown_scenario}
    end
  end

  @doc """
  Verifies system consistency.
  """
  def verify do
    IO.puts("Verifying system consistency...")

    case AxiomChaos.verify() do
      {:ok, result} ->
        IO.puts("✓ All checks passed (#{result.checks_passed})")
        :ok

      {:error, result} ->
        IO.puts("✗ Checks failed: #{result.failed}/#{result.checks_passed + result.failed}")
        {:error, result.failures}
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp get_workflows(limit) do
    try do
      workflows = AxiomGateway.Projections.WorkflowIndex.list_workflows(limit)
      formatted = Enum.map(workflows, fn wf ->
        %{
          id: wf.id,
          name: wf.name,
          state: String.to_atom(wf.status),
          completed_steps: 0,
          total_steps: 0,
          created_at: wf.created_at
        }
      end)
      {:ok, formatted}
    rescue
      _ -> {:ok, []}
    end
  end

  defp get_workflow(id) do
    try do
      case AxiomGateway.Projections.WorkflowIndex.get_workflow(id) do
        {:ok, wf} ->
          {:ok, %{
            id: wf.id,
            name: wf.name,
            state: String.to_atom(wf.status),
            steps: [],
            step_states: %{},
            events: [],
            created_at: wf.created_at
          }}
        {:error, :not_found} ->
          {:error, :not_found}
      end
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "unknown"

  defp state_badge(:pending), do: "⏳ pending"
  defp state_badge(:running), do: "▶ running"
  defp state_badge(:completed), do: "✓ completed"
  defp state_badge(:failed), do: "✗ failed"
  defp state_badge(state), do: to_string(state)

  defp format_time(timestamp) when is_integer(timestamp) do
    timestamp
    |> div(1_000_000_000)
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end
  defp format_time(_), do: "unknown"

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end
  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end
  defp format_bytes(bytes), do: "#{div(bytes, 1024)} KB"

  defp format_steps(steps, step_states) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      state = Map.get(step_states, step, :pending)
      icon = case state do
        :completed -> "✓"
        :running -> "▶"
        :failed -> "✗"
        _ -> "○"
      end
      "  #{idx}. #{icon} #{step}"
    end)
    |> Enum.join("\n")
  end

  defp print_table(headers, rows) do
    widths = Enum.map(0..(length(headers) - 1), fn i ->
      max_width = Enum.max([
        String.length(Enum.at(headers, i)) |
        Enum.map(rows, fn row -> String.length(Enum.at(row, i) || "") end)
      ])
      max_width + 2
    end)

    # Header
    header_line = headers
      |> Enum.with_index()
      |> Enum.map(fn {h, i} -> String.pad_trailing(h, Enum.at(widths, i)) end)
      |> Enum.join("│")

    IO.puts(header_line)
    IO.puts(String.duplicate("─", String.length(header_line)))

    # Rows
    Enum.each(rows, fn row ->
      line = row
        |> Enum.with_index()
        |> Enum.map(fn {cell, i} -> String.pad_trailing(cell || "", Enum.at(widths, i)) end)
        |> Enum.join("│")
      IO.puts(line)
    end)
  end
end
