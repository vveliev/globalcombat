defmodule GlobalCombat.Tourneys.Bracket do
  @moduledoc """
  Pure port of `Web/Models/Tourney.cs`'s `BuildRounds` and `Web/Models/TourneyRound.cs`. No
  I/O, no database -- takes a tourney's shape and returns the bracket structure of rounds, so
  the round-progression math can be unit tested directly against the original algorithm instead
  of only indirectly through database-backed integration tests.
  """

  defmodule Round do
    @moduledoc "Port of `Web/Models/TourneyRound.cs` (`Tourney`/`Games` back-references dropped -- callers already have the round list)."
    defstruct [
      :number,
      :start_game,
      :game_count,
      :game_size,
      winners_of_round: 0,
      losers_of_round: 0
    ]
  end

  @doc """
  Port of `Tourney.BuildRounds`. `initial_games` is assumed already validated (power of two,
  >= 2, etc.) by the caller -- `BuildRounds` itself does no such validation either; see
  `GlobalCombat.Tourneys.validate_shape/1` for where that validation actually lives (ported
  from `Tourney.CreateTournament`).

  Returns `%{winner_bracket: [Round.t()], loser_bracket: [Round.t()], final_round: Round.t() | nil}`.
  """
  def build_rounds(%{
        initial_games: initial_games,
        game_size: game_size,
        winners: winners,
        losers: losers,
        double_elimination: double_elimination?
      }) do
    round1 = %Round{number: 1, start_game: 1, game_count: initial_games, game_size: game_size}

    {winner_bracket, current_round, start_game} =
      build_winner_bracket_rounds([round1], 1, 1 + initial_games, initial_games, winners)

    if double_elimination? do
      winner_round = 1
      current_round = current_round + 1
      previous_game_count = div(initial_games, 2)

      first_loser_round = %Round{
        number: current_round,
        start_game: start_game,
        game_count: previous_game_count,
        game_size: losers * 2,
        losers_of_round: winner_round
      }

      start_game = start_game + previous_game_count
      winner_round_game_count = div(initial_games, 2)

      {loser_bracket, current_round, start_game, winner_round} =
        build_loser_bracket_rounds(
          [first_loser_round],
          current_round,
          start_game,
          previous_game_count,
          winner_round,
          winner_round_game_count,
          winners
        )

      winner_round = winner_round + 1
      current_round = current_round + 1

      last_loser_round = %Round{
        number: current_round,
        start_game: start_game,
        game_count: 1,
        game_size: winners * 2,
        winners_of_round: current_round - 1,
        losers_of_round: winner_round
      }

      start_game = start_game + 1
      current_round = current_round + 1

      final_round = %Round{
        number: current_round,
        start_game: start_game,
        game_count: 1,
        game_size: winners * 2,
        winners_of_round: winner_round,
        losers_of_round: -(current_round - 1)
      }

      %{
        winner_bracket: winner_bracket,
        loser_bracket: loser_bracket ++ [last_loser_round],
        final_round: final_round
      }
    else
      %{winner_bracket: winner_bracket, loser_bracket: [], final_round: nil}
    end
  end

  defp build_winner_bracket_rounds(
         rounds,
         current_round,
         start_game,
         previous_game_count,
         winners
       ) do
    if previous_game_count > 1 do
      current_round = current_round + 1
      previous_game_count = div(previous_game_count, 2)

      round = %Round{
        number: current_round,
        start_game: start_game,
        game_count: previous_game_count,
        game_size: winners * 2,
        winners_of_round: current_round - 1
      }

      build_winner_bracket_rounds(
        rounds ++ [round],
        current_round,
        start_game + previous_game_count,
        previous_game_count,
        winners
      )
    else
      {rounds, current_round, start_game}
    end
  end

  # Port of the `while (previousGameCount > 1)` loop inside `BuildRounds`'s double-elimination
  # branch. Faithful to the original's asymmetric mutation: `previous_game_count` is only ever
  # halved on the `add_flag? == false` path -- on the `true` path the *next* loser-bracket round
  # reuses the same game count while `winner_round_game_count` (a separate counter tracking how
  # fast the winner bracket itself is shrinking) is what halves instead. Collapsing these into
  # one counter would silently change which rounds pick up a fresh wave of winner-bracket losers.
  defp build_loser_bracket_rounds(
         rounds,
         current_round,
         start_game,
         previous_game_count,
         winner_round,
         winner_round_game_count,
         winners
       ) do
    if previous_game_count > 1 do
      count = div(previous_game_count, 2)

      add_flag? =
        cond do
          winner_round_game_count == 2 and count > 1 -> false
          winner_round_game_count < 2 -> false
          true -> true
        end

      current_round = current_round + 1

      if add_flag? do
        winner_round = winner_round + 1
        winner_round_game_count = div(winner_round_game_count, 2)

        round = %Round{
          number: current_round,
          start_game: start_game,
          game_count: previous_game_count,
          game_size: winners * 2,
          winners_of_round: current_round - 1,
          losers_of_round: winner_round
        }

        build_loser_bracket_rounds(
          rounds ++ [round],
          current_round,
          start_game + previous_game_count,
          previous_game_count,
          winner_round,
          winner_round_game_count,
          winners
        )
      else
        previous_game_count = div(previous_game_count, 2)

        round = %Round{
          number: current_round,
          start_game: start_game,
          game_count: previous_game_count,
          game_size: winners * 2,
          winners_of_round: current_round - 1
        }

        build_loser_bracket_rounds(
          rounds ++ [round],
          current_round,
          start_game + previous_game_count,
          previous_game_count,
          winner_round,
          winner_round_game_count,
          winners
        )
      end
    else
      {rounds, current_round, start_game, winner_round}
    end
  end

  @doc """
  Port of the `winnerRound`/`loserRound` lookup inline in `Tourney.CreateTourneyGame`: given one
  round and the full flattened list of every round in the bracket (winner + loser + final),
  returns `{winner_round_number, loser_round_number}` -- the round numbers this round's winners
  and losers should advance into (`0` meaning "nowhere", i.e. eliminated or tournament-ending).
  """
  def advancement_targets(%Round{number: number}, all_rounds) do
    winner_round =
      Enum.find(all_rounds, fn r ->
        r.winners_of_round == number or r.losers_of_round == -number
      end)

    loser_round = Enum.find(all_rounds, fn r -> r.losers_of_round == number end)

    {(winner_round && winner_round.number) || 0, (loser_round && loser_round.number) || 0}
  end
end
