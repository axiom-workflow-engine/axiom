defmodule AxiomGateway.RouterIntegrationTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AxiomGateway.Plugs.Auth
  alias AxiomGateway.Router

  setup do
    previous_secret = Application.get_env(:axiom_gateway, :jwt_secret)
    on_exit(fn -> Application.put_env(:axiom_gateway, :jwt_secret, previous_secret) end)

    Application.put_env(:axiom_gateway, :jwt_secret, "integration-test-jwt-secret")
    :ok
  end

  test "GET /health returns liveness payload" do
    conn = conn(:get, "/health") |> dispatch()

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "alive"
    assert is_binary(body["timestamp"])
  end

  test "GET /ready returns readiness payload" do
    conn = conn(:get, "/ready") |> dispatch()

    assert conn.status in [200, 503]

    body = Jason.decode!(conn.resp_body)
    assert body["status"] in ["ready", "not_ready"]
    assert is_map(body["checks"])
  end

  test "GET /api/v1/openapi.json serves openapi spec" do
    conn = conn(:get, "/api/v1/openapi.json") |> dispatch()

    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["openapi"] == "3.0.3"
    assert is_map(body["paths"])
  end

  test "POST /api/v1/webhooks/:id accepts webhook payload" do
    conn = conn(:post, "/api/v1/webhooks/order-created") |> dispatch()

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "accepted"
    assert body["webhook_id"] == "order-created"
  end

  test "authenticated non-admin user is forbidden from admin routes" do
    conn =
      conn(:post, "/api/v1/verify")
      |> put_req_header("authorization", "Bearer #{jwt_for_role("user")}")
      |> dispatch()

    assert conn.status == 403
    assert conn.resp_body =~ "forbidden"
  end

  test "authenticated admin user can reach admin routes" do
    conn =
      conn(:post, "/api/v1/verify")
      |> put_req_header("authorization", "Bearer #{jwt_for_role("admin")}")
      |> dispatch()

    assert conn.status != 403
    assert conn.status != 401
  end

  test "protected new controller routes require authentication" do
    metrics_conn = conn(:get, "/api/v1/metrics") |> dispatch()
    tasks_conn = conn(:get, "/api/v1/tasks") |> dispatch()

    assert metrics_conn.status == 401
    assert tasks_conn.status == 401
  end

  defp dispatch(conn) do
    conn =
      if get_req_header(conn, "accept") == [] do
        put_req_header(conn, "accept", "application/json")
      else
        conn
      end

    Router.call(conn, Router.init([]))
  end

  defp jwt_for_role(role) do
    signer = Joken.Signer.create("HS256", "integration-test-jwt-secret")
    claims = %{"role" => role, "tenant_id" => "tenant-test", "sub" => "integration-user"}

    result =
      cond do
        function_exported?(Auth.Token, :generate_and_sign, 2) ->
          Auth.Token.generate_and_sign(claims, signer)

        function_exported?(Auth.Token, :generate_and_sign, 1) ->
          Auth.Token.generate_and_sign(claims)

        true ->
          {:error, :no_signing_function}
      end

    case result do
      {:ok, token, _claims} -> token
      {:ok, token} -> token
      {:error, reason} -> raise "failed to create test jwt: #{inspect(reason)}"
    end
  end
end
