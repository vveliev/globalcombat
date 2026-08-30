defmodule GlobalCombat.Games.Server do
  @moduledoc """
  One process per live game (GIF-30) — the runtime replacement for the combination of
  `Web/Models/GameServer.cs`'s in-memory `MemoryCache<Game>` and the `GlobalCombat.Core.Game`
  instance it cached. Owns the canonical `%GlobalCombat.Engine.Game{}` and is the only
  thing in the system allowed to touch it unfiltered — everyone else (`GameLive` included)
  goes through `GlobalCombat.Games.Live.player_view/2`, which calls back in here for state and
  returns `GlobalCombat.Games.PlayerView.build/3`'s fog-filtered projection instead of the
  struct itself. See `PlayerView`'s moduledoc for why that boundary has to be enforced here
  rather than trusted to callers.

  ## Scope cut this ticket makes on purpose

  `GlobalCombat.Core/Game.cs`'s `Start()` — the RNG-driven, retry-until-balanced area deal —
  is explicitly not ported to Elixir (`GlobalCombat.Engine.Game`'s moduledoc: "the harness
  always sources a game's starting state from the .NET oracle's own `NewGame` response").
  ADR-0001 (GIF-25) already settled that real game creation should ask the .NET engine over
  gRPC for that starting state, not reimplement its balancing algorithm here. Standing up that
  integration (a live `GlobalCombat.GrpcHost` process as a runtime dependency of the Phoenix
  app, plus the `games`/`game_players` Ecto persistence schema-map.md already designed in
  §1.1 but nothing has implemented yet) is its own substantial task, orthogonal to "replace
  the SignalR transport with LiveView/PubSub" — so `deal_areas/2` below is a simple, clearly-
  labeled round-robin dealer that produces *a* valid starting position (enough to prove turns
  resolve and broadcast live), not *the* oracle's balanced one. Tracked as a follow-up.
  """

  use GenServer

  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombat.Games.PlayerView
  alias GlobalCombat.Games.PubSub, as: GamePubSub

  @registry GlobalCombat.Games.Registry
  @max_messages 150

  defstruct [
    :game_id,
    :map_name,
    :is_fogged,
    :is_training,
    :is_non_random,
    :reverse_attack_order,
    :minimum_armies,
    :max_players,
    :turn_length_minutes,
    :turn_started_at,
    :is_private,
    status: :lobby,
    players: [],
    engine: nil,
    messages: []
  ]

  # --- client API --------------------------------------------------------

  def child_spec(opts) do
    game_id = Keyword.fetch!(opts, :game_id)

    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via(game_id))
  end

  def via(game_id), do: {:via, Registry, {@registry, game_id}}

  def alive?(game_id), do: Registry.lookup(@registry, game_id) != []

  @doc """
  Returns `{:lobby, view}` before `start_game/2`, or `{:playing, %PlayerView{}}` after,
  for the player `account_id` resolves to (or a spectator's view if `account_id` is `nil`
  or isn't seated in this game). `account_id` is resolved to a player number *inside* the
  server, never accepted as a caller-supplied player number — the web layer only ever
  knows the logged-in account, never "which seat am I," so a click handler can't be
  tricked into acting as a different player by forging a player-number param.
  """
  def player_view(game_id, account_id) do
    GenServer.call(via(game_id), {:player_view, account_id})
  end

  @doc "Joins `account_id` to the game's lobby. Returns `{:ok, player_number}` or `{:error, reason}`."
  def join(game_id, account_id, name) do
    GenServer.call(via(game_id), {:join, account_id, name})
  end

  @doc "Starts the game (host/player 1 only, matching `GameController.Start`'s `player.Number == 1` check)."
  def start_game(game_id, account_id) do
    GenServer.call(via(game_id), {:start_game, account_id})
  end

  @doc "Port of `GameController.Send` + `Game.SendForumMessage` — broadcasts to everyone on the board."
  def send_chat(game_id, account_id, name, text) do
    GenServer.cast(via(game_id), {:chat, account_id, name, text})
  end

  @doc "Port of `GameController.Done` + `Game.Done`. `account_id` is resolved to a seat server-side, same reasoning as `player_view/2`."
  def set_done(game_id, account_id) do
    GenServer.cast(via(game_id), {:done, account_id})
  end

  @doc "Port of `GameController.ForceTurn` + `Game.ForceTurn`."
  def force_turn(game_id, account_id) do
    GenServer.cast(via(game_id), {:force_turn, account_id})
  end

  # --- server callbacks ---------------------------------------------------

  @impl true
  def init(opts) do
    state = %__MODULE__{
      game_id: Keyword.fetch!(opts, :game_id),
      map_name: Keyword.get(opts, :map_name, :original),
      is_fogged: Keyword.get(opts, :is_fogged, false),
      is_training: Keyword.get(opts, :is_training, false),
      is_non_random: Keyword.get(opts, :is_non_random, false),
      reverse_attack_order: Keyword.get(opts, :reverse_attack_order, false),
      minimum_armies: Keyword.get(opts, :minimum_armies, 3),
      max_players: Keyword.get(opts, :max_players, 6),
      turn_length_minutes: Keyword.get(opts, :turn_length_minutes, 1440),
      is_private: Keyword.get(opts, :is_private, false)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:player_view, account_id}, _from, %{status: :lobby} = state) do
    view = %{
      status: :lobby,
      game_id: state.game_id,
      map_name: state.map_name,
      is_fogged: state.is_fogged,
      max_players: state.max_players,
      viewer_number: find_player_number(state, account_id),
      players:
        Enum.map(state.players, fn {number, p} ->
          %{
            number: number,
            name: p.name,
            done: false,
            eliminated: false,
            place: nil,
            areas: nil,
            armies: nil
          }
        end)
    }

    {:reply, {:lobby, view}, state}
  end

  def handle_call({:player_view, account_id}, _from, state) do
    viewer_number = find_player_number(state, account_id)

    view =
      PlayerView.build(state.engine, viewer_number,
        game_id: state.game_id,
        is_fogged: state.is_fogged,
        messages: state.messages
      )

    {:reply, {:playing, view}, state}
  end

  def handle_call({:join, account_id, name}, _from, %{status: :lobby} = state) do
    cond do
      Enum.any?(state.players, fn {_n, p} -> p.account_id == account_id end) ->
        {:reply, {:error, :already_joined}, state}

      length(state.players) >= state.max_players ->
        {:reply, {:error, :full}, state}

      true ->
        number = length(state.players) + 1
        players = state.players ++ [{number, %{account_id: account_id, name: name}}]
        state = %{state | players: players}
        GamePubSub.broadcast_reload(state.game_id)
        {:reply, {:ok, number}, state}
    end
  end

  def handle_call({:join, _account_id, _name}, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call({:start_game, account_id}, _from, %{status: :lobby} = state) do
    with 1 <- find_player_number(state, account_id),
         true <- length(state.players) >= 2 do
      engine = new_engine(state)
      state = %{state | status: :playing, engine: engine, turn_started_at: DateTime.utc_now()}
      GamePubSub.broadcast_reload(state.game_id)
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :cannot_start}, state}
    end
  end

  def handle_call({:start_game, _account_id}, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  @impl true
  def handle_cast({:chat, account_id, name, text}, state) do
    message = %{source_id: account_id, source_name: name, text: text, sent: DateTime.utc_now()}
    messages = Enum.take([message | state.messages], @max_messages)
    GamePubSub.broadcast_add_message(state.game_id, message)
    {:noreply, %{state | messages: messages}}
  end

  def handle_cast({:done, account_id}, %{status: :playing} = state) do
    case find_player_number(state, account_id) do
      nil -> {:noreply, state}
      player_number -> {:noreply, mark_done(state, player_number)}
    end
  end

  def handle_cast({:done, _account_id}, state), do: {:noreply, state}

  def handle_cast({:force_turn, account_id}, %{status: :playing} = state) do
    player_number = find_player_number(state, account_id)

    if player_number && time_left(state) <= 0 do
      player = Engine.player!(state.engine, player_number)

      message = %{
        source_id: 1,
        source_name: "Computer",
        text: "#{player.name} forced the turn to run.",
        sent: DateTime.utc_now()
      }

      GamePubSub.broadcast_add_message(state.game_id, message)
      state = run_turn(%{state | messages: Enum.take([message | state.messages], @max_messages)})
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:force_turn, _account_id}, state), do: {:noreply, state}

  # --- internals -----------------------------------------------------------

  defp find_player_number(state, account_id) do
    case Enum.find(state.players, fn {_n, p} -> p.account_id == account_id end) do
      {number, _p} -> number
      nil -> nil
    end
  end

  defp time_left(%{turn_started_at: nil}), do: 0

  defp time_left(state) do
    deadline = DateTime.add(state.turn_started_at, state.turn_length_minutes * 60, :second)
    DateTime.diff(deadline, DateTime.utc_now(), :second)
  end

  @doc false
  def new_engine(state) do
    player_count = length(state.players)
    dealt = deal_areas(MapInfo.num_areas(state.map_name), player_count)

    areas =
      Map.new(dealt, fn {area_number, owner_number} ->
        {area_number, %Engine.Area{number: area_number, owner_number: owner_number, armies: 5}}
      end)

    players =
      Map.new(state.players, fn {number, p} ->
        owned = Enum.count(areas, fn {_n, a} -> a.owner_number == number end)

        {number,
         %Engine.Player{
           number: number,
           account_id: p.account_id,
           name: p.name,
           areas: owned,
           armies: owned * 5
         }}
      end)

    %Engine{
      map_name: state.map_name,
      rng: GlobalCombat.Engine.DotnetRandom.new(:erlang.unique_integer()),
      turn: 1,
      is_non_random: state.is_non_random,
      reverse_attack_order: state.reverse_attack_order,
      minimum_armies: state.minimum_armies,
      is_training: state.is_training,
      areas: areas,
      players: players
    }
  end

  @doc "Round-robin deals `num_areas` areas across `player_count` players — see moduledoc for why this isn't the oracle's balanced `Start()`."
  def deal_areas(num_areas, player_count) do
    for area_number <- 1..num_areas do
      {area_number, rem(area_number - 1, player_count) + 1}
    end
  end

  defp mark_done(state, player_number) do
    player = Engine.player!(state.engine, player_number)

    if player.done do
      state
    else
      state = update_in(state.engine.players[player_number], &%{&1 | done: true})

      if all_done?(state.engine) do
        run_turn(state)
      else
        GamePubSub.broadcast_set_done(state.game_id, player_number)
        state
      end
    end
  end

  defp all_done?(engine) do
    Engine.players_in_order(engine) |> Enum.all?(& &1.done)
  end

  defp run_turn(state) do
    engine = Engine.run_turn(state.engine)
    state = %{state | engine: engine, turn_started_at: DateTime.utc_now()}

    for {number, account_id} <- notifiable_accounts(state) do
      GamePubSub.broadcast_notification(
        account_id,
        "Turn #{engine.turn} Run",
        player_turn_summary(engine, number),
        "/Game-#{state.game_id}/"
      )
    end

    GamePubSub.broadcast_reload(state.game_id)
    state
  end

  defp notifiable_accounts(state) do
    Enum.map(state.players, fn {number, p} -> {number, p.account_id} end)
  end

  defp player_turn_summary(engine, number) do
    player = Engine.player!(engine, number)
    "#{player.armies} armies, #{player.areas} areas."
  end
end
