defmodule GlobalCombat.Games.PlayerView do
  @moduledoc """
  Builds the fog-of-war-filtered projection of a `GlobalCombat.Engine.Game` for one
  viewer — the *only* sanctioned way game state reaches `GameLive` (GIF-30).

  Port of the filtering `Web/Views/Game/Index.cshtml` does inline while rendering
  (`Model.IsFogged && !isOwner` at line 158, and the `isOwner ? areaData.AssignedArmies : 0`
  guards a few lines below it). That logic lived in the view because the legacy app
  rendered server-side HTML per request, so "filter while rendering" and "filter before
  rendering" were the same moment. A LiveView socket holds state *between* renders, so
  the two moments are no longer the same thing — `GlobalCombat.Games.Server` must never
  hand its canonical `%GlobalCombat.Engine.Game{}` to the web layer and trust the
  template to filter it on the way out, because every `handle_info(:reload, socket)`
  after the first render is a second chance to `assign` the unfiltered struct by
  accident. Filtering happens once, here, at the context boundary
  (`GlobalCombat.Games.Live.player_view/2`) — `GameLive` never touches `Engine.Game` at all.

  Two independent things are hidden from a non-owner, matching the original exactly:

    1. Fog of war (`is_fogged: true`, the `IsFogged` game option): an area's true
       owner/army-count is hidden unless the viewer owns it, or owns an area that
       links to it (`inbounds` — the original computes `Model.GetArea(inbound).Owner.Number
       == Player.Number`). A hidden area's "owner" always renders as the neutral/no-owner
       color (`owner.Number % 9` with owner forced to 0), same as the original's `showArea
       ? ... : 0` image-name suffix — never the real owner number with a "??" army count,
       which would leak *who* owns it even while hiding *how much*.
    2. Assigned-but-unresolved armies (`assigned_armies`) are folded into the displayed
       army count *only* for the area's own owner, unconditionally — even in a
       non-fogged game. Every other viewer sees the area's resolved `armies` only. This
       is what stops "how many armies did my opponent just queue for their next attack"
       from leaking to anyone but the player who queued it.

  Player roll-ups (name, total armies, area count, done/eliminated/place) are **not**
  fog-gated — `Index.cshtml`'s `PlayerReadout` table shows every player's totals to
  everyone in the game regardless of `IsFogged`; only the per-area board detail is
  hidden. A spectator (`viewer_number: nil`) sees exactly what a fogged non-owner sees.
  """

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.MapInfo

  defstruct [
    :game_id,
    :map_name,
    :turn,
    :ended,
    :is_fogged,
    :viewer_number,
    areas: [],
    players: [],
    messages: []
  ]

  @doc """
  Builds the view for `viewer_number` (an `Engine.Game.Player.number`, or `nil` for a
  spectator/not-yet-joined visitor) from `engine` — the game's canonical state — plus
  the surrounding metadata `GlobalCombat.Games.Server` tracks alongside it.
  """
  def build(%Engine{} = engine, viewer_number, opts \\ []) do
    game_id = Keyword.fetch!(opts, :game_id)
    is_fogged = Keyword.fetch!(opts, :is_fogged)
    messages = Keyword.get(opts, :messages, [])

    %__MODULE__{
      game_id: game_id,
      map_name: engine.map_name,
      turn: engine.turn,
      ended: engine.ended,
      is_fogged: is_fogged,
      viewer_number: viewer_number,
      areas:
        Enum.map(Engine.areas_in_order(engine), &area_view(engine, &1, viewer_number, is_fogged)),
      players: Enum.map(Engine.players_in_order(engine), &player_summary/1),
      messages: messages
    }
  end

  defp area_view(engine, %Engine.Area{} = area, viewer_number, is_fogged) do
    owns_it? = area.owner_number == viewer_number
    visible? = not is_fogged or owns_it? or owns_adjacent?(engine, area, viewer_number)

    {tech_name, x, y, width, height} = MapInfo.render_info(engine.map_name, area.number)

    %{
      number: area.number,
      tech_name: tech_name,
      x: x,
      y: y,
      width: width,
      height: height,
      visible: visible?,
      owner_number: if(visible?, do: area.owner_number, else: nil),
      armies: area_armies(area, visible?, owns_it?)
    }
  end

  defp area_armies(_area, false, _owns_it?), do: nil
  defp area_armies(area, true, false), do: area.armies
  defp area_armies(area, true, true), do: area.armies + area.assigned_armies

  defp owns_adjacent?(_engine, _area, nil), do: false

  defp owns_adjacent?(engine, area, viewer_number) do
    MapInfo.inbounds(engine.map_name, area.number)
    |> Enum.any?(fn inbound_number ->
      Engine.area!(engine, inbound_number).owner_number == viewer_number
    end)
  end

  defp player_summary(%Engine.Player{} = player) do
    %{
      number: player.number,
      account_id: player.account_id,
      name: player.name,
      done: player.done,
      eliminated: Engine.eliminated?(player),
      place: player.place,
      areas: player.areas,
      armies: player.armies,
      unassigned_armies: player.unassigned_armies
    }
  end
end
