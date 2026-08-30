defmodule GlobalCombatWeb.TourneyController do
  @moduledoc """
  Port of `Web/Controllers/TourneyController.cs` and its views
  (`Web/Views/Tourney/{Index,Create,_Round}.cshtml`) -- see `GlobalCombat.Tourneys` for the
  rules this controller drives.
  """

  use GlobalCombatWeb, :controller

  alias GlobalCombat.Tourneys
  alias GlobalCombat.Tourneys.Tourney

  plug GlobalCombatWeb.Plugs.LegacyIntegerId when action in [:index, :join, :quit]

  @doc "Port of `TourneyController.Index`, including the admin-only StartTourney/KillTourney query-param actions."
  def index(conn, params) do
    case Tourneys.get_tourney(conn.assigns.legacy_id) do
      nil ->
        conn |> put_status(:not_found) |> text("Not Found")

      tourney ->
        admin? = admin?(conn)

        cond do
          admin? and not Tourney.started?(tourney) and Map.has_key?(params, "StartTourney") ->
            {:ok, tourney} = Tourneys.start_tournament(tourney)
            render_index(conn, tourney, "Tournament Started")

          admin? and Map.has_key?(params, "KillTourney") ->
            kill_tourney(tourney)
            redirect(conn, to: "/")

          true ->
            render_index(conn, tourney, nil)
        end
    end
  end

  defp kill_tourney(tourney) do
    alias GlobalCombat.Repo
    alias GlobalCombat.Tourneys.{TourneyGame, TourneyPlayer}
    import Ecto.Query

    Repo.delete_all(from tg in TourneyGame, where: tg.tourney_id == ^tourney.id)
    Repo.delete_all(from tp in TourneyPlayer, where: tp.tourney_id == ^tourney.id)
    Repo.delete(tourney)
  end

  @doc "Port of `TourneyController.Create()` (GET) -- renders the creation form; admin-only, same as the original."
  def new(conn, _params) do
    if admin?(conn) do
      render(conn, :new, changeset: Tourney.create_changeset(%Tourney{}, %{}))
    else
      redirect(conn, to: "/")
    end
  end

  @doc """
  Port of `TourneyController.Create(Tourney model)` (POST). The original re-renders the empty
  form in place with `ViewBag.ErrorMessage = "Tournament Created."`; this instead redirects
  straight to the new tournament's bracket page, which is more useful and needs no flash-
  across-redirect plumbing that isn't wired up elsewhere in this app yet.
  """
  def create(conn, %{"tourney" => tourney_params}) do
    if admin?(conn) do
      case Tourneys.create_tourney(tourney_params) do
        {:ok, tourney} ->
          redirect(conn, to: "/Tournament-#{tourney.id}")

        {:error, changeset} ->
          render(conn, :new, changeset: changeset)
      end
    else
      redirect(conn, to: "/")
    end
  end

  @doc "Port of `TourneyController.Join`."
  def join(conn, _params) do
    with %{} = account <- conn.assigns.current_account,
         tourney when not is_nil(tourney) <- Tourneys.get_tourney(conn.assigns.legacy_id) do
      message =
        case Tourneys.join_tournament(tourney, account.id) do
          {:ok, :joined} -> "You have joined this tournament."
          {:ok, :started} -> "Tournament Started"
          {:error, :full} -> "This tournament is full."
          {:error, :already_joined} -> "You've already joined this tournament."
          {:error, :already_started} -> "This tournament has already started."
        end

      render_index(conn, Tourneys.get_tourney!(tourney.id), message)
    else
      nil -> conn |> put_status(:not_found) |> text("Not Found")
      _ -> redirect(conn, to: "/")
    end
  end

  @doc "Port of `TourneyController.Quit`."
  def quit(conn, _params) do
    with %{} = account <- conn.assigns.current_account,
         tourney when not is_nil(tourney) <- Tourneys.get_tourney(conn.assigns.legacy_id) do
      message =
        case Tourneys.quit_tournament(tourney, account.id) do
          :ok -> "You quit this tournament."
          :noop -> nil
        end

      render_index(conn, Tourneys.get_tourney!(tourney.id), message)
    else
      nil -> conn |> put_status(:not_found) |> text("Not Found")
      _ -> redirect(conn, to: "/")
    end
  end

  # `message` mirrors `ViewBag.ErrorMessage` -- a per-response notice rendered inline in
  # `index.html.heex` (`Index.cshtml:11`), not session flash (there is nothing to persist
  # across a redirect; every original action that sets it also renders `Index` directly).
  defp render_index(conn, tourney, message) do
    render(conn, :index,
      tourney: tourney,
      message: message,
      bracket: Tourneys.bracket(tourney),
      players: Tourneys.players(tourney),
      tourney_games: Tourneys.tourney_games(tourney),
      current_players: Tourneys.current_players(tourney)
    )
  end

  defp admin?(conn), do: match?(%{admin: true}, conn.assigns[:current_account])
end
