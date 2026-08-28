defmodule GlobalCombatWeb.Components.Boutique.Tabs do
  @moduledoc """
  Section switcher — LiveView mirror of `components/react/Tabs` (Mantine
  `Tabs` wrapped with `variant="pills"`, `keepMounted={false}`).

  Mantine's `Tabs` owns "which tab is active" as internal component state
  (`defaultValue`/`value`/`onChange`). A stateless `Phoenix.Component` has
  nowhere to hold that — so here the calling LiveView owns it instead: keep
  the selected tab's id in an assign (e.g. `@active_tab`) and pass it into
  every `tab/1` and `tab_panel/1` as `active`. Wire `tab/1`'s `rest` to
  whatever switch scheme fits the page — `phx-click`+`phx-value-id` into a
  `handle_event` that updates the assign, or `patch` via `push_patch` for a
  URL-addressable tab. This is the standard Phoenix pattern for
  interactive-but-stateless components: the component renders, the LiveView
  decides.

  `keepMounted=false` (this port's only default, matching robo-hub's
  SettingsPage usage) is implemented literally: `tab_panel/1` puts
  `:if={@active == @id}` on its own root element, so an inactive panel's
  slot is never rendered into HTML at all — the direct HEEx equivalent of
  React unmounting the panel.

  No top-level `tabs/1` wrapper: Mantine's `<Tabs>` exists to host the
  provider that threads state to its compound children, which isn't needed
  here since `active` is passed explicitly. `tab_list/1` renders the
  pill-track container directly.
  """
  use Phoenix.Component

  attr :label, :string, default: nil, doc: "aria-label for the tablist; mirrors Tabs.List's."
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true, doc: "One or more <Tabs.tab> triggers."

  def tab_list(assigns) do
    ~H"""
    <div
      role="tablist"
      aria-label={@label}
      class={[
        "inline-flex gap-[var(--space-1)] p-[var(--space-1)] bg-surface-muted rounded-[var(--radius-full)]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :any, required: true, doc: "This tab's identifier — matched against `active`."

  attr :active, :any,
    required: true,
    doc: "The currently selected tab id, owned by the calling LiveView."

  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-value-id phx-value-tab),
    doc: "Wire the tab switch: phx-click/phx-value-* into handle_event, or a patch scheme."

  slot :inner_block, required: true

  def tab(assigns) do
    ~H"""
    <button
      type="button"
      role="tab"
      id={"tab-#{@id}"}
      aria-selected={to_string(@active == @id)}
      aria-controls={"panel-#{@id}"}
      class={[
        "px-[var(--space-3)] py-[var(--space-1)] text-sm font-medium rounded-[var(--radius-full)]",
        "transition-colors",
        "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
        if(@active == @id,
          do: "bg-primary text-primary-contrast",
          else: "text-text-muted hover:text-text hover:bg-surface-muted"
        ),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :id, :any, required: true, doc: "Must match the id of the <Tabs.tab> it belongs to."

  attr :active, :any,
    required: true,
    doc: "The currently selected tab id — this panel only renders when it matches."

  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def tab_panel(assigns) do
    ~H"""
    <div
      :if={@active == @id}
      id={"panel-#{@id}"}
      role="tabpanel"
      aria-labelledby={"tab-#{@id}"}
      class={["p-[var(--space-4)]", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
