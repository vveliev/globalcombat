defmodule GlobalCombat.TourneysTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.{Games, Tourneys}
  alias GlobalCombat.Tourneys.Tourney

  import GlobalCombat.AccountsFixtures

  defp accounts(count), do: for(_ <- 1..count, do: account_fixture())

  defp tourney_fixture(attrs \\ %{}) do
    {:ok, tourney} =
      %{
        "name" => "Test Cup #{System.unique_integer([:positive])}",
        "initial_games" => 4,
        "game_size" => 2,
        "winners" => 1,
        "double_elimination" => false,
        "auto_start" => true
      }
      |> Map.merge(attrs)
      |> Tourneys.create_tourney()

    tourney
  end

  defp join_all(tourney, players) do
    Enum.reduce(players, {tourney, nil}, fn account, {tourney, _last} ->
      {:ok, outcome} = Tourneys.join_tournament(tourney, account.id)
      {Tourneys.get_tourney!(tourney.id), outcome}
    end)
  end

  defp players_of(tourney_game) do
    tourney_game.game.game_players |> Enum.map(& &1.account_id) |> MapSet.new()
  end

  describe "create_tourney/1 (Tourney.CreateTournament validation)" do
    test "rejects fewer than two initial games" do
      assert {:error, changeset} =
               Tourneys.create_tourney(%{"name" => "x", "initial_games" => 1, "game_size" => 2})

      assert "At least two initial games required" in errors_on(changeset).initial_games
    end

    test "rejects a non-power-of-two initial game count" do
      assert {:error, changeset} =
               Tourneys.create_tourney(%{"name" => "x", "initial_games" => 3, "game_size" => 2})

      assert "Initial games must be a power of two." in errors_on(changeset).initial_games
    end

    test "rejects more than 8 initial games with double elimination" do
      assert {:error, changeset} =
               Tourneys.create_tourney(%{
                 "name" => "x",
                 "initial_games" => 16,
                 "game_size" => 2,
                 "double_elimination" => true
               })

      assert "A max of 8 initial games with double elimination." in errors_on(changeset).double_elimination
    end

    test "rejects winners >= game_size" do
      assert {:error, changeset} =
               Tourneys.create_tourney(%{
                 "name" => "x",
                 "initial_games" => 4,
                 "game_size" => 2,
                 "winners" => 2
               })

      assert "Winners must be less than initial game size." in errors_on(changeset).winners
    end

    test "creates a valid tourney with derived max_players" do
      assert {:ok, tourney} =
               Tourneys.create_tourney(%{
                 "name" => "Cup",
                 "initial_games" => 4,
                 "game_size" => 2,
                 "winners" => 1
               })

      assert tourney.max_players == 8
      assert tourney.status == :new
      assert tourney.create_time
    end
  end

  describe "join_tournament/2 (TourneyController.Join)" do
    test "joining seats a player and reports :joined while seats remain" do
      tourney = tourney_fixture()
      [a | _] = accounts(1)

      assert {:ok, :joined} = Tourneys.join_tournament(tourney, a.id)
      assert Tourneys.current_players(tourney) == 1
      assert Tourneys.playing?(tourney, a.id)
    end

    test "rejects a second join from the same account" do
      tourney = tourney_fixture()
      [a] = accounts(1)
      {:ok, :joined} = Tourneys.join_tournament(tourney, a.id)
      assert {:error, :already_joined} = Tourneys.join_tournament(tourney, a.id)
    end

    test "rejects joins once the tourney is full" do
      tourney = tourney_fixture(%{"initial_games" => 2})
      players = accounts(4)
      {tourney, _} = join_all(tourney, players)

      extra = account_fixture()
      assert {:error, :full} = Tourneys.join_tournament(tourney, extra.id)
    end

    test "auto-starts once the last seat fills, seeding round 1 games" do
      tourney = tourney_fixture(%{"initial_games" => 2})
      players = accounts(4)
      {tourney, last_outcome} = join_all(tourney, players)

      assert last_outcome == :started
      assert Tourney.started?(tourney)

      round_one = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 1))
      assert length(round_one) == 2
      assert Enum.all?(round_one, &(length(&1.game.game_players) == 2))

      seated = round_one |> Enum.flat_map(&players_of/1) |> MapSet.new()
      assert seated == MapSet.new(players, & &1.id)
    end
  end

  describe "quit_tournament/2 (TourneyController.Quit)" do
    test "removes a signed-up player before start" do
      tourney = tourney_fixture()
      [a] = accounts(1)
      {:ok, :joined} = Tourneys.join_tournament(tourney, a.id)

      assert :ok = Tourneys.quit_tournament(tourney, a.id)
      refute Tourneys.playing?(tourney, a.id)
    end

    test "no-ops once the tourney has started" do
      tourney = tourney_fixture(%{"initial_games" => 2})
      players = accounts(4)
      {tourney, _} = join_all(tourney, players)
      [a | _] = players

      assert :noop = Tourneys.quit_tournament(tourney, a.id)
      assert Tourneys.playing?(tourney, a.id)
    end
  end

  describe "single-elimination bracket advancement across three rounds" do
    test "winners advance round over round until the tourney finishes" do
      tourney = tourney_fixture(%{"initial_games" => 4, "game_size" => 2, "winners" => 1})
      players = accounts(8)
      {tourney, last_outcome} = join_all(tourney, players)
      assert last_outcome == :started

      round_one = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 1))
      assert length(round_one) == 4

      round_one_winners =
        for tourney_game <- round_one do
          [loser, winner] = tourney_game.game.game_players

          Tourneys.finish_game(tourney_game.game_id, [
            {loser.account_id, 2},
            {winner.account_id, 1}
          ])

          winner.account_id
        end

      tourney = Tourneys.get_tourney!(tourney.id)
      assert tourney.status == :running

      round_two = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 2))
      assert length(round_two) == 2
      assert Enum.all?(round_two, &(length(&1.game.game_players) == 2))

      round_two_seated = round_two |> Enum.flat_map(&players_of/1) |> MapSet.new()
      assert round_two_seated == MapSet.new(round_one_winners)

      round_two_winners =
        for tourney_game <- round_two do
          [loser, winner] = tourney_game.game.game_players

          Tourneys.finish_game(tourney_game.game_id, [
            {loser.account_id, 2},
            {winner.account_id, 1}
          ])

          winner.account_id
        end

      tourney = Tourneys.get_tourney!(tourney.id)
      assert tourney.status == :running

      round_three = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 3))
      assert length(round_three) == 1
      [final_game] = round_three
      assert length(final_game.game.game_players) == 2
      assert players_of(final_game) == MapSet.new(round_two_winners)

      [loser, champion] = final_game.game.game_players
      Tourneys.finish_game(final_game.game_id, [{loser.account_id, 2}, {champion.account_id, 1}])

      tourney = Tourneys.get_tourney!(tourney.id)
      assert tourney.status == :finished
      assert tourney.end_time
    end
  end

  describe "option_game_id inheritance (Tourney.CreateTourneyGame's OptionGame ruleset copy)" do
    test "every bracket game inherits the option game's ruleset instead of bare schema defaults" do
      {:ok, option_game} =
        Games.create_game(%{
          map_name: :elements,
          is_fogged: true,
          is_non_random: true,
          reverse_attack_order: true,
          minimum_armies: 7,
          turn_length: 720
        })

      tourney =
        tourney_fixture(%{
          "initial_games" => 4,
          "game_size" => 2,
          "winners" => 1,
          "option_game_id" => option_game.id
        })

      {tourney, :started} = join_all(tourney, accounts(8))

      for tourney_game <- Tourneys.tourney_games(tourney) do
        game = tourney_game.game
        assert game.map_name == :elements
        assert game.is_fogged == true
        assert game.is_non_random == true
        assert game.reverse_attack_order == true
        assert game.minimum_armies == 7
        assert game.turn_length == 720
      end
    end

    test "falls back to schema defaults when option_game_id doesn't resolve to a real game" do
      tourney =
        tourney_fixture(%{
          "initial_games" => 2,
          "game_size" => 2,
          "winners" => 1,
          "option_game_id" => 999_999_999
        })

      {tourney, :started} = join_all(tourney, accounts(4))

      for tourney_game <- Tourneys.tourney_games(tourney) do
        game = tourney_game.game
        assert game.map_name == :original
        assert game.is_fogged == false
        assert game.is_non_random == false
        assert game.reverse_attack_order == false
        assert game.minimum_armies == 3
      end
    end
  end

  describe "double-elimination bracket advancement" do
    test "a round-1 loser drops into the loser bracket instead of being eliminated" do
      tourney =
        tourney_fixture(%{
          "initial_games" => 4,
          "game_size" => 2,
          "winners" => 1,
          "double_elimination" => true
        })

      players = accounts(8)
      {tourney, :started} = join_all(tourney, players)

      [round_one_game | _] = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 1))
      [loser, winner] = round_one_game.game.game_players

      Tourneys.finish_game(round_one_game.game_id, [{loser.account_id, 2}, {winner.account_id, 1}])

      loser_bracket_games = tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 4))
      seated = loser_bracket_games |> Enum.flat_map(&players_of/1) |> MapSet.new()

      assert MapSet.member?(seated, loser.account_id)
      refute MapSet.member?(seated, winner.account_id)

      winner_bracket_round_two =
        tourney |> Tourneys.tourney_games() |> Enum.filter(&(&1.round == 2))

      winner_seated = winner_bracket_round_two |> Enum.flat_map(&players_of/1) |> MapSet.new()
      assert MapSet.member?(winner_seated, winner.account_id)
    end
  end

  describe "Games (minimal GameServer port)" do
    test "create_game/join/players round-trips" do
      {:ok, game} = Games.create_game(%{})
      [a, b] = accounts(2)
      {:ok, _} = Games.join(game, a.id)
      {:ok, _} = Games.join(game, b.id)

      assert Games.player_count(game) == 2
      assert Games.players(game) |> Enum.map(& &1.id) == [a.id, b.id]
    end
  end
end
