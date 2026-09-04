defmodule GlobalCombat.Games.Supervisor do
  @moduledoc """
  DynamicSupervisor holding one `GlobalCombat.Games.Server` child per live game.

  GIF-74 item 3: also does the boot-time reconstruction nothing did before — every `games` row
  left `status: :active` (a node restart mid-game, or the whole app just booting fresh against
  an existing database) gets its `GlobalCombat.Games.Server` restarted straight from its last
  `games.serialized` snapshot, via the same rehydration path `GlobalCombat.Games.LiveResolver`
  uses for a claimed turn with no live process — otherwise a resolver alone would only ever
  reach these rows through that one-off "no process, run it offline" path, never actually
  repopulating `GlobalCombat.Games.Registry` for the board LiveView to attach to.
  """

  use DynamicSupervisor

  require Logger

  alias GlobalCombat.Games, as: GamesDb
  alias GlobalCombat.Games.Server

  def start_link(opts) do
    {:ok, pid} = DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
    rehydrate_active_games()
    {:ok, pid}
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  On-demand counterpart to the boot-time sweep below (GIF-119): ensures a live
  `GlobalCombat.Games.Server` process backs `game_id`, starting one from its persisted
  `games.serialized` snapshot if none is currently registered. Unlike `rehydrate_active_games/0`
  (which only ever runs once, at application boot), this is meant to be called from
  `GlobalCombat.Games.Live` on every player action/page load — so a game whose process died
  *after* boot (a crash this DynamicSupervisor didn't restart with fresh state, a deploy without
  a full node restart, a concurrent dev-server restart) gets transparently rehydrated the next
  time a player reaches it, instead of being permanently "not found" despite valid DB state.

  Returns `:ok` once a live process backs `game_id` (whether it was already alive or just
  started), or `{:error, :not_found}` if there's nothing valid to rehydrate — no such row, a
  `:finished` row, or a `:new`/`:active` row with no `serialized` snapshot yet.
  """
  def ensure_started(game_id) do
    if Server.alive?(game_id) do
      :ok
    else
      game_id |> GamesDb.get_game() |> start_if_rehydratable()
    end
  end

  # A `:new` row with a snapshot is a persisted lobby (`GlobalCombat.Games.Server` writes one on
  # every roster change) and rehydrates the same way — `Server.init/1` branches on the
  # snapshot's own `Started` flag, so this path doesn't need to know which it is.
  defp start_if_rehydratable(%{status: status, serialized: serialized} = game)
       when status in [:active, :new] and not is_nil(serialized) do
    case start_child(game) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "GlobalCombat.Games.Supervisor: failed to rehydrate game #{game.id} on demand: #{inspect(reason)}"
        )

        {:error, :not_found}
    end
  end

  defp start_if_rehydratable(_game), do: {:error, :not_found}

  # Off in :test for the same reason GlobalCombat.Application#turn_scheduler_child/0 is: a query
  # against GlobalCombat.Repo at application boot, outside any test's own Ecto Sandbox checkout,
  # would raise (or worse, race a sandboxed test's transaction) under `pool: Ecto.Adapters.SQL.
  # Sandbox`. Tests that exercise rehydration start a Games.Server with `rehydrate_from:` directly
  # instead of going through application boot.
  defp rehydrate_active_games do
    if Application.get_env(:global_combat, :rehydrate_active_games, true) do
      GamesDb.list_active_games() |> Enum.each(&rehydrate_game/1)
    end
  end

  # An :active row with no serialized snapshot yet is a narrow crash window (mark_active/1
  # committed but the process died before its first persist_snapshot write) rather than the
  # normal case — nothing to rehydrate from, so this is logged and skipped rather than handed to
  # GrpcHost.Game.decode/1, which would raise on nil.
  defp rehydrate_game(%{serialized: nil, id: id}) do
    Logger.error(
      "GlobalCombat.Games.Supervisor: game #{id} is :active with no persisted snapshot — skipping rehydration"
    )
  end

  defp rehydrate_game(game) do
    case start_child(game) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "GlobalCombat.Games.Supervisor: failed to rehydrate game #{game.id}: #{inspect(reason)}"
        )
    end
  end

  # Shared by both rehydration paths. `last_turn_time:` is required by
  # `Server.init/1`'s `rehydrate_from:` branch (`Keyword.fetch!(opts, :last_turn_time)`) —
  # previously omitted here, which meant the boot-time sweep this was lifted from would have
  # raised a KeyError on any real `:active` row (masked because `:rehydrate_active_games` is off
  # in :test, so nothing ever exercised it). `callers:` mirrors `Games.Live.create_game/1`'s
  # Ecto Sandbox handoff — this runs in the original caller's process (a page load, a test), not
  # this DynamicSupervisor's own, so `self()`/`$callers` here are the ones the spawned `Server`
  # needs to reach a sandboxed `GlobalCombat.Repo` connection.
  defp start_child(game) do
    opts = [
      game_id: game.id,
      rehydrate_from: game.serialized,
      turn_length_minutes: game.turn_length,
      last_turn_time: game.last_turn_time,
      callers: [self() | Process.get(:"$callers", [])]
    ]

    DynamicSupervisor.start_child(__MODULE__, {Server, opts})
  end
end
