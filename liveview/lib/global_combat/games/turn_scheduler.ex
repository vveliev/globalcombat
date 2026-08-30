defmodule GlobalCombat.Games.TurnScheduler.Resolver do
  @moduledoc """
  Callback contract for whatever actually applies a claimed turn's game logic — running
  `GlobalCombat.Engine.Game.run_turn/1` (or an AI's think step) against the game's real state
  and persisting the result. `GlobalCombat.Games.TurnScheduler` only owns the sweep + the atomic
  DB claim (GIF-68's scope); it calls a configured resolver for the actual resolution rather
  than doing it itself, because there is currently no code path that persists a live
  `GlobalCombat.Engine.Game`'s play state to a `games` row at all — `GlobalCombat.Games.Server`
  (GIF-30) owns that state entirely in-memory, keyed by a bare `System.unique_integer/1`, not a
  `games.id` (see that module's moduledoc: "the two don't share state yet"). Wiring a resolver
  that bridges the two is tracked as a follow-up; until one is configured, the scheduler finds
  due games and logs them without claiming, rather than silently advancing a game's turn clock
  with no game logic actually applied.
  """

  @callback resolve_turn(GlobalCombat.Games.Game.t()) :: :ok | {:error, term()}
end

defmodule GlobalCombat.Games.TurnScheduler do
  @moduledoc """
  Supervised GenServer doing a periodic sweep for games due for a turn, per GIF-68's decision
  record: not Oban, since this project runs on MySQL (myxql) and Oban's polling/notification
  optimizations are Postgres-specific, while a plain sweep + `GlobalCombat.Games.Scheduling.
  claim_turn/2`'s conditional `UPDATE` is DB-engine-agnostic and needs no extra dependency.

  Every tick is a full re-evaluation of "which games are due" straight from the database — the
  process holds no schedule of its own, so a node restart (or the scheduler itself crashing and
  being restarted by its supervisor) can neither double-resolve a turn nor skip one; the next
  sweep just finds whatever is still due.
  """

  use GenServer

  require Logger

  alias GlobalCombat.Games.Scheduling

  @default_interval_ms 15_000

  @doc """
  Starts the scheduler, registered as `#{inspect(__MODULE__)}` by default (matching the single
  instance the application supervisor starts). Pass `name: nil` to start unnamed — tests do this
  to run multiple instances concurrently under `async: true`.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs one sweep synchronously and returns its result — for tests, instead of waiting on the timer."
  def sweep_now(server \\ __MODULE__) do
    GenServer.call(server, :sweep_now)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:global_combat, __MODULE__, [])

    state = %{
      interval_ms:
        Keyword.get(opts, :interval_ms, Keyword.get(config, :interval_ms, @default_interval_ms)),
      resolver: Keyword.get(opts, :resolver, Keyword.get(config, :resolver))
    }

    schedule_sweep(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(state)
    schedule_sweep(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    {:reply, sweep(state), state}
  end

  defp schedule_sweep(state), do: Process.send_after(self(), :sweep, state.interval_ms)

  defp sweep(%{resolver: nil}) do
    case Scheduling.list_due() do
      [] ->
        :ok

      due ->
        Logger.warning(
          "GlobalCombat.Games.TurnScheduler: #{length(due)} game(s) due for a turn but no " <>
            "resolver is configured — skipping (config :global_combat, #{inspect(__MODULE__)}, resolver: ...)"
        )

        :ok
    end
  end

  defp sweep(%{resolver: resolver}) do
    Scheduling.list_due()
    |> Enum.each(fn game -> claim_and_resolve(game, resolver) end)

    :ok
  end

  defp claim_and_resolve(game, resolver) do
    case Scheduling.claim_turn(game) do
      {:ok, claimed} ->
        case resolver.resolve_turn(claimed) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "GlobalCombat.Games.TurnScheduler: resolver failed for game #{game.id}: #{inspect(reason)}"
            )
        end

      {:error, :already_claimed} ->
        :ok
    end
  end
end
