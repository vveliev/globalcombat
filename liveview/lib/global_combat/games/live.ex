defmodule GlobalCombat.Games.Live do
  @moduledoc """
  Public API for live games (GIF-30). `GameLive` and `GameCreateLive` talk to games
  exclusively through this module — never to `GlobalCombat.Games.Server` or
  `GlobalCombat.Engine.Game` directly — so the fog-of-war filtering boundary in
  `GlobalCombat.Games.PlayerView` can't be bypassed by a shortcut call from the web layer.

  Named `Games.Live` rather than `Games` because `GlobalCombat.Games` is already the
  MySQL-backed persistence/listing facade for the `games`/`game_players` tables (GIF-32/33).

  As of GIF-74, `create_game/1` creates its `games` row here (a real `games.id`, not a bare
  `System.unique_integer/1`) and starts `GlobalCombat.Games.Server` against that same id, so a
  `GlobalCombat.Games.TurnScheduler` claim and this in-memory process refer to the same game —
  see `GlobalCombat.Games.LiveResolver`'s moduledoc for the other half (the scheduler handing a
  claimed turn back to whichever of "the live process" or "persisted state" actually has it).
  `game_players` rows still aren't written here (the roster lives entirely on the `Server`
  process, mirrored into `games.serialized` only once play starts) — a lobby only shows up in
  `GlobalCombat.Games.list_new_games/0` once it exists as a row at all; it won't yet show up in
  `GlobalCombat.Games.list_player_games/2` for anyone who joined it, since that reads
  `game_players`. Tracked as a known gap, not silently "fixed" by this ticket.
  """

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.PubSub, as: GamePubSub
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

  @default_turn_length_minutes 1440

  @doc """
  Creates a new game lobby (a `games` row plus the `GlobalCombat.Games.Server` process backing
  it) and returns its id. `attrs` may include `:map_name` (`:original` | `:elements`),
  `:is_fogged`, `:is_training`, `:is_non_random`, `:reverse_attack_order`, `:minimum_armies`,
  `:max_players`, `:turn_length_minutes` — see `GameController.Create`/`Views/Game/Create.cshtml`
  for the legacy field set. `:turn_length_minutes` also opts the row into
  `GlobalCombat.Games.Scheduling.list_due/1` once it goes active (`GlobalCombat.Games.Server`
  calls `GlobalCombat.Games.mark_active/1` on `start_game/2`).
  """
  def create_game(attrs \\ %{}) do
    turn_length = Map.get(attrs, :turn_length_minutes, @default_turn_length_minutes)

    {:ok, db_game} =
      GamesDb.create_game(%{
        status: :new,
        private: false,
        turn_length: turn_length,
        map_name: Map.get(attrs, :map_name, :original),
        is_fogged: Map.get(attrs, :is_fogged, false),
        is_non_random: Map.get(attrs, :is_non_random, false),
        reverse_attack_order: Map.get(attrs, :reverse_attack_order, false),
        minimum_armies: Map.get(attrs, :minimum_armies, 3)
      })

    # Captures the calling process's Ecto Sandbox ownership chain so the freshly-spawned
    # Games.Server — a *different* process than whoever called create_game/1, started by
    # GamesSupervisor rather than inheriting it — can still reach GlobalCombat.Repo under an
    # async test's non-shared sandbox. See Ecto.Adapters.SQL.Sandbox's docs on `$callers`;
    # Server.init/1 does the matching `Process.put(:"$callers", ...)`.
    callers = [self() | Process.get(:"$callers", [])]

    opts =
      [game_id: db_game.id, callers: callers]
      |> Keyword.merge(Enum.map(attrs, fn {k, v} -> {k, v} end))

    {:ok, _pid} = DynamicSupervisor.start_child(GamesSupervisor, {Server, opts})
    db_game.id
  end

  def game_exists?(game_id), do: Server.alive?(game_id)

  @doc "Port of `GameController.Join` + `Game.Join`/`GameServer.PlayerJoined`."
  def join(game_id, account_id, name), do: with_game(game_id, &Server.join(&1, account_id, name))

  @doc "Port of `GameController.Start`."
  def start_game(game_id, account_id), do: with_game(game_id, &Server.start_game(&1, account_id))

  @doc """
  Starts a game once its seats are full without a designated host — port of `Game.cs`'s `Join`
  auto-start (`if (Players.Count >= MaxPlayers) Start()`), used by tourney bracket seeding
  (GIF-115) where no single seat is the "host" authorized to call `start_game/2`.
  """
  def force_start(game_id), do: with_game(game_id, &Server.force_start/1)

  @doc "Port of `GameController.Send`."
  def send_chat(game_id, account_id, name, text),
    do: with_game(game_id, &Server.send_chat(&1, account_id, name, text))

  @doc "Port of `GameController.Done`. `account_id` is resolved to a seat inside the game server, never trusted as a caller-supplied player number."
  def set_done(game_id, account_id), do: with_game(game_id, &Server.set_done(&1, account_id))

  @doc "Port of `GameController.ForceTurn`. Same `account_id` resolution as `set_done/2`."
  def force_turn(game_id, account_id),
    do: with_game(game_id, &Server.force_turn(&1, account_id))

  @doc "Port of `GameController.Assign`. Same `account_id`/ownership resolution as `set_done/2`."
  def assign(game_id, account_id, area_number, amount),
    do: with_game(game_id, &Server.assign(&1, account_id, area_number, amount))

  @doc "Port of `GameController.Unassign`."
  def unassign(game_id, account_id, area_number),
    do: with_game(game_id, &Server.unassign(&1, account_id, area_number))

  @doc "Port of `GameController.Transfer`."
  def transfer(game_id, account_id, area_number, target_area_number, amount),
    do:
      with_game(
        game_id,
        &Server.transfer(&1, account_id, area_number, target_area_number, amount)
      )

  @doc "Port of `GameController.Attack`."
  def attack(game_id, account_id, area_number, target_area_number, amount),
    do:
      with_game(
        game_id,
        &Server.attack(&1, account_id, area_number, target_area_number, amount)
      )

  @doc """
  Returns `{:lobby, view} | {:playing, %GlobalCombat.Games.PlayerView{}}` for the player
  `account_id` resolves to, or a spectator's view if `account_id` is `nil`/not seated.
  """
  def player_view(game_id, account_id),
    do: with_game(game_id, &Server.player_view(&1, account_id))

  @doc "Subscribes the calling process to this game's board updates."
  def subscribe(game_id), do: GamePubSub.subscribe_game(game_id)

  @doc "Subscribes the calling process to one account's private messages/notifications."
  def subscribe_account(account_id), do: GamePubSub.subscribe_account(account_id)

  defp with_game(game_id, fun) do
    if Server.alive?(game_id), do: fun.(game_id), else: {:error, :not_found}
  end
end
