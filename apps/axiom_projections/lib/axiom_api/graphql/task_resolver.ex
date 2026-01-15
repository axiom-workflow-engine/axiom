defmodule Axiom.API.GraphQL.TaskResolver do
  @moduledoc """
  GraphQL resolvers for task queries.
  """

  alias Axiom.API.Tasks

  def get_stats(_parent, _args, _context) do
    case Tasks.list() do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
