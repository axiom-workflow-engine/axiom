defmodule AxiomGateway.Plugs.RequireAdminTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias AxiomGateway.Plugs.RequireAdmin

  test "allows admin role" do
    conn =
      conn(:post, "/api/v1/verify")
      |> assign(:current_user, %{role: "admin"})
      |> RequireAdmin.call([])

    refute conn.halted
  end

  test "rejects non-admin role" do
    conn =
      conn(:post, "/api/v1/verify")
      |> assign(:current_user, %{role: "user"})
      |> RequireAdmin.call([])

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body =~ "forbidden"
  end
end
