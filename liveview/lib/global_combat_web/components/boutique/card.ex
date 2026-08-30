defmodule GlobalCombatWeb.Components.Boutique.Card do
  @moduledoc """
  Compound page-content container — LiveView mirror of
  `components/react/Card` (pure tokens, no primitive base: a headed panel
  has no interaction to inherit). Sections are named slots
  (`:header`/`:inner_block`/`:footer`), the HEEx idiom for React's
  `Card.Header/Body/Footer` compound children.

  `:header` renders as a real heading element (`heading_level`, default
  `h2`) rather than a styled `<div>` — Card is the primary section-title
  mechanism across the Home/Stats/Messages/PlayerInfo/IpAddresses/OptOut
  surfaces (GIF-33), so a styled div there left those pages with no
  heading structure for screen-reader users to navigate by (WCAG 1.3.1,
  2.4.6; GIF-86). Callers nesting a Card inside another heading's section
  should raise `heading_level` to keep the page's heading order sequential.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
  attr :heading_level, :string, values: ~w(h1 h2 h3 h4 h5 h6), default: "h2"
  attr :rest, :global

  slot :header
  slot :inner_block
  slot :footer

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "bg-surface border border-border rounded-[var(--radius-md)] shadow-md text-text overflow-hidden",
        @class
      ]}
      {@rest}
    >
      <.dynamic_tag
        :if={@header != []}
        tag_name={@heading_level}
        class="px-[var(--space-5)] py-[var(--space-4)] border-b border-border font-semibold"
      >
        {render_slot(@header)}
      </.dynamic_tag>
      <div :if={@inner_block != []} class="p-[var(--space-5)]">
        {render_slot(@inner_block)}
      </div>
      <div
        :if={@footer != []}
        class="px-[var(--space-5)] py-[var(--space-4)] border-t border-border text-text-muted"
      >
        {render_slot(@footer)}
      </div>
    </section>
    """
  end
end
