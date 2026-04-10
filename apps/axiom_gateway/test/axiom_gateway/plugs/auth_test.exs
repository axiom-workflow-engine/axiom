defmodule AxiomGateway.Plugs.AuthTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AxiomGateway.Plugs.Auth

  test "rejects jwt authentication when JWT_SECRET is not configured" do
    previous_secret = Application.get_env(:axiom_gateway, :jwt_secret)
    on_exit(fn -> Application.put_env(:axiom_gateway, :jwt_secret, previous_secret) end)

    Application.delete_env(:axiom_gateway, :jwt_secret)

    conn =
      conn(:get, "/api/v1/metrics")
      |> put_req_header("authorization", "Bearer any-token")
      |> Auth.call([])

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "jwt_secret_not_configured"
  end
end
