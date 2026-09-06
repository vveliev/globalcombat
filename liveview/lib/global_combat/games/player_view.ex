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

  Three independent things are hidden from a non-owner, matching the original exactly:

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
    3. A queued transfer/attack (`order: %{command:, target:, amount:}`) is `nil` for
       every non-owner regardless of `is_fogged` — the board's pending-orders arrow
       overlay must never let an opponent preview a move before it resolves, which is
       a stricter bar than fog of war itself (fog can still reveal an *area's*
       owner/armies to an inbound neighbour; an order is never shared, full stop).

  Player roll-ups (name, total armies, area count, done/eliminated/place) are **not**
  fog-gated — `Index.cshtml`'s `PlayerReadout` table shows every player's totals to
  everyone in the game regardless of `IsFogged`; only the per-area board detail is
  hidden. A spectator (`viewer_number: nil`) sees exactly what a fogged non-owner sees.

  ## Turn-resolution event visibility

  `last_turn_log` (a `GlobalCombat.Games.TurnLog` wrapping the previous turn's
  `GlobalCombat.Engine.Game.resolve_turn/1` log) is filtered by the *same* rule as the board
  above, applied per event rather than per area — an event is exposed only if every area it
  touches (`{:assign, area, _}`'s one area; `{:transfer, from, to, _}`/`{:attack, from, to,
  ...}`'s two) was visible to this viewer (owned, or adjacent to an owned area) at *either*
  endpoint of the turn: right before it resolved, or right after. Checking only "after" would
  leak a hidden area's fate the instant it changes hands (an attack into fog the viewer had no
  way to see coming); checking only "before" would keep hiding an attack the viewer's own troops
  just captured visibility into. Both instants have to be checked independently —
  `owns_adjacent?/3` depends on a *neighboring* area's owner, which can itself flip mid-turn, so
  "visible before" and "visible after" are genuinely different computations, not the same check
  run twice. `{:eliminated, _}`/`{:ended, _}` touch no area and are never filtered, matching the
  player-roll-up rule above (elimination/game-end is public information, not a board detail).

  The "before" ownership snapshot has no equivalent already sitting in `Engine.Game` — the engine
  is pure and only ever hands back the *resolved* state (see its moduledoc's "old state is
  discarded" framing) — so `GlobalCombat.Games.Server` captures owner numbers only (never army
  counts, which this rule never needs) just before calling `resolve_turn/1`, via
  `TurnLog.snapshot/3`'s `before_owners`.

  `last_turn_log.turn` is checked against `engine.turn` before any of the above runs at all: a
  log whose stamped turn doesn't match the state it's paired with (a rehydrate that landed one
  half of `GlobalCombat.Games.persist_turn/3`'s atomic pair without the other would still be a
  bug, but this is a second, structural line of defense against it; a game rehydrated before the
  `last_turn_events` column existed, decoding to `turn: nil`, hits the same path) drops the whole
  log rather than risk a plausible-looking but wrong replay.
  """

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombat.Games.TurnLog

  defstruct [
    :game_id,
    :map_name,
    :turn,
    :ended,
    :is_fogged,
    :viewer_number,
    areas: [],
    players: [],
    messages: [],
    last_turn_events: []
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
    last_turn_log = Keyword.get(opts, :last_turn_log, %TurnLog{})

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
      messages: messages,
      last_turn_events: visible_events(engine, viewer_number, is_fogged, last_turn_log)
    }
  end

  # See the moduledoc's turn-stamp paragraph — a log stamped for some turn other than the one
  # this render shows is dropped outright, not partially trusted.
  defp visible_events(engine, viewer_number, is_fogged, %TurnLog{turn: turn} = log) do
    if turn == engine.turn do
      Enum.filter(
        log.events,
        &event_visible?(&1, engine, log.before_owners, viewer_number, is_fogged)
      )
    else
      []
    end
  end

  defp area_view(engine, %Engine.Area{} = area, viewer_number, is_fogged) do
    owns_it? = area.owner_number == viewer_number
    visible? = not is_fogged or owns_it? or owns_adjacent?(engine, area, viewer_number)

    {tech_name, x, y, width, height} = MapInfo.render_info(engine.map_name, area.number)
    {_number, name, _region, links} = MapInfo.area(engine.map_name, area.number)

    %{
      number: area.number,
      name: name,
      tech_name: tech_name,
      x: x,
      y: y,
      width: width,
      height: height,
      visible: visible?,
      owner_number: if(visible?, do: area.owner_number, else: nil),
      armies: area_armies(area, visible?, owns_it?),
      # GIF-111: how many of `armies` above are still a pending (unresolved) assignment
      # this owner queued this turn, as opposed to already-resolved troops — the same
      # `assigned_armies` this area's `armies` already folds in for its owner (see
      # `area_armies/3` below), exposed separately so the order panel can offer
      # "Unassign" only when there is something to undo. Zero for every non-owner,
      # for the same reason `armies` itself is never split out for them.
      pending_armies: if(visible? and owns_it?, do: area.assigned_armies, else: 0),
      # Map topology (which territories border which) is never secret — it's the
      # same static layout every viewer already sees rendered on the board
      # regardless of fog, unlike `owner_number`/`armies` above. Safe to expose in
      # full for GIF-81's accessible board table.
      adjacent: links,
      # The viewer's own queued transfer/attack, for the board's pending-orders arrow
      # overlay. `nil` for every non-owner (fog-of-war for *orders*, not just areas —
      # an opponent must never see what a player queued before it resolves) and also
      # `nil` for the owner's own area when there's nothing queued (`:command ==
      # :none`), so the overlay's `if area.order do` has one clean falsy case to check
      # instead of a sentinel command atom.
      order: order_view(area, owns_it?)
    }
  end

  defp area_armies(_area, false, _owns_it?), do: nil
  defp area_armies(area, true, false), do: area.armies
  defp area_armies(area, true, true), do: area.armies + area.assigned_armies

  defp order_view(%Engine.Area{command: :none}, _owns_it?), do: nil
  defp order_view(_area, false), do: nil

  defp order_view(%Engine.Area{} = area, true),
    do: %{command: area.command, target: area.target_number, amount: area.amount}

  defp owns_adjacent?(_engine, _area, nil), do: false

  defp owns_adjacent?(engine, area, viewer_number) do
    MapInfo.inbounds(engine.map_name, area.number)
    |> Enum.any?(fn inbound_number ->
      Engine.area!(engine, inbound_number).owner_number == viewer_number
    end)
  end

  # See the moduledoc's "Turn-resolution event visibility" section — an event is exposed
  # only if every area it touches was visible to this viewer either right before this turn
  # resolved (`before_owners`) or right after (`engine`'s own current state); `{:eliminated, _}`/
  # `{:ended, _}` touch no area and are always exposed, same as the player roll-ups above.
  defp event_visible?(event, engine, before_owners, viewer_number, is_fogged) do
    before_owner = before_owners_lookup(before_owners)
    current_owner = current_owner_lookup(engine)

    event
    |> event_area_numbers()
    |> Enum.all?(fn area_number ->
      area_visible_at?(before_owner, engine, viewer_number, is_fogged, area_number) or
        area_visible_at?(current_owner, engine, viewer_number, is_fogged, area_number)
    end)
  end

  defp event_area_numbers({:assign, area, _amount}), do: [area]
  defp event_area_numbers({:transfer, from, to, _amount}), do: [from, to]

  defp event_area_numbers(
         {:attack, from, to, _amount, _attacker_lost, _defender_lost, _captured?}
       ),
       do: [from, to]

  defp event_area_numbers({:eliminated, _player}), do: []
  defp event_area_numbers({:ended, _winner}), do: []

  # `Map.get/3` with a sentinel, not `Map.fetch!/2`: a turn-mismatched log is already dropped
  # before this runs (see `visible_events/4`), but `before_owners` still shouldn't be trusted to
  # have an entry for every area an event names — a missing key is treated as "not visible",
  # never as a match, which is why the sentinel can't be `nil` (a real, valid owner_number for an
  # unowned area, and `viewer_number` itself for a spectator).
  defp before_owners_lookup(before_owners) do
    fn number -> Map.get(before_owners, number, :area_not_in_before_owners) end
  end

  defp current_owner_lookup(engine),
    do: fn number -> Engine.area!(engine, number).owner_number end

  defp area_visible_at?(_owner_of, _engine, _viewer_number, false, _area_number), do: true

  # A spectator (`viewer_number: nil`) never expands visibility through adjacency — same guard
  # as `owns_adjacent?/3` above, and for the same reason: `owner_number` is `nil` for every
  # unowned area, which would otherwise equal a spectator's `nil` viewer_number and spuriously
  # "match" as ownership, making almost any area (adjacent to at least one unowned neighbor)
  # look visible to a spectator regardless of who actually holds it.
  defp area_visible_at?(owner_of, _engine, nil, true, area_number),
    do: owner_of.(area_number) == nil

  defp area_visible_at?(owner_of, engine, viewer_number, true, area_number) do
    owner_of.(area_number) == viewer_number or
      MapInfo.inbounds(engine.map_name, area_number)
      |> Enum.any?(&(owner_of.(&1) == viewer_number))
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
      unassigned_armies: player.unassigned_armies,
      # The Elo-style score the engine's own end-game path computes (`Game.cs`'s legacy
      # "Score Expected = X, Score = Y, Rating Change = Z" readout) never left the engine —
      # a returning player finishing a game never saw the number they used to get.
      score: player.score
    }
  end
end
