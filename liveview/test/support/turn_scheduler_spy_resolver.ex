defmodule GlobalCombat.Games.TurnScheduler.SpyResolver do
  @moduledoc """
  Test-only `GlobalCombat.Games.TurnScheduler.Resolver` — records `resolve_turn/1` calls by
  sending `{:resolved, game}` to whatever pid was `register/3`'d for that game's id, so async
  tests can assert on scheduler behavior without any shared, test-global process state (each
  game id -> pid mapping is independent, and MySQL `AUTO_INCREMENT` ids don't collide across
  concurrent sandboxed test transactions).
  """

  @behaviour GlobalCombat.Games.TurnScheduler.Resolver

  use Agent

  def start_link(_opts \\ []) do
    case Agent.start_link(fn -> %{} end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @doc "Registers `pid` to receive `{:resolved, game}` when `game_id` is resolved; `result` is what `resolve_turn/1` returns."
  def register(game_id, pid, result \\ :ok) do
    start_link()
    Agent.update(__MODULE__, &Map.put(&1, game_id, {pid, result}))
  end

  @impl true
  def resolve_turn(game) do
    start_link()

    case Agent.get(__MODULE__, &Map.get(&1, game.id)) do
      {pid, result} ->
        send(pid, {:resolved, game})
        result

      nil ->
        :ok
    end
  end
end
