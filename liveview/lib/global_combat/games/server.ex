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

  alias GlobalCombat.Engine.DotnetRandom
  alias GlobalCombat.Engine.Game, as: Engine
  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombat.Engine.RandomAi
  alias GlobalCombat.Engine.Wire
  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.PlayerView
  alias GlobalCombat.Games.PubSub, as: GamePubSub
  alias GlobalCombat.GrpcHost
  alias GlobalCombat.Tourneys

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
    :db_last_turn_time,
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

  @doc """
  Starts the game once it has enough seats, without checking who's calling — mirrors `Game.cs`'s
  `Join`-driven auto-start (`if (Players.Count >= MaxPlayers) Start()`), for callers like tourney
  bracket seeding (GIF-115) where no single seat is a "host" to authorize `start_game/2`'s check.
  """
  def force_start(game_id) do
    GenServer.call(via(game_id), :force_start)
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

  @doc """
  Port of `GameController.Assign` + `Game.SetAssigned`. `account_id` is resolved to a
  seat and `area_number` ownership-checked inside the server, mirroring
  `GameController.Assign`'s `area.Owner != player` guard — same reasoning as
  `set_done/2`, a click handler can't be trusted to hand over a player number.
  """
  def assign(game_id, account_id, area_number, amount) do
    GenServer.cast(via(game_id), {:assign, account_id, area_number, amount})
  end

  @doc "Port of `GameController.Unassign` + `Game.ClearAssigned`."
  def unassign(game_id, account_id, area_number) do
    GenServer.cast(via(game_id), {:unassign, account_id, area_number})
  end

  @doc """
  Port of `GameController.Transfer` + `Game.SetTransfer`. Requires `account_id`'s seat
  to own both `area_number` and `target_area_number`, matching `GameController.Transfer`.
  """
  def transfer(game_id, account_id, area_number, target_area_number, amount) do
    GenServer.cast(via(game_id), {:transfer, account_id, area_number, target_area_number, amount})
  end

  @doc """
  Port of `GameController.Attack` + `Game.SetAttack`. Requires `account_id`'s seat to
  own `area_number` and *not* own `target_area_number`, matching `GameController.Attack`.
  """
  def attack(game_id, account_id, area_number, target_area_number, amount) do
    GenServer.cast(via(game_id), {:attack, account_id, area_number, target_area_number, amount})
  end

  @doc """
  Runs the turn `GlobalCombat.Games.TurnScheduler` already claimed for this game (GIF-74) —
  `claimed_last_turn_time` is the `last_turn_time` `GlobalCombat.Games.Scheduling.claim_turn/2`
  just wrote, so this process's own clock bookkeeping stays in sync with the DB without
  re-advancing it a second time (see `GlobalCombat.Games.advance_turn/4`'s moduledoc). Returns
  `{:error, :not_playing}` if this game isn't mid-play — the scheduler shouldn't have found it
  due otherwise, but a stale claim racing a since-ended game is a caller bug to report, not
  something to crash the scheduler sweep over.
  """
  def run_scheduled_turn(game_id, claimed_last_turn_time) do
    GenServer.call(via(game_id), {:run_scheduled_turn, claimed_last_turn_time})
  end

  # --- server callbacks ---------------------------------------------------

  @impl true
  def init(opts) do
    if callers = Keyword.get(opts, :callers) do
      Process.put(:"$callers", callers)
    end

    state =
      case Keyword.get(opts, :rehydrate_from) do
        nil -> fresh_state(opts)
        serialized -> rehydrated_state(opts, serialized)
      end

    {:ok, state}
  end

  defp fresh_state(opts) do
    %__MODULE__{
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
  end

  # Boot-time reconstruction (GIF-74 item 3): rebuilds a live, :playing Games.Server straight
  # from its last persisted wire snapshot instead of an empty lobby — the roster comes back out
  # of the engine's own Players (Wire.from_wire_snapshot/2 needs no separate lobby-roster
  # persistence: a rehydrated game is always already past start_game). The RNG is freshly
  # reseeded (see Wire.to_wire_game/2's moduledoc) — a discontinuity only a differential-harness
  # comparison would notice, never a production player.
  defp rehydrated_state(opts, serialized) do
    wire = GrpcHost.Game.decode(serialized)
    rng = DotnetRandom.new(:erlang.unique_integer())

    %{engine: engine, is_fogged: is_fogged, max_players: max_players} =
      Wire.from_wire_snapshot(wire, rng)

    %__MODULE__{
      game_id: Keyword.fetch!(opts, :game_id),
      map_name: engine.map_name,
      is_fogged: is_fogged,
      is_training: engine.is_training,
      is_non_random: engine.is_non_random,
      reverse_attack_order: engine.reverse_attack_order,
      minimum_armies: engine.minimum_armies,
      max_players: max_players,
      turn_length_minutes: Keyword.fetch!(opts, :turn_length_minutes),
      turn_started_at: DateTime.utc_now(),
      db_last_turn_time: Keyword.fetch!(opts, :last_turn_time),
      status: :playing,
      engine: engine,
      players: rehydrated_players(engine)
    }
  end

  defp rehydrated_players(engine) do
    Enum.map(Engine.players_in_order(engine), fn p ->
      {p.number, %{account_id: p.account_id, name: p.name}}
    end)
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
      {:reply, :ok, do_start(state)}
    else
      _ -> {:reply, {:error, :cannot_start}, state}
    end
  end

  def handle_call({:start_game, _account_id}, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call(:force_start, _from, %{status: :lobby} = state) do
    if length(state.players) >= 2 do
      {:reply, :ok, do_start(state)}
    else
      {:reply, {:error, :not_enough_players}, state}
    end
  end

  def handle_call(:force_start, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call(
        {:run_scheduled_turn, claimed_last_turn_time},
        _from,
        %{status: :playing} = state
      ) do
    state = run_turn(%{state | db_last_turn_time: claimed_last_turn_time}, advance_clock: false)
    {:reply, :ok, state}
  end

  def handle_call({:run_scheduled_turn, _claimed_last_turn_time}, _from, state) do
    {:reply, {:error, :not_playing}, state}
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

  # GIF-111: the four order-setters a player's territory clicks drive. Every clause
  # re-derives the acting seat from `account_id` and re-checks ownership against the
  # live engine state before touching it — a `phx-value-area` is just a number a
  # browser sent us, never trusted the way `GameController`'s session-bound `player`
  # was. An unauthorized/invalid order is a silent no-op, matching `GameController`'s
  # own `return 0` guards, not a crash — `Map.fetch!`-based `Engine.area!/2` would
  # take the whole game's GenServer down (every seated player, not just the sender)
  # on a bad area number, which a raw client param absolutely can be.
  def handle_cast({:assign, account_id, area_number, amount}, %{status: :playing} = state) do
    with player_number when not is_nil(player_number) <- find_player_number(state, account_id),
         true <- valid_amount?(amount),
         true <- owns_area?(state, player_number, area_number) do
      {_amount, engine} = Engine.set_assigned(state.engine, area_number, amount)
      {:noreply, apply_order(state, engine)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_cast({:assign, _account_id, _area_number, _amount}, state), do: {:noreply, state}

  def handle_cast({:unassign, account_id, area_number}, %{status: :playing} = state) do
    with player_number when not is_nil(player_number) <- find_player_number(state, account_id),
         true <- owns_area?(state, player_number, area_number) do
      {_amount, engine} = Engine.clear_assigned(state.engine, area_number)
      {:noreply, apply_order(state, engine)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_cast({:unassign, _account_id, _area_number}, state), do: {:noreply, state}

  def handle_cast(
        {:transfer, account_id, area_number, target_area_number, amount},
        %{status: :playing} = state
      ) do
    with player_number when not is_nil(player_number) <- find_player_number(state, account_id),
         true <- valid_amount?(amount),
         true <- owns_area?(state, player_number, area_number),
         true <- owns_area?(state, player_number, target_area_number) do
      {_amount, engine} = Engine.set_transfer(state.engine, area_number, target_area_number, amount)
      {:noreply, apply_order(state, engine)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_cast({:transfer, _account_id, _area_number, _target_area_number, _amount}, state),
    do: {:noreply, state}

  def handle_cast(
        {:attack, account_id, area_number, target_area_number, amount},
        %{status: :playing} = state
      ) do
    with player_number when not is_nil(player_number) <- find_player_number(state, account_id),
         true <- valid_amount?(amount),
         true <- owns_area?(state, player_number, area_number),
         true <- valid_area?(state, target_area_number),
         false <- owns_area?(state, player_number, target_area_number) do
      {_amount, engine} = Engine.set_attack(state.engine, area_number, target_area_number, amount)
      {:noreply, apply_order(state, engine)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_cast({:attack, _account_id, _area_number, _target_area_number, _amount}, state),
    do: {:noreply, state}

  # --- internals -----------------------------------------------------------

  # Shared by {:start_game, account_id} (host-authorized) and :force_start (unconditional,
  # GIF-115) — everything past "who's allowed to start this" is identical.
  defp do_start(state) do
    engine = state |> new_engine() |> run_ai_turns()
    {:ok, db_game} = state.game_id |> GamesDb.get_game!() |> GamesDb.mark_active()

    state = %{
      state
      | status: :playing,
        engine: engine,
        turn_started_at: DateTime.utc_now(),
        db_last_turn_time: db_game.last_turn_time
    }

    persist_snapshot(state)
    GamePubSub.broadcast_reload(state.game_id)
    state
  end

  defp find_player_number(state, account_id) do
    case Enum.find(state.players, fn {_n, p} -> p.account_id == account_id end) do
      {number, _p} -> number
      nil -> nil
    end
  end

  defp valid_amount?(amount), do: is_integer(amount) and amount >= 0

  defp valid_area?(state, number), do: is_integer(number) and Map.has_key?(state.engine.areas, number)

  defp owns_area?(state, player_number, area_number) do
    valid_area?(state, area_number) and
      Engine.area!(state.engine, area_number).owner_number == player_number
  end

  # Common tail of every order-setter above: land the new engine state, persist it
  # (so a crash/rehydrate mid-turn doesn't silently drop a queued order — same
  # `persist_snapshot/1` `start_game`/`run_turn` already use), and reload every
  # subscriber, including the sender's own view.
  defp apply_order(state, engine) do
    state = %{state | engine: engine}
    persist_snapshot(state)
    GamePubSub.broadcast_reload(state.game_id)
    state
  end

  defp time_left(%{turn_started_at: nil}), do: 0

  defp time_left(state) do
    deadline = DateTime.add(state.turn_started_at, state.turn_length_minutes * 60, :second)
    DateTime.diff(deadline, DateTime.utc_now(), :second)
  end

  @doc false
  def new_engine(state) do
    player_count = length(state.players)
    num_areas = MapInfo.num_areas(state.map_name)
    dealt = deal_areas(num_areas, player_count)

    areas =
      Map.new(dealt, fn {area_number, owner_number} ->
        {area_number, %Engine.Area{number: area_number, owner_number: owner_number, armies: 5}}
      end)

    # Port of `Game.cs Start()`'s "give initial armies to place and give army bonus for
    # players who didn't get country" loop (line ~327): every player starts with 20
    # unassigned armies, +5 more if they only got the base `NumAreas / CurrentPlayers`
    # share (no extra area from divvying up the remainder). `Player.Armies` folds that
    # pending pool in immediately, before any turn resolves — GIF-105 is `PlayerView`'s
    # display total not doing the same.
    initial_area_count = div(num_areas, player_count)

    players =
      Map.new(state.players, fn {number, p} ->
        owned = Enum.count(areas, fn {_n, a} -> a.owner_number == number end)
        unassigned = if owned == initial_area_count, do: 25, else: 20

        {number,
         %Engine.Player{
           number: number,
           account_id: p.account_id,
           name: p.name,
           areas: owned,
           armies: owned * 5 + unassigned,
           unassigned_armies: unassigned
         }}
      end)

    %Engine{
      map_name: state.map_name,
      rng: DotnetRandom.new(:erlang.unique_integer()),
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

  # GIF-104: `RandomAi` (GIF-28) was validated by the differential harness in isolation but
  # never wired into live play — a seat's `done` flag only ever flipped via a human's
  # `set_done`/`force_turn` cast, which never arrives for the reserved "Computer" account
  # (account_id 1, see `Engine.reset_done_flags/1`), so training games stuck on turn 1 forever.
  # Ports `GameController.Create`'s `model.Join(1, "Computer", 0).Done = true` — the Computer
  # seat is marked done the instant its turn starts, not waited on — but additionally runs
  # `RandomAi.think/1` first (the oracle-side-only `RandomAiPlayer.Think` call in
  # `GameEngineService.cs` was never ported to the live .NET web app either, leaving that
  # "AI" a purely passive placeholder there; this wires it up for real so Training Mode's
  # opponent actually plays instead of just rubber-stamping "done").
  defp run_ai_turns(%Engine{ended: true} = engine), do: engine

  defp run_ai_turns(engine) do
    Enum.reduce(Engine.players_in_order(engine), engine, fn player, engine ->
      if computer_seat?(player) and not Engine.eliminated?(player) do
        engine
        |> RandomAi.think()
        |> then(&put_in(&1.players[player.number].done, true))
      else
        engine
      end
    end)
  end

  defp computer_seat?(%Engine.Player{account_id: 1}), do: true
  defp computer_seat?(%Engine.Player{}), do: false

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

  # `advance_clock: true` (the default — every self-triggered run: all-players-done, force_turn)
  # advances games.turn/prev_turn_time/last_turn_time itself, mirroring what
  # GlobalCombat.Games.Scheduling.claim_turn/2 would have done had the scheduler gotten there
  # first. `advance_clock: false` is only passed from the {:run_scheduled_turn, _} handler, whose
  # caller already advanced those columns via an actual claim_turn/2 call before handing off —
  # see GlobalCombat.Games.advance_turn/4's moduledoc for why running it again here would be a
  # double-advance, not idempotent.
  defp run_turn(state, opts \\ []) do
    advance_clock? = Keyword.get(opts, :advance_clock, true)
    engine = state.engine |> Engine.run_turn() |> run_ai_turns()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    state = %{state | engine: engine, turn_started_at: now}

    state =
      if advance_clock? do
        GamesDb.advance_turn(state.game_id, engine.turn, state.db_last_turn_time, now)
        %{state | db_last_turn_time: now}
      else
        state
      end

    persist_snapshot(state)

    if engine.ended do
      GamesDb.finish_game(state.game_id)

      # GIF-116: wires the seam `Tourneys.finish_game/2`'s moduledoc documents but nothing
      # ever called outside tests -- mirrors `Web/Models/GameServer.cs`'s `Game.OnEnd` calling
      # into `Tourney.PlayerFinishedCheck`/`TourneyFinishedCheck`. Unconditional: `finish_game/2`
      # already no-ops (via `record_player_result/3`'s `Repo.get_by(TourneyGame, ...)` lookup)
      # for a game_id that isn't part of any tourney, so a plain lobby/training game costs one
      # harmless extra query rather than needing this call gated on a tourney_id this schema
      # doesn't have.
      Tourneys.finish_game(state.game_id, tourney_results(engine))
    end

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

  defp persist_snapshot(state) do
    wire =
      Wire.to_wire_game(state.engine,
        game_id: state.game_id,
        turn_length_minutes: state.turn_length_minutes,
        max_players: state.max_players,
        is_fogged: state.is_fogged
      )

    GamesDb.persist_serialized(state.game_id, GrpcHost.Game.encode(wire))
  end

  defp notifiable_accounts(state) do
    Enum.map(state.players, fn {number, p} -> {number, p.account_id} end)
  end

  defp player_turn_summary(engine, number) do
    player = Engine.player!(engine, number)
    "#{player.armies} armies, #{player.areas} areas."
  end

  # `Tourneys.finish_game/2`'s `results` shape: `[{account_id, place}]`. Every player has a
  # nonzero `place` by the time `engine.ended` is true (`Engine.eliminate_player/2` assigns it
  # on the way out, `Engine.end_game/1` backfills the last survivor's place as 1).
  defp tourney_results(engine) do
    Enum.map(Engine.players_in_order(engine), fn p -> {p.account_id, p.place} end)
  end
end
