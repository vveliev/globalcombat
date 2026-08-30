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
    opts = [
      game_id: game.id,
      rehydrate_from: game.serialized,
      turn_length_minutes: game.turn_length
    ]

    case DynamicSupervisor.start_child(__MODULE__, {Server, opts}) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "GlobalCombat.Games.Supervisor: failed to rehydrate game #{game.id}: #{inspect(reason)}"
        )
    end
  end
end
