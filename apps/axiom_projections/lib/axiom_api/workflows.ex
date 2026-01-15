defmodule Axiom.API.Workflows do
  @moduledoc """
  Workflow API handlers.
  """

  alias Axiom.Core.Event

  @doc """
  Lists workflows with pagination.
  """
  def list(opts \\ []) do
    _limit = Keyword.get(opts, :limit, 20)
    _offset = Keyword.get(opts, :offset, 0)

    # Would query projections in production
    {:ok, []}
  end

  @doc """
  Creates a new workflow.
  """
  def create(name, input, steps) do
    workflow_id = Event.generate_uuid()

    case AxiomEngine.create_workflow(name, input, steps) do
      {:ok, ^workflow_id} ->
        {:ok, %{
          id: workflow_id,
          name: name,
          steps: steps,
          state: "pending",
          created_at: System.system_time(:millisecond)
        }}

      {:ok, id} ->
        {:ok, %{
          id: id,
          name: name,
          steps: steps,
          state: "pending",
          created_at: System.system_time(:millisecond)
        }}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Gets a workflow by ID.
  """
  def get(id) do
    case AxiomEngine.get_workflow(id) do
      {:ok, state} ->
        {:ok, %{
          id: id,
          name: state.name,
          steps: state.steps,
          step_states: state.step_states,
          state: to_string(state.state),
          version: state.version
        }}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets workflow events.
  """
  def get_events(id) do
    case Axiom.WAL.LogAppendServer.replay(id) do
      {:ok, events} ->
        formatted = Enum.map(events, fn event ->
          %{
            id: event.event_id,
            type: event.event_type,
            sequence: event.sequence,
            timestamp: event.timestamp,
            payload: event.payload
          }
        end)
        {:ok, formatted}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :not_found}
  end

  @doc """
  Advances a workflow.
  """
  def advance(id) do
    AxiomEngine.advance_workflow(id)
  end
end
