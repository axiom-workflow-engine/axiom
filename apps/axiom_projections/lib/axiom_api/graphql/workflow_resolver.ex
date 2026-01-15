defmodule Axiom.API.GraphQL.WorkflowResolver do
  @moduledoc """
  GraphQL resolvers for workflow queries and mutations.
  """

  alias Axiom.API.Workflows

  def get(_parent, %{id: id}, _context) do
    case Workflows.get(id) do
      {:ok, workflow} -> {:ok, workflow}
      {:error, :not_found} -> {:error, "Workflow not found"}
    end
  end

  def list(_parent, args, _context) do
    opts = [
      limit: Map.get(args, :limit, 20),
      offset: Map.get(args, :offset, 0)
    ]

    case Workflows.list(opts) do
      {:ok, workflows} -> {:ok, workflows}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def create(_parent, args, _context) do
    name = args.name
    steps = Enum.map(args.steps, &String.to_atom/1)
    input = Map.get(args, :input, %{})

    case Workflows.create(name, input, steps) do
      {:ok, workflow} -> {:ok, workflow}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def advance(_parent, %{id: id}, _context) do
    case Workflows.advance(id) do
      :ok ->
        {:ok, %{success: true, message: "Workflow advanced", id: id}}
      {:error, reason} ->
        {:ok, %{success: false, message: inspect(reason), id: id}}
    end
  end

  def get_events(workflow, _args, _context) do
    case Workflows.get_events(workflow.id) do
      {:ok, events} -> {:ok, events}
      {:error, _} -> {:ok, []}
    end
  end
end
