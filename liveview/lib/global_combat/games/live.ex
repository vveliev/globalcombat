defmodule GlobalCombat.Games.Live do
  @moduledoc """
  Public API for live games (GIF-30). `GameLive` and `GameCreateLive` talk to games
  exclusively through this module — never to `GlobalCombat.Games.Server` or
  `GlobalCombat.Engine.Game` directly — so the fog-of-war filtering boundary in
  `GlobalCombat.Games.PlayerView` can't be bypassed by a shortcut call from the web layer.

  Named `Games.Live` rather than `Games` because `GlobalCombat.Games` is already the
  MySQL-backed persistence/listing facade for the `games`/`game_players` tables (GIF-32/33).
  The two don't share state: a game started here is a bare in-memory process, not a row in
  that table — reconciling the two (persisting board state, listing live games alongside
  DB-backed ones) is the follow-up `GlobalCombat.Games.Server`'s moduledoc already tracks.
  """

  alias GlobalCombat.Games.PubSub, as: GamePubSub
  alias GlobalCombat.Games.Server
  alias GlobalCombat.Games.Supervisor, as: GamesSupervisor

  @doc """
  Creates a new game lobby and returns its id. `attrs` may include `:map_name`
  (`:original` | `:elements`), `:is_fogged`, `:is_training`, `:is_non_random`,
  `:reverse_attack_order`, `:minimum_armies`, `:max_players`, `:turn_length_minutes` —
  see `GameController.Create`/`Views/Game/Create.cshtml` for the legacy field set.
  """
  def create_game(attrs \\ %{}) do
    game_id = System.unique_integer([:positive])
    opts = Keyword.merge([game_id: game_id], Enum.map(attrs, fn {k, v} -> {k, v} end))
    {:ok, _pid} = DynamicSupervisor.start_child(GamesSupervisor, {Server, opts})
    game_id
  end

  def game_exists?(game_id), do: Server.alive?(game_id)

  @doc "Port of `GameController.Join` + `Game.Join`/`GameServer.PlayerJoined`."
  def join(game_id, account_id, name), do: with_game(game_id, &Server.join(&1, account_id, name))

  @doc "Port of `GameController.Start`."
  def start_game(game_id, account_id), do: with_game(game_id, &Server.start_game(&1, account_id))

  @doc "Port of `GameController.Send`."
  def send_chat(game_id, account_id, name, text),
    do: with_game(game_id, &Server.send_chat(&1, account_id, name, text))

  @doc "Port of `GameController.Done`. `account_id` is resolved to a seat inside the game server, never trusted as a caller-supplied player number."
  def set_done(game_id, account_id), do: with_game(game_id, &Server.set_done(&1, account_id))

  @doc "Port of `GameController.ForceTurn`. Same `account_id` resolution as `set_done/2`."
  def force_turn(game_id, account_id),
    do: with_game(game_id, &Server.force_turn(&1, account_id))

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
