defmodule AxiomGateway.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug using Hammer.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    # Identify bucket: tenant_id + purpose
    tenant_id = user[:tenant_id] || "anonymous"

    # 100 requests per minute
    case Hammer.check_rate("request:#{tenant_id}", 60_000, 100) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", "100")
        |> put_resp_header("x-ratelimit-remaining", Integer.to_string(100 - count))

      {:deny, limit} ->
        conn
        |> put_resp_header("x-ratelimit-limit", "100")
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, Jason.encode!(%{error: "Too Many Requests"}))
        |> halt()
    end
  end
end
