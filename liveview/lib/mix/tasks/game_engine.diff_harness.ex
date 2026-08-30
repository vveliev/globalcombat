defmodule Mix.Tasks.GameEngine.DiffHarness do
  @moduledoc """
  GIF-28: the differential harness. Runs N turns of a game through both the
  .NET oracle (`GlobalCombat.GrpcHost`) and the Elixir port
  (`GlobalCombat.Engine`), from identical starting state, identical seeds,
  and identical (oracle-decided) orders each turn, and reports any
  divergence in AI order selection or turn-resolution state. Requires no
  Ecto/database - same as `game_engine.resolve_turn` (GIF-38).

      GRPC_HOST=localhost GRPC_PORT=5251 mix game_engine.diff_harness --turns 50 --seed 42

  Options:
    --turns                number of turns to run (default 50)
    --seed                 base seed for the run (default 1)
    --players              comma-separated player names (default Alice,Bob,Carol)
    --map                  Original | Elements (default Original)
    --minimum-armies       Game.MinimumArmies (default 3)
    --games                number of independent games to run this harness over (default 1)
    --non-random           exercise IsNonRandom (fixed-percentage, no-RNG) combat instead of dice rolls
    --reverse-attack-order exercise ReverseAttackOrder (smallest-first instead of largest-first)
    --fogged               exercise IsFogged (fog-of-war). Confirmed display-only in the .NET
                            oracle (Game.cs's GetStatus appends an <img> tag, nothing else reads
                            it) and unimplemented in the Elixir port for the same reason - passing
                            it through is expected to produce identical diffed state to --fogged
                            omitted, which is itself the check.

  Exits non-zero if any turn, across any game, diverged.
  """
  use Mix.Task

  alias GlobalCombat.Engine.Harness
  alias GlobalCombat.Engine.Harness.TurnReport

  @shortdoc "Run the .NET-vs-Elixir differential harness for N turns"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:gun)
    {:ok, _} = Application.ensure_all_started(:grpc)

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          turns: :integer,
          seed: :integer,
          players: :string,
          map: :string,
          minimum_armies: :integer,
          games: :integer,
          non_random: :boolean,
          reverse_attack_order: :boolean,
          fogged: :boolean
        ]
      )

    turns = Keyword.get(opts, :turns, 50)
    base_seed = Keyword.get(opts, :seed, 1)
    games = Keyword.get(opts, :games, 1)
    is_non_random = Keyword.get(opts, :non_random, false)
    reverse_attack_order = Keyword.get(opts, :reverse_attack_order, false)
    is_fogged = Keyword.get(opts, :fogged, false)

    player_names =
      opts
      |> Keyword.get(:players, "Alice,Bob,Carol")
      |> String.split(",", trim: true)

    map_name = opts |> Keyword.get(:map, "Original") |> String.to_atom()
    minimum_armies = Keyword.get(opts, :minimum_armies, 3)

    host = System.get_env("GRPC_HOST", "localhost")
    port = System.get_env("GRPC_PORT", "5251") |> String.to_integer()

    IO.puts("Connecting to #{host}:#{port} (plaintext h2c)...")
    {:ok, channel} = GRPC.Stub.connect("#{host}:#{port}")

    IO.puts(
      "Running #{games} game(s) x #{turns} turns each (map=#{map_name}, players=#{Enum.join(player_names, "/")}, " <>
        "base seed=#{base_seed}, non_random=#{is_non_random}, reverse_attack_order=#{reverse_attack_order}, " <>
        "fogged=#{is_fogged})\n"
    )

    all_reports =
      for game_index <- 1..games do
        game_seed = base_seed + game_index

        {reports, _final_oracle_game} =
          Harness.run(channel,
            map_name: map_name,
            player_names: player_names,
            turns: turns,
            seed: game_seed,
            minimum_armies: minimum_armies,
            is_non_random: is_non_random,
            reverse_attack_order: reverse_attack_order,
            is_fogged: is_fogged,
            on_turn: &print_turn(game_index, &1)
          )

        reports
      end
      |> List.flatten()

    GRPC.Stub.disconnect(channel)

    total_turns = length(all_reports)
    diverged = Enum.reject(all_reports, &TurnReport.clean?/1)

    IO.puts("\n#{String.duplicate("=", 60)}")

    if diverged == [] do
      IO.puts(
        "PASS: #{total_turns} turns run across #{games} game(s), zero state divergence between .NET oracle and Elixir port."
      )
    else
      IO.puts(
        "FAIL: #{length(diverged)}/#{total_turns} turns diverged. See details above for each flagged turn."
      )

      exit({:shutdown, 1})
    end
  end

  defp print_turn(game_index, %TurnReport{} = report) do
    status = if TurnReport.clean?(report), do: "OK", else: "*** DIVERGED ***"
    IO.puts("game ##{game_index} turn #{report.turn}: #{status}")

    for d <- report.ai_divergences, do: IO.puts("    AI decision diff: #{inspect(d)}")
    for d <- report.resolve_divergences, do: IO.puts("    Resolve diff: #{inspect(d)}")

    for m <- report.army_total_mismatches,
        do: IO.puts("    Army total mismatch: #{inspect(m)}")
  end
end
