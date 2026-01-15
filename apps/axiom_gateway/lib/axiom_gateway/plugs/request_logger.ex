defmodule AxiomGateway.Plugs.RequestLogger do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      stop = System.monotonic_time()
      diff = System.convert_time_unit(stop - start, :native, :microsecond)

      Logger.info(
        "method=#{conn.method} path=#{conn.request_path} status=#{conn.status} duration=#{diff}us"
      )

      conn
    end)
  end
end
