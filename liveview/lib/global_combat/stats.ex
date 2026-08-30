defmodule GlobalCombat.Stats do
  @moduledoc """
  Admin dashboard aggregates for `HomeController.stats` (GIF-33) — ports the scalar counts and
  daily series inlined in `Web/Controllers/HomeController.cs:Stats()` (lines 214-269).

  Read-only: the legacy page's `?ForceAll=1` link force-checks every running game for a stalled
  end-condition and mutates them (`GameServer.GetGame`/`ForceEndCheck`/`ForceEnd`/`SaveGame`) —
  that's live-game mutation, squarely the game board's territory (GIF-30), so this port drops
  the maintenance action and keeps the dashboard purely informational.
  """

  import Ecto.Query

  alias GlobalCombat.Accounts.{Account, AccountLogin}
  alias GlobalCombat.Games.Game
  alias GlobalCombat.Repo
  alias GlobalCombat.Tourneys.Tourney

  @doc """
  Returns the six scalar counts plus the last-30-days daily login/signup series, each as a
  list of `{Date.t(), integer()}` ordered oldest-first (ready for `Boutique.LineChart`'s
  `labels`/`points`, replacing the legacy page's hand-built Google Charts JS arrays — the
  `google.load('visualization', ...)` loader it used is a deprecated API Google no longer
  serves to new callers).
  """
  def overview do
    since_month = DateTime.utc_now() |> DateTime.add(-30, :day)
    since_day = DateTime.utc_now() |> DateTime.add(-1, :day)

    %{
      running_games: Repo.aggregate(from(g in Game, where: g.status == 1), :count),
      running_tourneys: Repo.aggregate(from(t in Tourney, where: t.status == :running), :count),
      accounts: Repo.aggregate(Account, :count),
      accounts_last_month:
        Repo.aggregate(from(a in Account, where: a.signed_up > ^since_month), :count),
      daily_active: Repo.aggregate(from(a in Account, where: a.last_on > ^since_day), :count),
      monthly_active: Repo.aggregate(from(a in Account, where: a.last_on > ^since_month), :count),
      daily_logins: daily_counts(AccountLogin, :logged_in_at, since_month),
      daily_signups: daily_counts(Account, :signed_up, since_month)
    }
  end

  defp daily_counts(schema, field, since) do
    schema
    |> where([r], field(r, ^field) > ^since)
    |> group_by([r], fragment("DATE(?)", field(r, ^field)))
    |> select([r], {fragment("DATE(?)", field(r, ^field)), count(r.id)})
    |> order_by([r], asc: fragment("DATE(?)", field(r, ^field)))
    |> Repo.all()
  end
end
