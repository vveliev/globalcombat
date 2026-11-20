defmodule GlobalCombatWeb.Plugs.ForwardedClientIp do
  @moduledoc """
  Sets `conn.remote_ip` to the real client address when the app sits behind a
  reverse proxy (kamal-proxy, `config/deploy.yml`), so login history (`Accounts.list_logins_for_ip/1`,
  the admin `/IpAddresses` page) records players rather than the proxy container.

  Trust rule: `X-Forwarded-For` is only honoured when the TCP peer is on a
  private, loopback or link-local network — i.e. the proxy on the Docker network.
  A request reaching Phoenix directly from a public address keeps its peer address,
  so a client can't spoof its IP by sending the header itself.

  Only the right-most entry is used: that's the one the proxy appended; anything to
  its left was supplied by the client.

  This relies on Phoenix's port never being published straight to the internet:
  Docker's port forwarding makes every client look like the private bridge gateway,
  which this plug would then trust. Under Kamal (and `docker-compose.prod.yml`) only
  the proxy publishes ports.
  """

  @behaviour Plug

  import Bitwise

  def init(opts), do: opts

  def call(%Plug.Conn{remote_ip: peer} = conn, _opts) do
    with true <- trusted_proxy?(peer),
         [header | _] <- Plug.Conn.get_req_header(conn, "x-forwarded-for"),
         {:ok, client} <- last_address(header) do
      %{conn | remote_ip: client}
    else
      _ -> conn
    end
  end

  defp last_address(header) do
    header
    |> String.split(",")
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
  end

  # IPv4: loopback, RFC 1918, link-local.
  defp trusted_proxy?({127, _, _, _}), do: true
  defp trusted_proxy?({10, _, _, _}), do: true
  defp trusted_proxy?({172, b, _, _}) when b in 16..31, do: true
  defp trusted_proxy?({192, 168, _, _}), do: true
  defp trusted_proxy?({169, 254, _, _}), do: true
  # IPv6: loopback, unique local (fc00::/7), link-local (fe80::/10), IPv4-mapped.
  defp trusted_proxy?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp trusted_proxy?({a, _, _, _, _, _, _, _}) when (a &&& 0xFE00) == 0xFC00, do: true
  defp trusted_proxy?({a, _, _, _, _, _, _, _}) when (a &&& 0xFFC0) == 0xFE80, do: true

  defp trusted_proxy?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: trusted_proxy?({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  defp trusted_proxy?(_), do: false
end
