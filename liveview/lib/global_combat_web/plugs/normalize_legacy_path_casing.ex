defmodule GlobalCombatWeb.Plugs.NormalizeLegacyPathCasing do
  @moduledoc """
  ASP.NET Core's routing — including the regex-based `{action}` constraint
  used for the legacy shortcut set — matches URL segments case-insensitively
  by default. Phoenix's router does an exact byte-for-byte match, so without
  this, a 25-year-old inbound link, bookmark, or search result that differs
  only in case (`/game-684316`, `/PLAYERINFO`, `/game-manual`) would have
  worked on the old globalcombat.com but 404 here (GIF-31).

  Must run in the endpoint, before the router: route dispatch pattern-matches
  directly on `path_info`, before any pipeline (`pipe_through`) plugs run, so
  rewriting inside a pipeline would be too late to affect route selection.

  Only rewrites segments that case-insensitively match one of the legacy
  segments this ticket added to the router — every other path (including
  future, non-legacy routes) passes through untouched. The second segment is
  only ever touched for `/Home/Index` (the one two-segment fully-literal
  route registered); the free-form `:action` segment in `/Game-:id/:action`
  is deliberately left alone, since the controller doesn't discriminate on
  its case anyway.
  """

  @behaviour Plug

  @literal_segments ~w(
    Create-Game Create-Tournament Game-Manual Send-Message
    Messages Stats IpAddresses GameManual OptOut PlayerInfo Chat
    LoadChatMessages CloseChatWindow SendMessage Home
  )

  @prefixes ~w(Player-Info- Tournament- Game-)

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: path_info} = conn, _opts) do
    case normalize(path_info) do
      ^path_info -> conn
      normalized -> %{conn | path_info: normalized}
    end
  end

  defp normalize([first, second]) do
    case canonical_segment(first) do
      "Home" = home ->
        if String.downcase(second) == "index", do: [home, "Index"], else: [home, second]

      nil ->
        [first, second]

      canonical ->
        [canonical, second]
    end
  end

  defp normalize([first | rest]) do
    case canonical_segment(first) do
      nil -> [first | rest]
      canonical -> [canonical | rest]
    end
  end

  defp normalize(path_info), do: path_info

  defp canonical_segment(segment) do
    downcased = String.downcase(segment)

    Enum.find(@literal_segments, &(String.downcase(&1) == downcased)) ||
      canonical_prefixed_segment(segment, downcased)
  end

  defp canonical_prefixed_segment(segment, downcased) do
    Enum.find_value(@prefixes, fn prefix ->
      prefix_size = byte_size(prefix)

      if String.downcase(prefix) ==
           binary_part(downcased, 0, min(prefix_size, byte_size(downcased))) do
        prefix <> binary_part(segment, prefix_size, byte_size(segment) - prefix_size)
      end
    end)
  end
end
