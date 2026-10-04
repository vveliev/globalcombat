defmodule GlobalCombatWeb.GameLive.GameOver do
  @moduledoc """
  The finished-game screen: who won, how the viewer placed, the final standings and a next
  action — plus the outcome wording (`outcome/1`, `winner_caption/2`) the status strip and the
  board caption reuse so all three always describe the same result.

  `engine.ended` is an explicit state instead of a live turn stuck on "Waiting on other
  players… [Force Turn]" with the outcome buried as a small "place 1" in the roster.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Kicker
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [my_player: 1, ordinal: 1]

  @doc """
  The viewer's outcome for a playing game, as assigns: `:winner` (the place-1 player, or
  `nil`), `:viewer_role` (`:winner`, `:loser` or `:spectator`), `:headline` and `:outcome`
  (the viewer's own line, `nil` for a spectator).

  `GameLive` computes this once per render and threads it to both the status strip's
  game-over announcement and `game_over/1`, so neither recomputes it.
  """
  def outcome(view) do
    winner = find_winner(view.players)
    me = my_player(view)
    role = viewer_role(view, winner, me)

    [
      winner: winner,
      viewer_role: role,
      headline: headline(role, winner),
      outcome: viewer_outcome(role, me, length(view.players))
    ]
  end

  # That state carries the weight the finale of the game deserves: a headline the size of
  # a real heading (not `text-lg`), the board's own owner colour bleeding into the panel instead
  # of a neutral `border-divider` box, full per-player final stats (not just a placing number —
  # `PlayersList`'s roster hides armies/areas the instant `place > 0`, which is every seated
  # player once the game has ended, winner included), and a primary next action (`Play again`)
  # instead of leaving Send in chat as the only `intent="primary"` button on the page.
  #
  # `role="status"`/`aria-live="polite"` never fired here — this section exists at first render
  # for anyone loading an already-finished game, and a live region only announces *changes*
  # after mount. `aria-labelledby` gives it a name for landmark navigation without pretending to
  # announce a mutation that already happened by the time the socket connects; the status
  # strip's `#game-over-announce` (inside `GameLayout`'s already-`aria-live="polite"` status
  # strip) covers the live-flip case for a player connected when the game ends.
  attr :view, :map, required: true
  attr :winner, :map, required: true
  attr :headline, :string, required: true
  attr :outcome, :string, default: nil

  def game_over(assigns) do
    standings = assigns.view.players |> Enum.filter(&(&1.place > 0)) |> Enum.sort_by(& &1.place)
    assigns = assign(assigns, :standings, standings)

    ~H"""
    <section
      id="game-over"
      aria-labelledby="game-over-heading"
      class="world-map-owner mb-[var(--space-4)] flex flex-col gap-[var(--space-3)] rounded-[var(--radius-md)] border border-divider border-l-4 border-l-[color:var(--map-owner-fill,var(--map-owner-0))] bg-surface p-[var(--space-5)]"
      data-owner={@winner && WorldMap.owner_slot(@winner.number)}
    >
      <Kicker.kicker>Game Over · Turn {@view.turn}</Kicker.kicker>

      <h2
        id="game-over-heading"
        class="m-0 font-heading font-[var(--font-heading-weight)] text-[length:var(--heading-2)] leading-[var(--heading-leading)] tracking-[var(--heading-tracking)] text-text"
      >
        {@headline}
      </h2>

      <p :if={@outcome} id="game-over-outcome" class="m-0 text-text">{@outcome}</p>

      <ol
        :if={@standings != []}
        id="game-over-standings"
        class="mt-[var(--space-2)] flex flex-col gap-[var(--space-2)]"
      >
        <li
          :for={p <- @standings}
          class="flex items-center justify-between gap-[var(--space-4)] text-[length:var(--text-sm)]"
        >
          <span class="flex items-center gap-[var(--space-2)]">
            <span
              class="world-map-swatch world-map-owner"
              data-owner={WorldMap.owner_slot(p.number)}
              aria-hidden="true"
            />
            <span class={p.place == 1 && "font-semibold"}>{p.place}. {p.name}</span>
          </span>
          <span :if={p.place == 1} class="text-text-muted">
            {p.armies} armies · {p.areas} territories
          </span>
        </li>
      </ol>

      <div class="mt-[var(--space-2)] flex flex-wrap gap-[var(--space-3)]">
        <Button.button id="game-over-play-again" intent="primary" navigate={~p"/Create-Game"}>
          Play again
        </Button.button>
        <Button.button id="game-over-home" intent="neutral" navigate={~p"/"}>
          Back to Home
        </Button.button>
      </div>
    </section>
    """
  end

  @doc """
  The board caption under a finished game's map.

  A game can also end by every other seat quitting/being eliminated one at a time
  (`Engine.eliminate_player/2` zeroes `areas`/`armies` on elimination) rather than the winner
  capturing the whole board, so the winner's own `areas` can be less than the board's total —
  "all" is only accurate when the two happen to match.
  """
  def winner_caption(winner, total_areas) when winner.areas == total_areas,
    do: "#{winner.name} holds all #{total_areas} territories."

  def winner_caption(winner, total_areas),
    do: "#{winner.name} holds #{winner.areas} of #{total_areas} territories."

  defp find_winner(players), do: Enum.find(players, &(&1.place == 1))

  # :winner/:loser require a seat (`my_player/1`); anyone else — logged out, or logged in but
  # never joined this game — is a :spectator, same viewer `GameLive` already treats as one
  # everywhere else (`viewer_number: nil`).
  defp viewer_role(view, winner, me) do
    cond do
      winner && winner.number == view.viewer_number -> :winner
      me -> :loser
      true -> :spectator
    end
  end

  defp headline(:winner, _winner), do: "Victory"
  defp headline(:loser, _winner), do: "Defeat"
  defp headline(:spectator, nil), do: "Game Over"
  defp headline(:spectator, winner), do: "#{winner.name} wins"

  # The viewer's own line under the headline; `nil` for a spectator.
  defp viewer_outcome(:winner, _me, _total), do: "You won."
  defp viewer_outcome(:loser, me, total), do: "You placed #{ordinal(me.place)} of #{total}."
  defp viewer_outcome(:spectator, _me, _total), do: nil
end
