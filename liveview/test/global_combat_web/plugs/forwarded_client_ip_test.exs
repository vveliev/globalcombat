defmodule GlobalCombatWeb.Plugs.ForwardedClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias GlobalCombatWeb.Plugs.ForwardedClientIp

  defp call(peer, xff \\ nil) do
    conn = conn(:get, "/") |> Map.put(:remote_ip, peer)
    conn = if xff, do: put_req_header(conn, "x-forwarded-for", xff), else: conn
    ForwardedClientIp.call(conn, ForwardedClientIp.init([]))
  end

  describe "from a private-network peer (the reverse proxy)" do
    test "uses the forwarded client address" do
      assert call({172, 18, 0, 5}, "203.0.113.7").remote_ip == {203, 0, 113, 7}
    end

    test "uses the address nearest the proxy when the header lists several" do
      # The proxy appends the address it saw; anything left of it is client-supplied.
      assert call({10, 0, 0, 2}, "198.51.100.1, 203.0.113.7").remote_ip == {203, 0, 113, 7}
    end

    test "trusts IPv6 unique-local and IPv4-mapped private peers" do
      assert call({0xFD00, 0, 0, 0, 0, 0, 0, 2}, "203.0.113.7").remote_ip == {203, 0, 113, 7}

      assert call({0, 0, 0, 0, 0, 0xFFFF, 0xAC12, 0x0005}, "203.0.113.7").remote_ip ==
               {203, 0, 113, 7}
    end

    test "accepts IPv6 client addresses" do
      assert call({172, 18, 0, 5}, "2001:db8::1").remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
    end

    test "keeps the peer address when the header is missing or malformed" do
      assert call({172, 18, 0, 5}).remote_ip == {172, 18, 0, 5}
      assert call({172, 18, 0, 5}, "not-an-ip").remote_ip == {172, 18, 0, 5}
      assert call({172, 18, 0, 5}, "").remote_ip == {172, 18, 0, 5}
    end
  end

  describe "from a public peer (no proxy in front)" do
    test "ignores the header so clients can't spoof their address" do
      assert call({203, 0, 113, 9}, "192.0.2.1").remote_ip == {203, 0, 113, 9}
      assert call({172, 32, 0, 1}, "192.0.2.1").remote_ip == {172, 32, 0, 1}

      assert call({0x2001, 0xDB8, 0, 0, 0, 0, 0, 9}, "192.0.2.1").remote_ip ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 9}
    end
  end
end
