defmodule GlobalCombatWeb.DesignSmokeLive do
  @moduledoc """
  Proof that the vendored design-boutique layer actually renders: the
  LiveView-first `GameLayout` shell filled with boutique components, drawing
  its colours from `assets/vendor/design-boutique/variables.css`.

  This is a bootstrap smoke page, not the game board. Delete it once a real
  board LiveView exists (GIF-30).
  """
  use GlobalCombatWeb, :live_view

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.Components.Boutique.Layouts.GameLayout
  alias GlobalCombatWeb.Components.Boutique.StatusPill

  @players [
    %{name: "Kaiser", armies: 27, tone: "active", state: "Orders in"},
    %{name: "Tsar", armies: 19, tone: "waiting", state: "Thinking"},
    %{name: "Entente", armies: 24, tone: "partial", state: "Partial orders"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Design smoke", players: @players, turn: 42)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <GameLayout.game_layout>
      <:status>
        <span class="font-semibold">Turn {@turn}</span>
        <StatusPill.status_pill tone="active">Resolving</StatusPill.status_pill>
        <span class="text-text-muted">Simultaneous turns · 5 minute limit</span>
      </:status>

      <:board>
        <Card.card>
          <:header>
            <h1 class="text-lg font-semibold">design-boutique renders here</h1>
          </:header>
          <p class="text-text-muted">
            Colours, spacing and type come from the vendored token layer. Switching
            <code>data-theme</code>
            on <code>&lt;html&gt;</code> recolours this page with no markup change.
          </p>
          <:footer>
            <Button.button intent="primary">End turn</Button.button>
            <Button.button intent="neutral">Save orders</Button.button>
          </:footer>
        </Card.card>
      </:board>

      <:players>
        <h2 class="mb-[var(--space-3)] text-sm font-semibold uppercase tracking-wide text-text-muted">
          Players
        </h2>
        <ul class="flex flex-col gap-[var(--space-3)]">
          <li :for={player <- @players} class="flex items-center justify-between gap-[var(--space-2)]">
            <span>{player.name}</span>
            <span class="flex items-center gap-[var(--space-2)]">
              <span class="text-text-muted">{player.armies}</span>
              <StatusPill.status_pill tone={player.tone}>{player.state}</StatusPill.status_pill>
            </span>
          </li>
        </ul>
      </:players>
    </GameLayout.game_layout>
    """
  end
end
