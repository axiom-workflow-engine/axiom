defmodule Axiom.API.GraphQL.Plug do
  @moduledoc """
  Plug for handling GraphQL requests.
  """

  use Plug.Builder

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug Absinthe.Plug,
    schema: Axiom.API.GraphQL.Schema,
    json_codec: Jason
end
