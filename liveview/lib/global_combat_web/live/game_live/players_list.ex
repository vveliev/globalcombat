defmodule GlobalCombatWeb.GameLive.PlayersList do
  @moduledoc """
  The roster at the top of the players drawer/rail — port of the legacy
  `Views/Game/_PlayerList.cshtml`. In the lobby and during play it lists every seat with its
  totals and Thinking/Done state (plus Kick for the lobby's host); once the game has ended it
  becomes the final standings.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.StatusPill
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [ordinal: 1]

  attr :players, :list, required: true
  attr :viewer_number, :any, required: true
  attr :status, :atom, required: true

  attr :ended, :boolean,
    default: false,
    doc: "swaps the Thinking/Done roster for final standings once the game has ended"

  attr :map_name, :atom,
    default: nil,
    doc: "the game's map, once known — in play each player's board colour gets a legend dot"

  # Once the game has ended the roster is the final standings, so it reads in
  # finishing order (legacy `_PlayerList.cshtml` sorts by `Place`) — seat
  # order otherwise. An eliminated player's totals are always "0 (0)" (the
  # engine zeroes them), never informative, so they are left off.
  def player_list(assigns) do
    assigns = assign(assigns, :players, roster_order(assigns.players, assigns.ended))

    ~H"""
    <ul id="player-list" aria-live="polite" class="flex flex-col gap-[var(--space-2)]">
      <li :for={p <- @players} class="flex items-center justify-between gap-[var(--space-2)]">
        <span class="flex min-w-0 items-center gap-[var(--space-2)]">
          <span
            :if={@map_name}
            class="world-map-swatch world-map-owner"
            data-owner={WorldMap.owner_slot(p.number)}
            aria-hidden="true"
          />
          <span class={["truncate", p.number == @viewer_number && "font-semibold"]}>{p.name}</span>
        </span>
        <span :if={@ended} class="flex items-center gap-[var(--space-2)]">
          <span :if={p.place == 1} aria-hidden="true">🏆</span>
          <span class="text-text-muted">{ordinal(p.place)}</span>
          <span :if={has_totals?(p)} class="text-text-muted">{p.armies} ({p.areas})</span>
          <span class="text-text-muted">Score {p.score}</span>
        </span>
        <span :if={!@ended} class="flex shrink-0 items-center gap-[var(--space-2)]">
          <span :if={!p.eliminated && p.armies} class="whitespace-nowrap tabular-nums text-text-muted">
            {p.armies} ({p.areas})
          </span>
          <span :if={p.eliminated} class="text-text-muted">{ordinal(p.place)}</span>
          <StatusPill.status_pill :if={!p.eliminated} tone={if p.done, do: "done", else: "waiting"}>
            {if p.done, do: "Done", else: "Thinking"}
          </StatusPill.status_pill>
          <Button.button
            :if={@status == :lobby and @viewer_number == 1 and p.number != @viewer_number}
            intent="neutral"
            phx-click="kick"
            phx-value-player_number={p.number}
          >
            Kick
          </Button.button>
        </span>
      </li>
    </ul>
    """
  end

  # Unplaced seats (place 0) sort last, after every finisher.
  defp roster_order(players, true), do: Enum.sort_by(players, &{&1.place == 0, &1.place})
  defp roster_order(players, false), do: players

  defp has_totals?(player), do: (player.armies || 0) > 0 or (player.areas || 0) > 0
end
