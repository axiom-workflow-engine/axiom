defmodule AxiomGateway.GraphQL.Context do
  @moduledoc """
  Plug to build the Absinthe context.
  Extracts the current user from conn.assigns (set by Auth plug)
  and puts it into the Absinthe context.
  """
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    context = build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

  defp build_context(conn) do
    case conn.assigns[:current_user] do
      nil -> %{}
      user -> %{current_user: user}
    end
  end
end
