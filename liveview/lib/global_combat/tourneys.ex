defmodule GlobalCombat.Tourneys do
  @moduledoc """
  Port of `Web/Models/Tourney.cs` and the tournament actions in
  `Web/Controllers/TourneyController.cs`. This is a rules port, not CRUD -- round progression
  (`GlobalCombat.Tourneys.Bracket`), seeding, and how a finished game feeds its result back
  into the bracket (`record_player_result/3`, `tourney_finished_check/1`, ported from
  `Tourney.PlayerFinishedCheck`/`Tourney.TourneyFinishedCheck`) are the meat of it.

  What a "finished game" *is* -- turn resolution, elimination, the board LiveView -- is out of
  scope (GIF-25/GIF-28/GIF-30); `finish_game/2` is the seam a caller supplies results through,
  mirroring where `Web/Models/GameServer.cs`'s `Game.OnEliminated`/`Game.OnEnd` handlers call
  into `Tourney.PlayerFinishedCheck`/`TourneyFinishedCheck` today.

  `list_open_tourneys/0` and `list_recent_tourneys_for_account/1` (GIF-33) are the two read-only
  exceptions: they port the inline queries in `Web/Controllers/HomeController.cs:25-29` and
  `:42-50` for the Home page's "Tournaments to Join"/"Your Recent Tourneys" lists.
  """

  import Ecto.Query

  alias GlobalCombat.Accounts
  alias GlobalCombat.Repo
  alias GlobalCombat.Games
  alias GlobalCombat.Games.Live, as: GamesLive
  alias GlobalCombat.Tourneys.{Bracket, Tourney, TourneyGame, TourneyPlayer}

  @doc "Port of `Tourney.CreateTournament`'s DB insert half; validation lives in `Tourney.create_changeset/2`."
  def create_tourney(attrs) do
    %Tourney{}
    |> Tourney.create_changeset(attrs)
    |> Repo.insert()
  end

  def get_tourney(id), do: Repo.get(Tourney, id)
  def get_tourney!(id), do: Repo.get!(Tourney, id)

  @doc "Ports `select * from tourney where status='New' order by id` — open tourneys to join."
  def list_open_tourneys do
    Repo.all(from t in Tourney, where: t.status == :new, order_by: [asc: t.id])
  end

  @doc """
  Ports the "Your Recent Tourneys" query (`select * from tourneyplayer, tourney where
  account_id = ? and id = tourney_id order by tourney_id desc limit 20`).
  """
  def list_recent_tourneys_for_account(account_id) do
    from(tp in TourneyPlayer,
      join: t in Tourney,
      on: t.id == tp.tourney_id,
      where: tp.account_id == ^account_id,
      order_by: [desc: t.id],
      limit: 20,
      select: t
    )
    |> Repo.all()
  end

  @doc "`Tourney.CurrentPlayers` -- computed from `tourneyplayer` rows, same as the live C# model (`Tourney.Load` never reads back the `curplayers` column, see the migration's comment)."
  def current_players(%Tourney{id: id}) do
    Repo.aggregate(from(tp in TourneyPlayer, where: tp.tourney_id == ^id), :count)
  end

  @doc "`Tourney.Players` -- signed-up accounts, in join order."
  def players(%Tourney{id: id}) do
    from(tp in TourneyPlayer,
      join: a in assoc(tp, :account),
      where: tp.tourney_id == ^id,
      order_by: tp.id,
      select: a
    )
    |> Repo.all()
  end

  @doc "Port of `Tourney.IsPlaying`."
  def playing?(%Tourney{} = tourney, account_id) do
    Enum.any?(players(tourney), &(&1.id == account_id))
  end

  @doc "The bracket shape for a tourney -- port of `Tourney.BuildRounds`, called from `Tourney.Load`."
  def bracket(%Tourney{} = tourney) do
    Bracket.build_rounds(%{
      initial_games: Tourney.initial_games(tourney),
      game_size: tourney.game_size,
      winners: tourney.winners,
      losers: Tourney.losers(tourney),
      double_elimination: tourney.double_elimination
    })
  end

  @doc """
  Every round across winner bracket, loser bracket, and final round, in bracket order -- the
  flattened list `Tourney.CreateTourneyGame`'s `winnerRound`/`loserRound` lookup runs over.
  """
  def all_rounds(%{winner_bracket: wb, loser_bracket: lb, final_round: fr}) do
    wb ++ lb ++ if fr, do: [fr], else: []
  end

  @doc """
  Games for a tourney, ordered by game_num -- port of `Tourney.LoadGames`, but returns the
  `tourneygame` rows (with `game` preloaded) rather than bare `Game` structs so callers have
  round/winner_round/loser_round available without a second lookup.
  """
  def tourney_games(%Tourney{id: id}) do
    from(tg in TourneyGame,
      where: tg.tourney_id == ^id,
      order_by: tg.game_num,
      preload: [game: [game_players: :account]]
    )
    |> Repo.all()
  end

  @doc """
  Port of `TourneyController.Join`. Returns `{:ok, :joined}` / `{:ok, :started}` (joined and
  the join filled the tourney, auto-starting it) or `{:error, reason}` with `reason` one of
  `:full`, `:already_joined`, `:already_started` -- mirroring the four `ViewBag.ErrorMessage`
  branches in the original action.
  """
  def join_tournament(%Tourney{} = tourney, account_id) do
    cond do
      current_players(tourney) >= tourney.max_players ->
        {:error, :full}

      playing?(tourney, account_id) ->
        {:error, :already_joined}

      Tourney.started?(tourney) ->
        {:error, :already_started}

      true ->
        {:ok, _} =
          %TourneyPlayer{}
          |> Ecto.Changeset.cast(%{tourney_id: tourney.id, account_id: account_id}, [
            :tourney_id,
            :account_id
          ])
          |> Repo.insert()

        if current_players(tourney) >= tourney.max_players and tourney.auto_start do
          {:ok, _tourney} = start_tournament(tourney)
          {:ok, :started}
        else
          {:ok, :joined}
        end
    end
  end

  @doc "Port of `TourneyController.Quit` -- only takes effect pre-start, silently no-ops otherwise (matching the original's `if` guard)."
  def quit_tournament(%Tourney{} = tourney, account_id) do
    if not Tourney.started?(tourney) and playing?(tourney, account_id) do
      Repo.delete_all(
        from tp in TourneyPlayer,
          where: tp.tourney_id == ^tourney.id and tp.account_id == ^account_id
      )

      :ok
    else
      :noop
    end
  end

  @doc """
  Port of `Tourney.Start`: builds every round's bracket games up front (winner bracket, and for
  double elimination the loser bracket + final round too -- exactly like the original, which
  creates all of them immediately rather than lazily as the bracket progresses), seeds round 1
  with the shuffled, signed-up player pool, and -- for a recurring tourney -- spins up the next
  copy the way `Start()` calls back into `CreateTournament(this)`.

  Only the DB bookkeeping (tourney status flip, `tourneygame` rows) runs inside a transaction --
  `seed_round_one/1` (GIF-115) calls into `Games.Server` processes, which are a *different* OS
  process than this one and need their own DB checkout for `Games.Live.force_start/1`'s
  `mark_active` write. A process can't check out the sandbox's single connection while this one
  is sitting inside an open `Repo.transaction` holding it and synchronously blocked waiting on
  that same GenServer call -- so seeding has to happen after the transaction commits, same as
  `Tourney.Start`'s original SQL, which never wrapped `Game.Join`/`GameServer.PlayerJoined` in an
  explicit transaction either.
  """
  def start_tournament(%Tourney{} = tourney) do
    if Tourney.started?(tourney) do
      {:error, :already_started}
    else
      {:ok, tourney} =
        Repo.transaction(fn ->
          {:ok, tourney} =
            tourney
            |> Ecto.Changeset.change(status: :running, start_time: DateTime.utc_now(:second))
            |> Repo.update()

          rounds = bracket(tourney)
          flat_rounds = all_rounds(rounds)

          Enum.each(flat_rounds, &create_round_games(tourney, &1, flat_rounds))

          tourney
        end)

      seed_round_one(tourney)

      if tourney.recurring do
        {:ok, _next} = recreate_recurring(tourney)
      end

      {:ok, tourney}
    end
  end

  # GIF-115: every bracket game must be created through `Games.Live.create_game/1` rather than
  # the plain DB-only `Games.create_game/1` -- only the `Live` context also starts the
  # `Games.Server` GenServer a game needs to be joinable/playable at all (`GameLive.mount/2`
  # gates entry on `Server.alive?/1`). The `TourneyGame`'s `game_id` still points at the same
  # `games` row either way (`Games.Live.create_game/1` writes that row itself, keyed by the same
  # id the Server is started against), so the rest of this module's DB-side bookkeeping (finding
  # a game by id, preloading `game_players`) is unaffected.
  defp create_round_games(tourney, round, flat_rounds) do
    {winner_round, loser_round} = Bracket.advancement_targets(round, flat_rounds)
    game_attrs = option_game_attrs(tourney, round)

    for game_num <- round.start_game..(round.start_game + round.game_count - 1) do
      game_id = GamesLive.create_game(game_attrs)

      {:ok, _tourney_game} =
        %TourneyGame{}
        |> Ecto.Changeset.cast(
          %{
            tourney_id: tourney.id,
            game_id: game_id,
            game_num: game_num,
            round: round.number,
            game_size: round.game_size,
            winners: tourney.winners,
            winner_round: winner_round,
            loser_round: loser_round
          },
          [
            :tourney_id,
            :game_id,
            :game_num,
            :round,
            :game_size,
            :winners,
            :winner_round,
            :loser_round
          ]
        )
        |> Repo.insert()
    end
  end

  # Port of `Tourney.CreateTourneyGame`'s `OptionGame` ruleset copy (`Tourney.cs:76-81`): every
  # bracket game inherits `option_game_id`'s map/fog/non-random/reverse-attack-order/minimum-
  # armies/turn-length instead of `Games.Live.create_game/1`'s schema defaults -- mirroring
  # `OptionGame`'s `GameServer.GetGame(OptionGameId)` lookup, this silently falls back to the
  # defaults (rather than raising) if `option_game_id` doesn't resolve to a real game.
  # `max_players` always comes from the round's own `game_size`, not `option_game_id` (a bracket
  # slot is never bigger than the round it belongs to), so `Games.Server`'s own seat limit
  # actually matches the size this module fills it to.
  defp option_game_attrs(%Tourney{option_game_id: option_game_id}, round) do
    base = %{max_players: round.game_size}

    case option_game_id && Games.get_game(option_game_id) do
      nil ->
        base

      option_game ->
        Map.merge(base, %{
          map_name: option_game.map_name,
          is_fogged: option_game.is_fogged,
          is_non_random: option_game.is_non_random,
          reverse_attack_order: option_game.reverse_attack_order,
          minimum_armies: option_game.minimum_armies,
          turn_length_minutes: option_game.turn_length
        })
    end
  end

  # GIF-115: seating a player has to reach both the `game_players` row (the DB-side roster the
  # bracket page (`tourney_html.ex`) and this module's own `Games.player_count/1` checks read)
  # *and* the running `Games.Server` (the only thing that makes the seat actually playable) --
  # `players/1` above already hands us full `Account` structs, so no extra lookup is needed for
  # the name `Games.Live.join/3` wants. Once a slot fills, `Games.Live.force_start/1` (not
  # `Games.mark_active/1`) is what actually flips the GenServer into `:playing` -- it updates the
  # DB status itself as a side effect, matching `Game.cs`'s `Join` -> `if (Players.Count >=
  # MaxPlayers) Start()` auto-start (there's no single "host" seat in a bracket game to gate a
  # manual `Games.Live.start_game/2` call the way `GameLive`'s lobby does).
  defp seed_round_one(tourney) do
    shuffled = tourney |> players() |> Enum.shuffle()

    round_one_games =
      from(tg in TourneyGame,
        where: tg.tourney_id == ^tourney.id and tg.round == 1,
        order_by: tg.game_num,
        preload: :game
      )
      |> Repo.all()

    round_one_games
    |> Enum.reduce(shuffled, fn tourney_game, remaining_players ->
      {seats, rest} = Enum.split(remaining_players, tourney_game.game_size)

      Enum.each(seats, fn account ->
        {:ok, _} = Games.join(tourney_game.game, account.id)
        {:ok, _} = GamesLive.join(tourney_game.game.id, account.id, account.name)
      end)

      if length(seats) >= tourney_game.game_size,
        do: :ok = GamesLive.force_start(tourney_game.game.id)

      rest
    end)
  end

  defp recreate_recurring(tourney) do
    name =
      if String.contains?(tourney.name, "#") do
        [base, counter] = String.split(tourney.name, "#", parts: 2)
        "#{base}##{String.to_integer(counter) + 1}"
      else
        tourney.name <> " #1"
      end

    create_tourney(%{
      "name" => name,
      "description" => tourney.description,
      "initial_games" => Tourney.initial_games(tourney),
      "game_size" => tourney.game_size,
      "winners" => tourney.winners,
      "double_elimination" => tourney.double_elimination,
      "auto_start" => tourney.auto_start,
      "recurring" => tourney.recurring,
      "option_game_id" => tourney.option_game_id
    })
  end

  @doc """
  Port of `Tourney.PlayerFinishedCheck`: routes an account that just finished a bracket game
  into whichever round its `place` sends it to next (winner round if `place <= tourneygame.winners`,
  loser round otherwise), seating it in the first not-yet-full game in that round, in game_num
  order. `target_round == 0` means nowhere to go (eliminated from the loser bracket, or this was
  the final) -- a no-op, matching the original.

  Original raises a hard exception when the target round has no open slot (a corrupted bracket);
  ported here as `{:error, :bracket_corrupted}` instead of crashing the caller.
  """
  def record_player_result(game_id, account_id, place) do
    case Repo.get_by(TourneyGame, game_id: game_id) do
      nil ->
        :ok

      %TourneyGame{} = tourney_game ->
        target_round =
          if place > tourney_game.winners,
            do: tourney_game.loser_round,
            else: tourney_game.winner_round

        if target_round == 0 do
          :ok
        else
          advance_into(tourney_game.tourney_id, target_round, account_id)
        end
    end
  end

  defp advance_into(tourney_id, target_round, account_id) do
    candidates =
      from(tg in TourneyGame,
        where: tg.tourney_id == ^tourney_id and tg.round == ^target_round,
        order_by: tg.game_num,
        preload: :game
      )
      |> Repo.all()

    target =
      Enum.find(candidates, fn tg ->
        tg.game.status != :active and Games.player_count(tg.game) < tg.game_size
      end)

    case target do
      nil ->
        {:error, :bracket_corrupted}

      %TourneyGame{} = tourney_game ->
        {:ok, _} = Games.join(tourney_game.game, account_id)

        account = Accounts.get_account_including_disabled(account_id)
        {:ok, _} = GamesLive.join(tourney_game.game.id, account_id, account.name)

        if Games.player_count(tourney_game.game) >= tourney_game.game_size do
          :ok = GamesLive.force_start(tourney_game.game.id)
        end

        {:ok, tourney_game}
    end
  end

  @doc "Port of `Tourney.TourneyFinishedCheck`: marks the tourney Finished once its last bracket game (by game_num) has been recorded."
  def tourney_finished_check(game_id) do
    case Repo.get_by(TourneyGame, game_id: game_id) do
      nil ->
        :ok

      %TourneyGame{tourney_id: tourney_id, game_num: game_num} ->
        max_game_num =
          Repo.one(
            from tg in TourneyGame, where: tg.tourney_id == ^tourney_id, select: max(tg.game_num)
          )

        if max_game_num == game_num do
          tourney = get_tourney!(tourney_id)

          {:ok, _} =
            tourney
            |> Ecto.Changeset.change(status: :finished, end_time: DateTime.utc_now(:second))
            |> Repo.update()
        end

        :ok
    end
  end

  @doc """
  The integration seam a finished game's results come in through -- port of the
  `Game.OnEliminated`/`Game.OnEnd` -> `Tourney.PlayerFinishedCheck`/`TourneyFinishedCheck`
  wiring in `Web/Models/GameServer.cs`. `results` is `[{account_id, place}]` for every player in
  the game, in the order they finished (losers first, winner last -- place `1` is first).
  """
  def finish_game(game_id, results) do
    Enum.each(results, fn {account_id, place} ->
      record_player_result(game_id, account_id, place)
    end)

    tourney_finished_check(game_id)
  end
end
