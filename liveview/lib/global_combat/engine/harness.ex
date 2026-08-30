defmodule GlobalCombat.Engine.Harness do
  @moduledoc """
  The differential harness for GIF-28: feeds identical game state, identical
  seeds, and identical orders to the .NET oracle (`GlobalCombat.GrpcHost`,
  ADR-0001) and the Elixir port (`GlobalCombat.Engine`), and diffs the
  resulting state turn by turn. See the `differential-harness` skill this
  follows.

  Per turn, against a single shared starting `Game`:

    1. Oracle `Think` decides AI orders from a seed — this is the fixture,
       recaptured from the oracle every run, never hand-edited (`Think`'s
       output is treated as ground truth for what orders to feed both
       engines, not as something to independently second-guess).
    2. The Elixir port *also* runs its own `RandomAi.think/1` from the same
       seed and starting state, and its decisions are diffed against the
       oracle's — this is the "RNG must be seeded identically or the diff is
       noise" check the issue calls out by name, isolated from turn
       resolution so a divergence here points at `RandomAi`, not `Game`.
    3. The oracle's orders (not the Elixir port's, even if they matched) are
       applied to both engines' `ResolveTurn`/`run_turn`, seeded identically,
       and the resulting state is diffed field by field.
    4. Each player's army total is independently recomputed from owned
       areas on both sides and checked against both engines' own reported
       total — catches stale-increment/double-count bugs that agreement
       between the two engines' own bookkeeping alone can't.

  A turn's starting state for turn N+1 is the *oracle's* result for turn N
  (not the Elixir port's) — divergences don't compound into meaningless
  noise on later turns; every turn is diffed from a known-good oracle state.

  Once the oracle reports `Ended: true`, the run stops for that game instead
  of requesting further turns: `RunTurn` no-ops entirely once ended (its
  first line is `if (Ended) return;`), so every subsequent turn would
  exercise nothing new — and calling `Think` against an ended game is worse
  than pointless, since `RunTurn` never reaches its own "clear commands"
  step to reset the `Target` references `Think` just queued. Those pile up,
  unbounded, turn after turn, until they retrigger the AsReference
  serialization crash `ThinkResponse` was redesigned to avoid in the first
  place (see `Contracts.cs`) — this time via `ResolveQueuedTurn`'s own
  response `Game`, discovered by running this harness for enough turns that
  a game actually finished.
  """

  alias GlobalCombat.Engine.{DotnetRandom, Game, RandomAi, Wire}
  alias GlobalCombat.GrpcHost.{GameEngine, NewGameRequest, ResolveQueuedTurnRequest, ThinkRequest}

  defmodule TurnReport do
    @moduledoc false
    defstruct [:turn, :ai_divergences, :resolve_divergences, :army_total_mismatches]

    def clean?(%__MODULE__{} = r),
      do: r.ai_divergences == [] and r.resolve_divergences == [] and r.army_total_mismatches == []
  end

  @doc """
  Runs `turns` turns through both engines starting from a freshly created
  oracle game, returning `{reports, final_oracle_game}`. `reports` is one
  `TurnReport` per turn, in order; check `TurnReport.clean?/1` on each, or
  just look for any non-empty divergence list — the harness does not stop
  early on a divergence, so a full run always reports exactly `turns`
  reports even if some diverged.
  """
  def run(channel, opts) do
    map_name = Keyword.get(opts, :map_name, :Original)
    player_names = Keyword.fetch!(opts, :player_names)
    turns = Keyword.fetch!(opts, :turns)
    base_seed = Keyword.fetch!(opts, :seed)
    minimum_armies = Keyword.get(opts, :minimum_armies, 3)
    reverse_attack_order = Keyword.get(opts, :reverse_attack_order, false)
    is_non_random = Keyword.get(opts, :is_non_random, false)
    is_fogged = Keyword.get(opts, :is_fogged, false)
    on_turn = Keyword.get(opts, :on_turn, fn _report -> :ok end)

    {:ok, new_game_reply} =
      GameEngine.Stub.new_game(channel, %NewGameRequest{
        MapName: map_name,
        PlayerNames: player_names,
        Seed: base_seed,
        IsNonRandom: is_non_random,
        IsFogged: is_fogged,
        ReverseAttackOrder: reverse_attack_order,
        MinimumArmies: minimum_armies
      })

    oracle_game = Map.fetch!(new_game_reply, :Game)
    game_id = Map.fetch!(oracle_game, :Id)

    {reports, final_game} =
      Enum.reduce_while(1..turns, {[], oracle_game}, fn turn_index, {reports, oracle_game} ->
        if Map.fetch!(oracle_game, :Ended) do
          {:halt, {reports, oracle_game}}
        else
          think_seed = base_seed * 1_000_000 + turn_index * 2
          resolve_seed = think_seed + 1

          {report, next_oracle_game} =
            run_one_turn(channel, game_id, oracle_game, think_seed, resolve_seed, turn_index)

          on_turn.(report)
          {:cont, {[report | reports], next_oracle_game}}
        end
      end)

    {Enum.reverse(reports), final_game}
  end

  # `oracle_game` here is only ever this turn's *starting* snapshot, used to build the Elixir
  # port's own copy to operate on locally — the oracle itself is stateful (GameEngineService keeps
  # the real Game server-side, keyed by `game_id`, across Think -> ResolveQueuedTurn) precisely so
  # neither side ever needs to round-trip a mutated Game back to it. See ThinkRequest's doc comment
  # in Contracts.cs for why: a stateless round trip broke SetAssigned's cross-area army-pool
  # debiting via protobuf-net's AsReference not actually sharing Player identity across sibling
  # Areas on deserialize — this design sidesteps that bug rather than working around it.
  defp run_one_turn(channel, game_id, oracle_game, think_seed, resolve_seed, turn_index) do
    starting_elixir_game = Wire.from_wire_game(oracle_game, DotnetRandom.new(think_seed))

    {:ok, think_reply} =
      GameEngine.Stub.think(channel, %ThinkRequest{GameId: game_id, Seed: think_seed})

    oracle_assignments = Map.fetch!(think_reply, :Assignments)
    oracle_orders = Map.fetch!(think_reply, :Orders)

    elixir_thought_game = RandomAi.think(starting_elixir_game)
    ai_divergences = diff_ai_decisions(elixir_thought_game, oracle_assignments, oracle_orders)

    {:ok, resolve_reply} =
      GameEngine.Stub.resolve_queued_turn(channel, %ResolveQueuedTurnRequest{
        GameId: game_id,
        Seed: resolve_seed
      })

    oracle_resolved_wire = Map.fetch!(resolve_reply, :Game)
    oracle_resolved = Wire.from_wire_game(oracle_resolved_wire, DotnetRandom.new(resolve_seed))

    elixir_resolved =
      starting_elixir_game
      |> Wire.apply_assignments(oracle_assignments)
      |> Wire.apply_orders(oracle_orders)
      |> Map.put(:rng, DotnetRandom.new(resolve_seed))
      |> Game.run_turn()

    resolve_divergences = diff_games(elixir_resolved, oracle_resolved)

    # Skip the recompute cross-check on the exact turn a game ends — see check_army_totals/2's
    # doc for why "Armies == fresh area scan" is not actually an invariant of the oracle on that
    # one turn, by the original algorithm's own design, not a bug in either engine.
    army_total_mismatches =
      if oracle_resolved.ended,
        do: [],
        else: check_army_totals(elixir_resolved, oracle_resolved)

    report = %TurnReport{
      turn: turn_index,
      ai_divergences: ai_divergences,
      resolve_divergences: resolve_divergences,
      army_total_mismatches: army_total_mismatches
    }

    {report, oracle_resolved_wire}
  end

  # AI-decision parity: compare the Elixir port's own Think() decisions against the oracle's,
  # both starting from the identical pre-think state and seed.
  defp diff_ai_decisions(elixir_thought_game, oracle_assignments, oracle_orders) do
    elixir_assignments =
      elixir_thought_game
      |> Game.areas_in_order()
      |> Enum.filter(&(&1.assigned_armies > 0))
      |> Enum.map(&{&1.number, &1.assigned_armies})
      |> Enum.sort()

    oracle_assignments_sorted =
      oracle_assignments
      |> Enum.map(&{Map.fetch!(&1, :AreaNumber), Map.fetch!(&1, :Amount)})
      |> Enum.sort()

    elixir_orders =
      elixir_thought_game
      |> Wire.to_wire_orders()
      |> Enum.map(&order_key/1)

    oracle_orders_keyed = Enum.map(oracle_orders, &order_key/1)

    assignment_diff =
      if elixir_assignments != oracle_assignments_sorted,
        do: [{:assignments, elixir_assignments, oracle_assignments_sorted}],
        else: []

    order_diff =
      if elixir_orders != oracle_orders_keyed,
        do: [{:orders, elixir_orders, oracle_orders_keyed}],
        else: []

    assignment_diff ++ order_diff
  end

  defp order_key(order),
    do:
      {Map.fetch!(order, :SourceAreaNumber), Map.fetch!(order, :TargetAreaNumber),
       Map.fetch!(order, :Command), Map.fetch!(order, :Amount)}

  # Turn-resolution parity: structural diff of the two engines' resulting state, by the stable
  # Number keys both sides already use (see Game.owned_by?/2, Game.same_owner?/2) — never by
  # reference identity, which Elixir has none of to accidentally rely on in the first place.
  defp diff_games(%Game{} = elixir_game, %Game{} = oracle_game) do
    area_diffs =
      for {number, e_area} <- elixir_game.areas,
          o_area = Map.fetch!(oracle_game.areas, number),
          e_area != o_area,
          do: {:area, number, e_area, o_area}

    player_diffs =
      for {number, e_player} <- elixir_game.players,
          o_player = Map.fetch!(oracle_game.players, number),
          e_player != o_player,
          do: {:player, number, e_player, o_player}

    scalar_diffs =
      for {field, e_val, o_val} <- [
            {:turn, elixir_game.turn, oracle_game.turn},
            {:ended, elixir_game.ended, oracle_game.ended}
          ],
          e_val != o_val,
          do: {:scalar, field, e_val, o_val}

    area_diffs ++ player_diffs ++ scalar_diffs
  end

  # differential-harness skill: "for every quantity the reference maintains incrementally, also
  # compute it independently from first principles on both sides" — Player.Armies is maintained
  # incrementally by RunTurn; recompute it from Areas.Armies + UnassignedArmies independently on
  # both engines and compare all four numbers, not just the two engines' own reported totals.
  #
  # NOT called on the turn a game ends (see run_one_turn/6) — found by running this harness deep
  # enough for games to actually finish: Game.cs's reinforcement loop walks Players in Number
  # order, and EliminatePlayer's own `if (loser.Place <= 2) End()` can fire *mid-loop*, off an
  # earlier-numbered player's elimination, before the eventual winner's own iteration runs. End()
  # sets `winner.Place = 1` immediately - so by the time the loop reaches the winner, their own
  # `if (!player.IsEliminated)` guard (Place > 0) is now false, and their reinforcement/army
  # recompute for that turn is skipped entirely. Their reported Armies on the winning turn is
  # thus last turn's value, not a fresh scan of the territory they just conquered - "Armies ==
  # sum(owned Areas.Armies) + UnassignedArmies" is not an invariant of the oracle at that exact
  # turn, by the original algorithm's own timing, not a bug. Confirmed not a port divergence: both
  # engines report the identical (frozen) Armies value for the winner - only this recompute
  # disagreed with both, identically, which is what pointed at the check's assumption rather than
  # either engine.
  defp check_army_totals(%Game{} = elixir_game, %Game{} = oracle_game) do
    for {number, e_player} <- elixir_game.players do
      o_player = Map.fetch!(oracle_game.players, number)

      e_recomputed = recompute_armies(elixir_game, number) + e_player.unassigned_armies
      o_recomputed = recompute_armies(oracle_game, number) + o_player.unassigned_armies

      if e_recomputed != e_player.armies or o_recomputed != o_player.armies or
           e_player.armies != o_player.armies do
        {number, e_player.armies, e_recomputed, o_player.armies, o_recomputed}
      end
    end
    |> Enum.filter(& &1)
  end

  defp recompute_armies(game, player_number) do
    game
    |> Game.areas_in_order()
    |> Enum.filter(&Game.owned_by?(&1, player_number))
    |> Enum.reduce(0, &(&2 + &1.armies))
  end
end
