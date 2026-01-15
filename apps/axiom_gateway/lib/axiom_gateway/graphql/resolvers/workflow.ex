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
    %{
      id: sm.workflow_id,
      name: "Workflow-#{sm.workflow_id}", # Name might not be in SM state directly, strictly speaking.
                                          # Ideally SM state includes metadata. For now, ID fallback.
      status: if(StateMachine.terminal?(sm), do: "completed", else: "running"),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(), # Placeholder if SM doesn't track creation time
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      steps: Enum.map(sm.step_states, fn {step, status} ->
        %{
          name: Atom.to_string(step),
          status: Atom.to_string(status),
          attempt: 1, # Simplified
          result: nil,
          error: nil
        }
      end),
      history: sm.history |> Enum.map(fn event ->
        %{
          sequence: event.sequence,
          event_type: Atom.to_string(event.event_type),
          timestamp: DateTime.to_iso8601(DateTime.utc_now()),
          details: Jason.encode!(event.payload)
        }
      end)
    }
  end
end
