defmodule GlobalCombatWeb.Plugs.HealthCheckTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias GlobalCombatWeb.Plugs.HealthCheck

  defp call(method, path), do: HealthCheck.call(conn(method, path), HealthCheck.init([]))

  test "answers GET /up with 200 and halts before the rest of the endpoint" do
    conn = call(:get, "/up")

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "answers HEAD /up too" do
    assert call(:head, "/up").status == 200
  end

  test "passes every other request through untouched" do
    for {method, path} <- [{:get, "/"}, {:get, "/upload"}, {:post, "/up"}, {:get, "/up/x"}] do
      conn = call(method, path)
      refute conn.halted
      assert conn.status == nil
    end
  end
end
