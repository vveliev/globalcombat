defmodule GlobalCombatWeb.Components.Boutique.Modal do
  @moduledoc """
  Dialog wrapper — LiveView mirror of `components/react/Modal` (itself a
  thin wrap of Mantine `Modal` inheriting the shared theme's a11y defaults:
  labelled close button, non-banner header — CLAUDE.md provenance notes).

  Rather than hand-roll focus-trap + escape/click-away handling, this wraps
  the already-generated Mishka Chelekom primitive
  `GlobalCombatWeb.Components.Modal` (`modal/1`, plus its `show_modal/1,2`
  and `hide_modal/1,2` JS-command helpers, delegated below). That vendor
  file is generated and out of scope for this port — only this file and
  `confirm_destructive.ex` are ours to edit — so we leave its `color`/
  `variant`/`border` attrs at their defaults (they resolve to inert class
  names since we never import `assets/vendor/mishka_chelekom.css`) and
  supply our own token-driven `class`/`*_class` overrides for the parts
  that actually paint: panel surface, border, radius, shadow, text, and the
  close button. `rounded="none"` silences the vendor's own literal
  `rounded` utility so only our `var(--radius-md)` class applies.

  The vendor template originally hardcoded `bg-zinc-50/90 dark:bg-zinc-600/90`
  on the overlay div *alongside* whatever `overlay_class` we pass (it was
  concatenated, not replaced) — unlike Mishka's other inert `-light`/`-dark`
  color classes, `zinc-*` is a real Tailwind default-palette color, so it
  would have actually painted. Fixed at the source (the one line in the
  vendored file, not a full restyle) so only our `overlay_class` applies.
  We set `overlay_class` to `bg-black/50` — no semantic "overlay" token
  exists yet, so this is the same stock-Tailwind carve-out as the danger
  button's `bg-red-600`) so the intended look is token-anchored on our side.

  State ownership: open/close is DOM/JS-driven, not assign-driven. Render
  with `show={false}` (the default) and trigger `show_modal(id)` /
  `hide_modal(id)` from `phx-click` on trigger elements — no LiveView
  assign round-trip is needed just to open or close a dialog.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  alias GlobalCombatWeb.Components.Modal, as: Primitive

  attr :id, :string,
    required: true,
    doc: "Also the DOM id show_modal/1,2 and hide_modal/1,2 target."

  attr :title, :string, default: nil

  attr :show, :boolean,
    default: false,
    doc: "Visible on initial render; toggle afterward via show_modal/hide_modal, not this assign."

  attr :on_cancel, JS,
    default: %JS{},
    doc: "Runs on close-button click, Escape, and click-away, composed with the built-in hide."

  attr :size, :string, values: ~w(sm md lg xl), default: "md"
  attr :class, :any, default: nil

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <Primitive.modal
      id={@id}
      title={@title}
      show={@show}
      on_cancel={@on_cancel}
      rounded="none"
      size={primitive_size(@size)}
      class={@class}
      title_class="text-lg font-semibold text-text"
      content_class="text-text"
      close_class="text-text-muted hover:text-text"
      overlay_class="bg-black/50"
      focus_wrap_class="bg-surface border-border rounded-[var(--radius-md)] shadow-lg"
    >
      {render_slot(@inner_block)}
    </Primitive.modal>
    """
  end

  @doc "Delegates to the underlying primitive's show JS command."
  def show_modal(js \\ %JS{}, id), do: Primitive.show_modal(js, id)

  @doc "Delegates to the underlying primitive's hide JS command."
  def hide_modal(js \\ %JS{}, id), do: Primitive.hide_modal(js, id)

  defp primitive_size("sm"), do: "small"
  defp primitive_size("md"), do: "medium"
  defp primitive_size("lg"), do: "large"
  defp primitive_size("xl"), do: "extra_large"
end
