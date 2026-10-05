defmodule GlobalCombatWeb.GameLive.Board do
  @moduledoc """
  The in-play board `GameLive` renders into the board slot once the game has started: the
  game-over panel (once ended), the `WorldMap` figure with its winner caption, and the
  visually-hidden table that carries the same board state for assistive tech.

  Every map is a responsive SVG (`WorldMap`) — the legacy per-owner GIF sprites
  `Index.cshtml` composited at fixed pixel offsets are gone. The order panel, turn controls,
  region bonuses, your orders, turn results and Quit used to sit in a rail column beside the
  map here; stage mode (`docs/mobile-battle-mode.md` §4.3) moved them into the `:dock`/
  `:players` slots (`GameLive.Dock`, `GameLive.PlayersExtras`), so this is just the map and its
  accessible table now.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.GameLive.GameOver
  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.WorldMap

  import GlobalCombatWeb.GameLive.ViewHelpers, only: [my_player: 1]

  attr :game_id, :integer, required: true
  attr :view, :map, required: true

  attr :stage, :boolean,
    required: true,
    doc: """
    true exactly when this isn't the ended state: gives the figure a definite height to fill,
    so the map fills the stage's board area instead of sizing to its own aspect ratio
    (`.world-map` in `app.css` completes the height chain down to the `<svg>` below `lg:`)
    """

  attr :selected_area, :any, required: true
  attr :target_area, :any, required: true
  attr :lens, :atom, required: true
  attr :replay_steps, :list, required: true
  attr :winner, :map, default: nil
  attr :headline, :string, default: nil
  attr :outcome, :string, default: nil

  def board(assigns) do
    ~H"""
    <GameOver.game_over
      :if={@view.ended}
      view={@view}
      winner={@winner}
      headline={@headline}
      outcome={@outcome}
    />
    <figure class={["m-0 w-full", @stage && "h-full"]}>
      <WorldMap.world_map
        map_name={@view.map_name}
        areas={@view.areas}
        players={@view.players}
        selected_area={@selected_area}
        target_area={@target_area}
        lens={@lens}
        viewer_number={@view.viewer_number}
        interactive={!@view.ended}
        replay_steps={@replay_steps}
        game_id={@game_id}
        unassigned={Hud.gesture_pool(@view, my_player(@view))}
      />
      <figcaption
        :if={@view.ended && @winner}
        id="game-over-caption"
        class="mt-[var(--space-2)] text-[length:var(--text-sm)] text-text-muted"
      >
        {GameOver.winner_caption(@winner, length(@view.areas))}
      </figcaption>
    </figure>
    <.board_table areas={@view.areas} players={@view.players} />
    """
  end

  # Non-visual equivalent of the board (WCAG 1.3.1): the map conveys
  # territory/owner/army-count/adjacency through position and color, which is
  # meaningless to a screen reader in DOM order. This `sr-only` table (same
  # pattern as BarChart/LineChart's fallback table) carries the identical,
  # already fog-of-war-filtered `@view.areas` data as an ordered, navigable
  # structure instead — visually hidden, never `aria-hidden`, so assistive tech
  # can still read it.
  #
  # Owner text goes through `WorldMap.owner_text/2` — the same function that
  # words the vector board's territory labels — so a fog-hidden area reports
  # "hidden by fog of war" instead of "unclaimed" here exactly as it does there,
  # and the two can never drift apart. A screen reader user still gets exactly
  # what a sighted player sees, no more and no less.
  # Adjacency, unlike owner/armies, is static map topology every viewer already
  # sees rendered on the board regardless of fog, so it's listed in full.
  # The wrapping div, not the table, carries `sr-only`: a table's
  # auto layout algorithm ignores an explicit width smaller than its content's
  # min-content width, so `sr-only` directly on `<table>` still laid it out at
  # its full intrinsic width (measured 824px) and that box pushed the
  # document's scrollWidth even though it was visually hidden. A plain `div`
  # honors the explicit 1px width, and Tailwind's `sr-only` utility already
  # sets `overflow: hidden` (no separate class needed) to clip the oversized
  # table inside it, so nothing here contributes to page scroll. Verified with
  # this fix in place, via a real Chromium session (Playwright) against `mix
  # phx.server`, logged in and viewing both an active and a finished game:
  # `document.documentElement.scrollWidth == clientWidth` holds at 375px and
  # 768px (see game_live_test.exs for the DOM-shape assertion this backs).
  attr :areas, :list, required: true
  attr :players, :list, required: true

  defp board_table(assigns) do
    assigns =
      assigns
      |> assign(:area_names, Map.new(assigns.areas, &{&1.number, &1.name}))
      |> assign(:owner_names, WorldMap.owner_names(assigns.players))

    ~H"""
    <div class="sr-only">
      <table>
        <caption>Board state: territory, owner, armies, and adjacency</caption>
        <thead>
          <tr>
            <th scope="col">Territory</th>
            <th scope="col">Owner</th>
            <th scope="col">Armies</th>
            <th scope="col">Adjacent to</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={area <- @areas}>
            <th scope="row">{area.name}</th>
            <td>{WorldMap.owner_text(area, @owner_names)}</td>
            <td>{area.armies || "—"}</td>
            <td>{adjacent_names(area, @area_names)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp adjacent_names(area, area_names) do
    area.adjacent
    |> Enum.map(&Map.fetch!(area_names, &1))
    |> Enum.join(", ")
  end
end
