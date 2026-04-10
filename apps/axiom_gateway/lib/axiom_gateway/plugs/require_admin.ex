defmodule AxiomGateway.Plugs.RequireAdmin do
  @moduledoc """
  Route-level authorization guard for admin operations.
  """

  import Plug.Conn

  @admin_roles MapSet.new(["admin", "ops_admin"])

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user] || %{}
    role = Map.get(user, :role) || Map.get(user, "role")

    if MapSet.member?(@admin_roles, role) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
      |> halt()
    end
  end
end
