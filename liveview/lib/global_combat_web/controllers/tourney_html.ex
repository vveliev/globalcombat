defmodule GlobalCombatWeb.TourneyHTML do
  @moduledoc "Views for `GlobalCombatWeb.TourneyController` -- port of `Web/Views/Tourney/*.cshtml`."

  use GlobalCombatWeb, :html

  alias GlobalCombat.Tourneys.Tourney

  embed_templates "tourney_html/*"

  @doc "Whether `account` is already signed up -- avoids a second DB round-trip for `Tourney.IsPlaying` since `@players` is already loaded."
  def playing?(_players, nil), do: false
  def playing?(players, account), do: Enum.any?(players, &(&1.id == account.id))

  @doc "Port of `Tourney/_Round.cshtml` -- one bracket round's column of games."
  attr :round, :any, required: true
  attr :tourney, :any, required: true
  attr :tourney_games, :list, required: true

  def bracket_round(assigns) do
    ~H"""
    <td class="align-middle whitespace-nowrap p-[var(--space-3)]">
      <b>Round {@round.number}</b><br />
      <span class="text-text-muted text-sm">
        {round_subtitle(@round)}
      </span>
      <div :for={game_number <- @round.start_game..(@round.start_game + @round.game_count - 1)}>
        <br />
        <div :if={not Tourney.started?(@tourney)}>
          Game {game_number}
          <br />
          <span :for={player_number <- 1..@round.game_size}>Player {player_number}<br /></span>
        </div>
        <div :if={Tourney.started?(@tourney)}>
          {round_game(assigns, game_number)}
        </div>
      </div>
    </td>
    """
  end

  defp round_subtitle(%{winners_of_round: 0, losers_of_round: 0}), do: "(Initial Players)"
  defp round_subtitle(%{winners_of_round: w, losers_of_round: 0}), do: "(Round #{w} Winners)"
  defp round_subtitle(%{winners_of_round: 0, losers_of_round: l}), do: "(Round #{l} Losers)"

  defp round_subtitle(%{winners_of_round: w, losers_of_round: l}) when l > 0,
    do: "(Round #{w} Winners & Round #{l} Losers)"

  defp round_subtitle(%{winners_of_round: w, losers_of_round: l}),
    do: "(Round #{w} Winners & Round #{-l} Winners)"

  defp round_game(assigns, game_number) do
    tourney_game = Enum.find(assigns.tourney_games, &(&1.game_num == game_number))

    assigns = assign(assigns, tourney_game: tourney_game, game_number: game_number)

    ~H"""
    <div :if={@tourney_game}>
      <.link href={"/Game-#{@tourney_game.game_id}"}>Game {@game_number}</.link>
      <br />
      <span :for={player <- @tourney_game.game.game_players}>
        &nbsp; {player_account(player).name}<br />
      </span>
    </div>
    """
  end

  defp player_account(%{account: %Ecto.Association.NotLoaded{}}), do: %{name: "?"}
  defp player_account(%{account: account}), do: account
end
