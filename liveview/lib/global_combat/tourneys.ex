defmodule GlobalCombat.Tourneys do
  @moduledoc """
  Read-only tourney lists for `HomeController.Index` (GIF-33) — ports the two inline queries in
  `Web/Controllers/HomeController.cs:25-29` (open tourneys) and `:42-50` (an account's recent
  tourneys). The tournament bracket itself is a separate, not-yet-scoped surface.
  """

  import Ecto.Query

  alias GlobalCombat.Repo
  alias GlobalCombat.Tourneys.{Tourney, TourneyPlayer}

  @doc "Ports `select * from tourney where status='New' order by id` — open tourneys to join."
  def list_open_tourneys do
    Repo.all(from t in Tourney, where: t.status == :new, order_by: [asc: t.id])
  end

  @doc """
  Ports the "Your Recent Tourneys" query (`select * from tourneyplayer, tourney where
  account_id = ? and id = tourney_id order by tourney_id desc limit 20`).
  """
  def list_recent_tourneys_for_account(account_id) do
    from(tp in TourneyPlayer,
      join: t in Tourney,
      on: t.id == tp.tourney_id,
      where: tp.account_id == ^account_id,
      order_by: [desc: t.id],
      limit: 20,
      select: t
    )
    |> Repo.all()
  end
end
