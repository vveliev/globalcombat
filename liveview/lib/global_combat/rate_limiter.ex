defmodule GlobalCombat.RateLimiter do
  @moduledoc """
  Tiny fixed-window attempt counter in ETS (single node). Keys are any term; counts live for
  one 15-minute window and a periodic sweep drops stale windows.

  shortcut: fixed window (up to 2x burst across a boundary) and node-local; upgrade if the app
  ever runs on more than one node.
  """

  use GenServer

  @table __MODULE__
  @window_ms :timer.minutes(15)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Whether `key` has fewer than `limit` recorded hits in the current window."
  def allow?(key, limit) do
    case :ets.lookup(@table, {key, bucket()}) do
      [{_, count}] -> count < limit
      [] -> true
    end
  end

  @doc "Records one hit against `key`."
  def hit(key) do
    :ets.update_counter(@table, {key, bucket()}, 1, {{key, bucket()}, 0})
    :ok
  end

  @doc "Forgets `key`'s hits (e.g. after a successful login)."
  def clear(key) do
    :ets.delete(@table, {key, bucket()})
    :ok
  end

  defp bucket, do: div(System.system_time(:millisecond), @window_ms)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    current = bucket()
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @window_ms)
end
