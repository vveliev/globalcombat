defmodule GlobalCombatWeb.Plugs.HealthCheck do
  @moduledoc """
  Liveness probe at `GET /up` for kamal-proxy (`config/deploy.yml`): it only switches
  traffic to a newly deployed container once this returns 200.

  Answers before the rest of the endpoint (no session, no router, no database), so
  it reports "the release booted and the HTTP server is serving". `/up` is also in
  `force_ssl`'s `exclude` list (`config/prod.exs`), because the proxy probes the
  container over plain HTTP.
  """

  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: method, path_info: ["up"]} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
