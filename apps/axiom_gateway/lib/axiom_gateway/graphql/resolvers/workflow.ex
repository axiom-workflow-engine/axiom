defmodule AxiomGateway.GraphQL.Resolvers.Workflow do
  alias AxiomGateway.Projections.WorkflowIndex



  alias Axiom.WAL.LogAppendServer
  alias Axiom.Engine.StateMachine
  alias AxiomGateway.Durable.Acceptor

  def list_workflows(_parent, %{limit: limit}, _resolution) do
     # Delegate to the projection
     {:ok, WorkflowIndex.list_workflows(limit)}
  end

  def get_workflow(_parent, %{id: id}, _resolution) do
     # For GraphQL detail view, we likely want the full state (steps, history).
     # The Index only has the summary.
     # We try to fetch from the running process or rehydrate from WAL.

     case Registry.lookup(Axiom.Engine.Registry, id) do
       [{pid, _}] ->
          state_machine = Axiom.Engine.WorkflowProcess.get_state(pid)
          {:ok, map_state_to_graphql(state_machine)}

       [] ->
          # Rehydrate ephemeral
          case LogAppendServer.replay(LogAppendServer, id) do
            {:ok, events} when events != [] ->
               state_machine = StateMachine.hydrate(id, events)
               {:ok, map_state_to_graphql(state_machine)}
            _ ->
               {:error, "Workflow not found"}
          end
     end
  end

  def create_workflow(_parent, args, %{context: context}) do
    # context.current_user should be populated by the Context plug
    identity = Map.get(context, :current_user, %{role: "anonymous"})

    # Args coming from GraphQL: %{name: "...", steps: ["..."], input: "..."}
    # Acceptor expects a map with string keys for params
    params = %{
      "name" => args.name,
      "steps" => args.steps,
      "input" => args[:input] && Jason.decode!(args.input) # Assuming input is JSON string
    }

    case Acceptor.accept_workflow(params, identity) do
      {:ok, id} ->
         # Return the initial state
         {:ok, %{
           id: id,
           name: args.name,
           status: "accepted",
           created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
           steps: [],
           history: []
         }}
      {:error, reason} ->
         {:error, inspect(reason)}
    end
  end

  defp map_state_to_graphql(sm) do
    # Get creation time from the first event (at the end of history list)
    first_event = List.last(sm.history)
    created_at = if first_event, do: format_timestamp(first_event.timestamp), else: DateTime.utc_now() |> DateTime.to_iso8601()
    
    # Get last update time from the newest event (at the head of history list)
    last_event = List.first(sm.history)
    updated_at = if last_event, do: format_timestamp(last_event.timestamp), else: created_at

    %{
      id: sm.workflow_id,
      name: sm.name || "Workflow-#{sm.workflow_id}",
      status: if(StateMachine.terminal?(sm), do: "completed", else: "running"),
      created_at: created_at,
      updated_at: updated_at,
      steps: Enum.map(sm.step_states, fn {step, status} ->
        %{
          name: Atom.to_string(step),
          status: Atom.to_string(status),
          attempt: 1,
          result: nil,
          error: nil
        }
      end),
      history: sm.history |> Enum.map(fn event ->
        %{
          sequence: event.sequence,
          event_type: Atom.to_string(event.event_type),
          timestamp: format_timestamp(event.timestamp),
          details: Jason.encode!(event.payload)
        }
      end)
    }
  end

  defp format_timestamp(logical_ns) do
    # Convert logical nanoseconds back to ISO8601 if possible, or just keep as string
    # For now, we'll convert to a DateTime if it's based on system time offset
    # logical_time = monotonic + offset. 
    # offset = wall_clock - monotonic.
    # So logical_time is roughly wall_clock in nanoseconds.
    
    logical_ns
    |> div(1_000_000_000)
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end
end
