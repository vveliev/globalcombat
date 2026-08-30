# GIF-72: broad differential-harness sweep across game modes.
#
# GIF-28 built the harness (`GlobalCombat.Engine.Harness`, driven by
# `mix game_engine.diff_harness`) and ran it once: 60 games / 5,069 turns, all
# default map/player-count/mode. This script re-runs the same harness (same
# oracle calls, same diff logic - it just drives `Harness.run/2` directly
# instead of through the single-scenario mix task) across a deliberately
# varied matrix: both maps, player counts 2-6, fog-of-war on/off,
# IsNonRandom on/off, ReverseAttackOrder on/off (the Largest/Smallest
# attack-order tie-break), and edge-case MinimumArmies values - plus a
# 2-player/400-turn "elo-endgame" batch specifically to force games to
# actually finish (`Game.cs`'s End() path, which is where per-player Rating/
# Score/ScoreExpected/RatingChange get computed - see Game.cs:612-658).
#
# Run (oracle must already be listening, e.g. `dotnet
# GlobalCombat.GrpcHost/bin/Release/net10.0/GlobalCombat.GrpcHost.dll` from
# the repo root):
#
#     GRPC_HOST=localhost GRPC_PORT=5251 mix run scripts/gif72_sweep.exs
#
# Set GIF72_SMOKE=1 for a fast structural check (1 game, 8 turns per
# scenario) instead of the full sweep. Exits non-zero if any turn, in any
# scenario, diverged.

Application.ensure_all_started(:gun)
Application.ensure_all_started(:grpc)

alias GlobalCombat.Engine.Harness
alias GlobalCombat.Engine.Harness.TurnReport

host = System.get_env("GRPC_HOST", "localhost")
port = System.get_env("GRPC_PORT", "5251") |> String.to_integer()
smoke? = System.get_env("GIF72_SMOKE") == "1"

IO.puts("Connecting to #{host}:#{port} (plaintext h2c)...")
{:ok, channel} = GRPC.Stub.connect("#{host}:#{port}")

player_sets = %{
  2 => ["Alice", "Bob"],
  3 => ["Alice", "Bob", "Carol"],
  4 => ["Alice", "Bob", "Carol", "Dave"],
  5 => ["Alice", "Bob", "Carol", "Dave", "Eve"],
  6 => ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"]
}

# The full mode matrix: map x player count x fog x combat-RNG mode x
# attack-order tie-break, at the default MinimumArmies.
main_matrix =
  for map <- [:Original, :Elements],
      player_count <- [2, 3, 4, 5, 6],
      fogged <- [false, true],
      non_random <- [false, true],
      reverse <- [false, true] do
    %{
      label: "main",
      map: map,
      players: player_sets[player_count],
      fogged: fogged,
      non_random: non_random,
      reverse: reverse,
      minimum_armies: 3,
      games: 3,
      turns: 120
    }
  end

# MinimumArmies edge cases (1 = smallest legal reinforcement; 10 = unusually
# high) crossed with map/RNG-mode/tie-break, at a small and a large player
# count.
edge_min_armies =
  for minimum_armies <- [1, 10],
      map <- [:Original, :Elements],
      non_random <- [false, true],
      reverse <- [false, true],
      player_count <- [3, 6] do
    %{
      label: "edge-min-armies",
      map: map,
      players: player_sets[player_count],
      fogged: false,
      non_random: non_random,
      reverse: reverse,
      minimum_armies: minimum_armies,
      games: 2,
      turns: 100
    }
  end

# 2-player games run long enough that most of them actually finish, to
# exercise Game.cs's End()/Elo-scoring path (Rating/Score/ScoreExpected/
# RatingChange) on both sides, not just mid-game turn resolution.
elo_endgame =
  for map <- [:Original, :Elements],
      non_random <- [false, true],
      reverse <- [false, true] do
    %{
      label: "elo-endgame",
      map: map,
      players: player_sets[2],
      fogged: false,
      non_random: non_random,
      reverse: reverse,
      minimum_armies: 3,
      games: 3,
      turns: 400
    }
  end

scenarios = main_matrix ++ edge_min_armies ++ elo_endgame

scenarios =
  if smoke? do
    Enum.map(scenarios, &%{&1 | games: 1, turns: 8})
  else
    scenarios
  end

base_seed = System.get_env("GIF72_BASE_SEED", "1") |> String.to_integer()

indexed = Enum.with_index(scenarios)
scenario_count = length(scenarios)

# `Harness.run/2` derives its gRPC-level Think/Resolve seeds as
# `game_seed * 1_000_000 + turn_index * 2` (see harness.ex) and encodes them
# as protobuf int32 - game_seed must stay well under ~2_000 or that
# multiplication overflows int32 before it ever reaches the network. Spacing
# scenarios 5 apart (max 3 games each) keeps every game_seed in this sweep
# under ~600.
results =
  for {scenario, index} <- indexed do
    scenario_base_seed = base_seed + index * 5

    scenario_reports =
      for game_index <- 1..scenario.games do
        game_seed = scenario_base_seed + game_index

        {reports, _final_oracle_game} =
          Harness.run(channel,
            map_name: scenario.map,
            player_names: scenario.players,
            turns: scenario.turns,
            seed: game_seed,
            minimum_armies: scenario.minimum_armies,
            is_non_random: scenario.non_random,
            is_fogged: scenario.fogged,
            reverse_attack_order: scenario.reverse
          )

        reports
      end
      |> List.flatten()

    diverged = Enum.reject(scenario_reports, &TurnReport.clean?/1)
    status = if diverged == [], do: "OK", else: "*** DIVERGED (#{length(diverged)}) ***"

    IO.puts(
      "[#{index + 1}/#{scenario_count}] #{scenario.label} map=#{scenario.map} " <>
        "players=#{length(scenario.players)} fogged=#{scenario.fogged} " <>
        "non_random=#{scenario.non_random} reverse=#{scenario.reverse} " <>
        "min_armies=#{scenario.minimum_armies} games=#{scenario.games} turns=#{scenario.turns} " <>
        "seed_base=#{scenario_base_seed} -> #{length(scenario_reports)} turns run, #{status}"
    )

    for d <- diverged do
      IO.puts(
        "    seed_base=#{scenario_base_seed} turn=#{d.turn} ai=#{inspect(d.ai_divergences)} " <>
          "resolve=#{inspect(d.resolve_divergences)} army=#{inspect(d.army_total_mismatches)}"
      )
    end

    {scenario, scenario_base_seed, scenario_reports, diverged}
  end

GRPC.Stub.disconnect(channel)

total_turns = results |> Enum.map(fn {_, _, reports, _} -> length(reports) end) |> Enum.sum()
total_games = results |> Enum.map(fn {scenario, _, _, _} -> scenario.games end) |> Enum.sum()
all_diverged = results |> Enum.flat_map(fn {_, _, _, diverged} -> diverged end)

IO.puts("\n" <> String.duplicate("=", 70))

IO.puts(
  "GIF-72 sweep complete: #{scenario_count} scenarios, #{total_games} games, #{total_turns} turns"
)

if all_diverged == [] do
  IO.puts(
    "PASS: #{total_turns} turns across #{total_games} games / #{scenario_count} scenarios, " <>
      "zero state divergence between .NET oracle and Elixir port."
  )
else
  IO.puts("FAIL: #{length(all_diverged)} diverged turn(s) across the sweep. See details above.")
  System.halt(1)
end
