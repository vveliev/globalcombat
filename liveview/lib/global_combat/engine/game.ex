defmodule GlobalCombat.Engine.Game do
  @moduledoc """
  Port of the turn-resolution rules in `GlobalCombat.Core/Game.cs` (GIF-28).

  Scope: this module ports `RunTurn` and everything it calls transitively —
  transfers, attack resolution (`DoAttack`/`DoTransfer`), reinforcement/region
  bonuses, elimination, end-game Elo scoring — plus the `SetAssigned`/
  `SetAttack`/`SetTransfer` order-setters `RandomAiPlayer` and human players
  both use to queue commands. It deliberately does **not** port `Start()`
  (the initial random area deal): the differential harness always sources a
  game's starting state from the .NET oracle's own `NewGame` response and
  operates on that from then on, exactly as the issue describes ("the harness
  feeds identical game state plus identical orders to both engines") — it
  never needs to reproduce Start()'s own RNG-driven area-assignment retry
  loop independently. `fog of war` is also out of scope here for the same
  reason it's out of scope for RunTurn in the original: it's a read-model
  projection over `Areas`/`Player.Number` applied in the view layer
  (`Web/Views/Game/Index.cshtml:158`), not a state mutation `RunTurn` performs.

  Message/HTML string building (`DoAttack`'s narrated combat text,
  `RunTurn`'s turn-summary string) is not ported — those are presentation,
  not state, and the harness diffs state.

  Every function here is pure: no field is mutated in place (Elixir has no
  such thing) — each returns an updated `%Game{}` (or `{value, %Game{}}` when
  the original C# method also returned something, like `SetAttack`'s
  clamped amount).
  """

  alias GlobalCombat.Engine.{DotnetRandom, MapInfo}

  defmodule Area do
    @moduledoc "Port of `GlobalCombat.Core/Area.cs`. `owner_number` is `nil` for an unowned area."
    defstruct [
      :number,
      :owner_number,
      armies: 5,
      assigned_armies: 0,
      command: :none,
      target_number: nil,
      amount: 0
    ]
  end

  defmodule Player do
    @moduledoc "Port of `GlobalCombat.Core/Player.cs`."
    defstruct [
      :number,
      :account_id,
      :name,
      done: false,
      areas: 0,
      armies: 0,
      unassigned_armies: 0,
      place: 0,
      score: 0.0,
      score_expected: 0.0,
      rating: 1200,
      rating_change: 0
    ]
  end

  defstruct [
    :map_name,
    :rng,
    turn: 1,
    is_non_random: false,
    reverse_attack_order: false,
    minimum_armies: 0,
    is_training: false,
    ended: false,
    areas: %{},
    players: %{}
  ]

  # --- lookups & ordered enumeration -----------------------------------
  #
  # Areas/players are stored in maps keyed by number for O(1) access, but
  # Erlang maps only guarantee key-sorted enumeration up to 32 entries (the
  # "elements" map has 38 areas) — so anywhere original List<Area>/List<Player>
  # order matters (attack-sort tie-breaking, elimination-order sequencing;
  # see differential-harness skill "attack-resolution order... stable sort...
  # ties broken by original area order"), we explicitly re-sort by number
  # rather than trust map enumeration order.

  def area!(game, number), do: Map.fetch!(game.areas, number)
  def player!(game, number), do: Map.fetch!(game.players, number)

  defp put_area(game, %Area{number: n} = area), do: %{game | areas: Map.put(game.areas, n, area)}
  defp update_area(game, number, fun), do: put_area(game, fun.(area!(game, number)))

  defp put_player(game, %Player{number: n} = player),
    do: %{game | players: Map.put(game.players, n, player)}

  defp update_player(game, number, fun), do: put_player(game, fun.(player!(game, number)))

  def areas_in_order(game),
    do: game.areas |> Map.keys() |> Enum.sort() |> Enum.map(&Map.fetch!(game.areas, &1))

  def players_in_order(game),
    do: game.players |> Map.keys() |> Enum.sort() |> Enum.map(&Map.fetch!(game.players, &1))

  def current_players(game), do: map_size(game.players)

  # --- ownership (Area.cs: IsOwnedBy/SameOwnerAs, Player.cs: SameAs) ----
  # Value comparison by Number, not reference identity — Elixir has no
  # reference identity to accidentally rely on in the first place, but the
  # nil-owner case ("two unowned areas count as sharing one owner") still
  # needs porting explicitly.

  def owned_by?(%Area{owner_number: nil}, nil), do: true
  def owned_by?(%Area{owner_number: nil}, _player_number), do: false
  def owned_by?(%Area{owner_number: o}, player_number), do: o == player_number

  def same_owner?(%Area{} = a, %Area{} = b), do: owned_by?(a, b.owner_number)

  def total_armies(%Area{armies: armies, assigned_armies: assigned}), do: armies + assigned
  def eliminated?(%Player{place: place}), do: place > 0

  # --- order setters (Game.cs: SetAssigned/SetTransfer/SetAttack) ------

  @doc "Port of `Game.SetAssigned`."
  def set_assigned(game, area_number, amount) do
    area = area!(game, area_number)
    owner = player!(game, area.owner_number)
    amount = min(amount, owner.unassigned_armies)

    if amount > 0 do
      game =
        game
        |> update_player(owner.number, &%{&1 | unassigned_armies: &1.unassigned_armies - amount})
        |> update_area(area_number, &%{&1 | assigned_armies: &1.assigned_armies + amount})

      {amount, game}
    else
      {amount, game}
    end
  end

  @doc "Port of `Game.SetTransfer`."
  def set_transfer(game, source_number, target_number, amount) do
    source = area!(game, source_number)
    target = area!(game, target_number)

    if same_owner?(source, target) and
         MapInfo.links_to?(game.map_name, source_number, target_number) do
      amount = min(amount, total_armies(source) - 1)

      if amount >= 0 do
        game =
          update_area(game, source_number, fn a ->
            %{a | amount: amount, command: :transfer, target_number: target_number}
          end)

        {amount, game}
      else
        {amount, game}
      end
    else
      {0, game}
    end
  end

  @doc "Port of `Game.SetAttack`."
  def set_attack(game, source_number, target_number, amount) do
    source = area!(game, source_number)
    target = area!(game, target_number)

    if not same_owner?(source, target) and
         MapInfo.links_to?(game.map_name, source_number, target_number) do
      amount = min(amount, total_armies(source) - 1)

      if amount >= 0 do
        game =
          update_area(game, source_number, fn a ->
            %{a | amount: amount, command: :attack, target_number: target_number}
          end)

        {amount, game}
      else
        {amount, game}
      end
    else
      {0, game}
    end
  end

  # --- turn resolution (Game.cs: RunTurn and everything it calls) ------

  @doc "Port of `Game.RunTurn`. No-op once the game has ended, matching the original's early return."
  def run_turn(%__MODULE__{ended: true} = game), do: game

  def run_turn(%__MODULE__{} = game) do
    game
    |> Map.update!(:turn, &(&1 + 1))
    |> reset_done_flags()
    |> assign_armies()
    |> do_transfers()
    |> do_attacks()
    |> clear_commands()
    |> resolve_reinforcements_and_eliminations()
  end

  @doc "Port of `Game.ResetDoneFlags`. AccountId 1 is the reserved \"Computer\" convention — always treated as done, never waited on."
  def reset_done_flags(game) do
    Enum.reduce(players_in_order(game), game, fn player, game ->
      done = player.account_id == 1 or eliminated?(player)
      update_player(game, player.number, &%{&1 | done: done})
    end)
  end

  defp assign_armies(game) do
    Enum.reduce(areas_in_order(game), game, fn area, game ->
      update_area(
        game,
        area.number,
        &%{&1 | armies: &1.armies + &1.assigned_armies, assigned_armies: 0}
      )
    end)
  end

  defp do_transfers(game) do
    Enum.reduce(areas_in_order(game), game, fn area, game ->
      if area.command == :transfer, do: do_transfer(game, area.number), else: game
    end)
  end

  @doc "Port of `Game.DoTransfer`."
  def do_transfer(game, area_number) do
    area = area!(game, area_number)

    game
    |> update_area(area.target_number, &%{&1 | armies: &1.armies + area.amount})
    |> update_area(area_number, &%{&1 | armies: &1.armies - area.amount})
  end

  # Stable sort by Amount (descending, or ascending under ReverseAttackOrder),
  # ties broken by original area-number order — see differential-harness
  # skill: LINQ's `orderby` is a stable sort, so `Enum.sort_by/3` here (also
  # stable) needs its *input* pre-sorted by number for the tie-break to match,
  # not just the sort key.
  defp do_attacks(game) do
    order = if game.reverse_attack_order, do: :asc, else: :desc

    sorted =
      areas_in_order(game)
      |> Enum.sort_by(& &1.amount, order)

    Enum.reduce(sorted, game, fn area, game ->
      # Re-fetch: an earlier attack in this same pass may have overwritten
      # this area's Command (see do_attack/2's defender-command-cancel).
      current = area!(game, area.number)
      if current.command == :attack, do: do_attack(game, area.number), else: game
    end)
  end

  @doc "Port of `Game.DoAttack`. Returns the updated game (the original's narrated message string is not ported — see moduledoc)."
  def do_attack(game, attacker_number) do
    attacker = area!(game, attacker_number)
    defender = area!(game, attacker.target_number)

    if same_owner?(attacker, defender) do
      game
    else
      # Game.cs only clamps (and only *possibly* early-returns) when Amount actually exceeds
      # Armies - 1. If Amount is already <= Armies - 1 — including Amount == 0 — the code falls
      # through unchanged: the attack-roll loop then runs zero times (contributing no damage) but
      # the *defend*-roll loop still runs its full `defender.Armies` draws regardless, since
      # nothing gates it on the attacker's amount. A "no-op" order (Amount 0) is not RNG-free —
      # skipping its draws here desyncs every attack processed after it in the same pass. Only
      # verifiable by tracing the oracle's actual per-roll draws turn-by-turn (see harness
      # divergence writeup) — the earlier `if amount <= 0` short-circuit here looked equivalent
      # but wasn't.
      needs_clamp = attacker.amount > attacker.armies - 1
      amount = if needs_clamp, do: attacker.armies - 1, else: attacker.amount

      if needs_clamp and amount <= 0 do
        game
      else
        # `DotnetRandom.next(rng, min, max)` is exclusive of `max`, matching `Random.Next(int,
        # int)` — `Rng.Next(1, 10 + 1) <= 6` in Game.cs is `next(rng, 1, 11)` here, not
        # `next(rng, 1, 10)`; same for the defend roll's `Next(1, 4 + 1)`.
        {attack_damage, game} = roll_damage(game, game.is_non_random, amount, 0.6, 1, 11, 6)
        attack_damage = min(attack_damage, defender.armies)

        {defend_damage, game} =
          roll_damage(game, game.is_non_random, defender.armies, 0.75, 1, 5, 3)

        defend_damage = min(defend_damage, amount)

        if attack_damage >= defender.armies and defend_damage < amount do
          # Attacker wins: takes the area. Defender's own queued command is
          # cancelled (Game.cs: `defender.Command = Command.None`) since it
          # no longer belongs to that player when the sorted attack pass
          # reaches it, if it hasn't already.
          game
          |> update_area(attacker_number, &%{&1 | armies: &1.armies - amount})
          |> update_area(defender.number, fn d ->
            %{
              d
              | armies: amount - defend_damage,
                owner_number: attacker.owner_number,
                command: :none
            }
          end)
          |> update_player(attacker.owner_number, &%{&1 | areas: &1.areas + 1})
          |> update_player(defender.owner_number, &%{&1 | areas: &1.areas - 1})
        else
          game
          |> update_area(defender.number, &%{&1 | armies: &1.armies - attack_damage})
          |> update_area(attacker_number, &%{&1 | armies: &1.armies - defend_damage})
        end
      end
    end
  end

  # `IsNonRandom`: fixed-percentage damage, no RNG draw at all (not even one
  # gated behind the flag) — see differential-harness skill: only the
  # combat roll is gated by this flag, nothing else is.
  defp roll_damage(game, true, amount, fraction, _lo, _hi, _threshold),
    do: {trunc(amount * fraction), game}

  defp roll_damage(game, false, amount, _fraction, lo, hi, threshold) do
    {hits, rng} = count_hits(game.rng, amount, lo, hi, threshold)
    {hits, %{game | rng: rng}}
  end

  defp count_hits(rng, n, _lo, _hi, _threshold) when n <= 0, do: {0, rng}

  defp count_hits(rng, n, lo, hi, threshold) do
    Enum.reduce(1..n, {0, rng}, fn _, {hits, rng} ->
      {roll, rng} = DotnetRandom.next(rng, lo, hi)
      if roll <= threshold, do: {hits + 1, rng}, else: {hits, rng}
    end)
  end

  defp clear_commands(game) do
    Enum.reduce(areas_in_order(game), game, fn area, game ->
      update_area(game, area.number, &%{&1 | amount: 0, command: :none, target_number: nil})
    end)
  end

  defp resolve_reinforcements_and_eliminations(game) do
    {game, alive_players} =
      Enum.reduce(players_in_order(game), {game, 0}, fn player, {game, alive_players} ->
        player = player!(game, player.number)

        cond do
          eliminated?(player) ->
            {game, alive_players}

          player.areas == 0 ->
            {eliminate_player(game, player.number), alive_players}

          true ->
            {reinforce(game, player.number), alive_players + 1}
        end
      end)

    if alive_players <= 1, do: end_game(game), else: game
  end

  defp reinforce(game, player_number) do
    player = player!(game, player_number)
    new_armies = div(player.areas, 2) + region_bonus(game, player_number)
    new_armies = max(new_armies, game.minimum_armies)

    total_armies =
      areas_in_order(game)
      |> Enum.filter(&owned_by?(&1, player_number))
      |> Enum.reduce(0, &(&2 + &1.armies))

    update_player(game, player_number, fn p ->
      unassigned = p.unassigned_armies + new_armies
      %{p | unassigned_armies: unassigned, armies: total_armies + unassigned}
    end)
  end

  defp region_bonus(game, player_number) do
    MapInfo.regions(game.map_name)
    |> Enum.filter(fn {region_number, _name, num_areas, _bonus} ->
      owned =
        Enum.count(game.areas, fn {_number, area} ->
          owned_by?(area, player_number) and area_region(game, area.number) == region_number
        end)

      owned == num_areas
    end)
    |> Enum.reduce(0, fn {_number, _name, _num_areas, bonus}, acc -> acc + bonus end)
  end

  defp area_region(game, area_number) do
    {_number, _name, region, _links} = MapInfo.area(game.map_name, area_number)
    region
  end

  @doc "Port of `Game.EliminatePlayer` (only the RunTurn-reachable path — `loser.IsEliminated` is always false here, RunTurn only calls this on non-eliminated players)."
  def eliminate_player(game, player_number) do
    place = players_in_order(game) |> Enum.count(&(not eliminated?(&1)))

    game =
      update_player(game, player_number, fn p ->
        %{p | areas: 0, armies: 0, unassigned_armies: 0, place: place, done: true}
      end)

    if place <= 2, do: end_game(game), else: game
  end

  @doc "Port of `Game.End`. A no-op once already ended, matching the original's guard (so a mid-loop early end from `eliminate_player/2` doesn't get recomputed by the trailing alive_players<=1 check)."
  def end_game(%__MODULE__{ended: true} = game), do: game

  def end_game(%__MODULE__{} = game) do
    winner = players_in_order(game) |> Enum.find(&(&1.place <= 1))
    game = if winner, do: update_player(game, winner.number, &%{&1 | place: 1}), else: game

    game =
      if game.is_training do
        game
      else
        Enum.reduce(players_in_order(game), game, fn player, game ->
          score_expected = round_half_even(get_score_expected(game, player.number) * 100) / 100
          score = round_half_even(gen_score(game, player.place) * 100) / 100

          update_player(game, player.number, fn p ->
            rating_change = trunc(round_half_even((score - score_expected) * 150))
            %{p | score_expected: score_expected, score: score, rating_change: rating_change}
          end)
        end)
      end

    %{game | ended: true}
  end

  @doc "Port of `Game.GenScoreExpected` — note the 1500f divisor is a 32-bit float in the original, emulated here via `to_float32/1` since it measurably changes the result's low bits."
  def gen_score_expected(player_rating, opponent_rating) do
    exponent = to_float32((opponent_rating - player_rating) / 1500.0)
    1 / (:math.pow(10, exponent) + 1)
  end

  @doc "Port of `Game.GetScoreExpected`."
  def get_score_expected(game, player_number) do
    player = player!(game, player_number)

    total =
      players_in_order(game)
      |> Enum.filter(&(&1.number != player_number))
      |> Enum.reduce(0.0, fn other, acc ->
        acc + gen_score_expected(player.rating, other.rating)
      end)

    total / (current_players(game) - 1)
  end

  @doc "Port of `Game.GenScore`."
  def gen_score(game, place) do
    n = current_players(game)
    1.0 / (n - 1) * (n - place)
  end

  # Emulates C#'s implicit int -> float32 -> (float32 / float32) conversion
  # chain for `(opponentRating - playerRating) / 1500f`: round the true
  # double-precision quotient to the nearest float32-representable value,
  # then widen back — verified against real `dotnet run` output.
  defp to_float32(x) when is_float(x) do
    <<x32::float-32>> = <<x::float-32>>
    x32
  end

  # Emulates C#'s `Math.Round(double)`, which defaults to round-half-to-even
  # ("banker's rounding") — Elixir's `round/1` and `Float.round/2` both round
  # half away from zero instead. Verified against real `dotnet run` output
  # across tie and non-tie cases (see GameTest).
  def round_half_even(x) when is_float(x) do
    floor_val = Float.floor(x)
    diff = x - floor_val

    cond do
      diff < 0.5 -> floor_val
      diff > 0.5 -> floor_val + 1.0
      rem(trunc(floor_val), 2) == 0 -> floor_val
      true -> floor_val + 1.0
    end
  end
end
