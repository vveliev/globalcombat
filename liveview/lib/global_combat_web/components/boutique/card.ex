defmodule GlobalCombatWeb.Components.Boutique.Card do
  @moduledoc """
  Compound page-content container — LiveView mirror of
  `components/react/Card` (pure tokens, no primitive base: a headed panel
  has no interaction to inherit). Sections are named slots
  (`:header`/`:inner_block`/`:footer`), the HEEx idiom for React's
  `Card.Header/Body/Footer` compound children.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil
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
      <div
        :if={@header != []}
        class="px-[var(--space-5)] py-[var(--space-4)] border-b border-border font-semibold"
      >
        {render_slot(@header)}
      </div>
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
