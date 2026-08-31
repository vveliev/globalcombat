# GIF-109: differential-harness coverage for tournament bracket resolution.
#
# GIF-72/101 documented a structural gap: GlobalCombat.GrpcHost only exposed NewGame/Think/
# ResolveQueuedTurn, so GlobalCombat.Tourneys's bracket logic (ported from Web/Models/Tourney.cs
# in GIF-32) was never diffed against the .NET oracle - only covered by the Elixir port's own
# unit tests (bracket_test.exs et al.). GIF-109 added a TourneyBracket RPC, backed by
# GlobalCombat.Core.TourneyBracket - a pure, DB-free extraction of Tourney.cs's BuildRounds()
# that both Tourney.cs itself (Web/Models/Tourney.cs) and the gRPC oracle now share as one
# implementation. This script is that RPC's differential harness: same style as
# gif72_sweep.exs (a matrix, a diff, a PASS/FAIL summary, non-zero exit on divergence), but for
# bracket shape instead of turn-by-turn combat state.
#
# Unlike gif72_sweep.exs there is no RNG, no turns loop, and no seed - BuildRounds is a pure
# function of (initial_games, game_size, winners, double_elimination), so every scenario is a
# single request/response pair diffed against GlobalCombat.Tourneys.Bracket.build_rounds/1
# computed locally from the same inputs. WinnersOfRoundNumber/LosersOfRoundNumber - the fields
# GlobalCombat.Tourneys.Bracket.advancement_targets/2 derives "which round do winners/losers
# advance to" from - are part of the diffed round shape, so a correct bracket diff already
# covers advancement; there is no separate advancement-only oracle call to make.
#
# Run (oracle must already be listening, e.g. `dotnet
# GlobalCombat.GrpcHost/bin/Release/net10.0/GlobalCombat.GrpcHost.dll` from the repo root):
#
#     GRPC_HOST=localhost GRPC_PORT=5251 mix run scripts/gif109_tourney_sweep.exs
#
# Exits non-zero if any scenario's bracket diverged.

Application.ensure_all_started(:gun)
Application.ensure_all_started(:grpc)

defmodule GIF109.Wire do
  @moduledoc "Converts a wire `GlobalCombat.GrpcHost.TourneyRound`/`TourneyBracket` into `GlobalCombat.Tourneys.Bracket.Round`/plain map, for diffing against the Elixir port's own `Bracket.build_rounds/1`."

  alias GlobalCombat.Tourneys.Bracket.Round

  def from_wire_round(nil), do: nil

  def from_wire_round(r) do
    %Round{
      number: f(r, :Number),
      start_game: f(r, :StartGame),
      game_count: f(r, :GameCount),
      game_size: f(r, :GameSize),
      winners_of_round: f(r, :WinnersOfRoundNumber),
      losers_of_round: f(r, :LosersOfRoundNumber)
    }
  end

  def from_wire_bracket(wire_bracket) do
    %{
      winner_bracket: Enum.map(f(wire_bracket, :WinnerBracket), &from_wire_round/1),
      loser_bracket: Enum.map(f(wire_bracket, :LoserBracket), &from_wire_round/1),
      final_round: from_wire_round(f(wire_bracket, :FinalRound))
    }
  end

  defp f(struct, key), do: Map.fetch!(struct, key)
end

alias GlobalCombat.Tourneys.Bracket
alias GlobalCombat.GrpcHost.{GameEngine, TourneyBracketRequest}

host = System.get_env("GRPC_HOST", "localhost")
port = System.get_env("GRPC_PORT", "5251") |> String.to_integer()

IO.puts("Connecting to #{host}:#{port} (plaintext h2c)...")
{:ok, channel} = GRPC.Stub.connect("#{host}:#{port}")

# Single-elimination: every power-of-two initial_games size the original UI offers (up to 64,
# per Tourney.CreateTournament's validated list), crossed with every game_size/winners split
# that satisfies "winners < game_size" (Tourney.CreateTournament's own validation).
single_elim_matrix =
  for initial_games <- [2, 4, 8, 16, 32, 64],
      game_size <- [2, 3, 4],
      winners <- 1..(game_size - 1) do
    %{
      label: "single-elim",
      initial_games: initial_games,
      game_size: game_size,
      winners: winners,
      double_elimination: false
    }
  end

# Double-elimination: Tourney.CreateTournament caps this at 8 initial games ("A max of 8 initial
# games with double elimination"), so the matrix only covers what production actually allows.
double_elim_matrix =
  for initial_games <- [2, 4, 8],
      game_size <- [2, 3, 4],
      winners <- 1..(game_size - 1) do
    %{
      label: "double-elim",
      initial_games: initial_games,
      game_size: game_size,
      winners: winners,
      double_elimination: true
    }
  end

scenarios = single_elim_matrix ++ double_elim_matrix
scenario_count = length(scenarios)

results =
  for {scenario, index} <- Enum.with_index(scenarios) do
    request = %TourneyBracketRequest{
      InitialGames: scenario.initial_games,
      GameSize: scenario.game_size,
      Winners: scenario.winners,
      IsDoubleElimination: scenario.double_elimination
    }

    {:ok, reply} = GameEngine.Stub.tourney_bracket(channel, request)

    oracle_bracket = reply |> Map.fetch!(:Bracket) |> GIF109.Wire.from_wire_bracket()

    local_bracket =
      Bracket.build_rounds(%{
        initial_games: scenario.initial_games,
        game_size: scenario.game_size,
        winners: scenario.winners,
        losers: scenario.game_size - scenario.winners,
        double_elimination: scenario.double_elimination
      })

    diverged =
      for {field, oracle_val, local_val} <- [
            {:winner_bracket, oracle_bracket.winner_bracket, local_bracket.winner_bracket},
            {:loser_bracket, oracle_bracket.loser_bracket, local_bracket.loser_bracket},
            {:final_round, oracle_bracket.final_round, local_bracket.final_round}
          ],
          oracle_val != local_val,
          do: {field, oracle_val, local_val}

    status = if diverged == [], do: "OK", else: "*** DIVERGED ***"

    IO.puts(
      "[#{index + 1}/#{scenario_count}] #{scenario.label} initial_games=#{scenario.initial_games} " <>
        "game_size=#{scenario.game_size} winners=#{scenario.winners} -> #{status}"
    )

    for {field, oracle_val, local_val} <- diverged do
      IO.puts("    field=#{field} oracle=#{inspect(oracle_val)} elixir=#{inspect(local_val)}")
    end

    {scenario, diverged}
  end

GRPC.Stub.disconnect(channel)

all_diverged = results |> Enum.flat_map(fn {_, diverged} -> diverged end)

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("GIF-109 tourney bracket sweep complete: #{scenario_count} scenarios")

if all_diverged == [] do
  IO.puts(
    "PASS: #{scenario_count} scenarios, zero bracket divergence between .NET oracle and Elixir port."
  )
else
  diverged_scenarios = results |> Enum.count(fn {_, diverged} -> diverged != [] end)
  IO.puts("FAIL: #{diverged_scenarios} scenario(s) diverged. See details above.")
  System.halt(1)
end
