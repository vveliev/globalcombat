defmodule GlobalCombatWeb.Components.Boutique.StatCard do
  @moduledoc """
  KPI tile — LiveView mirror of `components/react/StatCard`, itself
  generalized from robo-hub's `FleetStatCard.tsx` (see
  `components/COMPONENT-MAP.md`). Eyebrow label, big value, optional
  detail/hint lines, an optional labelled progress meter, and an optional
  click-through.

  `interactive` is an explicit boolean the caller sets — never inferred
  from a `phx-click` turning up in `rest` — so a static tile can never end
  up with click semantics bolted onto a `<div>` by accident. Setting it
  renders a real `<button type="button">` via `Phoenix.Component.
  dynamic_tag/1`, matching the React side's real `<button>` (Mantine
  `UnstyledButton`) instead of a div with an onClick handler.

  `tone` resolves through the theme's semantic intents and shows through
  the eyebrow dot, the progress meter's accent color, and the trailing
  action label — never through the eyebrow text itself (matches the React
  source's actual placement). Every progress meter carries an
  `aria-label` (defaulting to `eyebrow` when `progress_label` is omitted)
  — no anonymous meters, per the robo-hub rule in COMPONENT-MAP.md.
  """
  use Phoenix.Component
  import GlobalCombatWeb.Components.Icon, only: [icon: 1]

  attr :id, :any, default: nil
  attr :eyebrow, :string, required: true, doc: ~s[Label above the value, e.g. "Offline now".]

  attr :value, :string,
    required: true,
    doc: ~s[The headline figure, preformatted ("12", "97.4%").]

  attr :detail, :string, default: nil, doc: "One supporting line under the value."
  attr :hint, :string, default: nil, doc: "Smaller muted hint under the detail line."

  attr :progress, :integer,
    default: nil,
    doc: "0-100; renders a labelled meter tinted by tone."

  attr :progress_label, :string,
    default: nil,
    doc: "Progress meter's aria-label; defaults to eyebrow — meters are never anonymous."

  attr :icon, :string, default: nil, doc: "Decorative leading glyph name; hidden from AT."
  attr :tone, :string, values: ~w(primary success warning danger), default: "primary"

  attr :interactive, :boolean,
    default: false,
    doc:
      "Renders a real <button type=\"button\"> instead of a <div>. Set explicitly by the " <>
        "caller — never inferred from rest."

  attr :action_label, :string,
    default: nil,
    doc: ~s[Trailing action hint shown when interactive, e.g. "View list".]

  attr :aria_label, :string,
    default: nil,
    doc: ~s[Accessible name override for the interactive button; defaults to "eyebrow: value".]

  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target)

  def stat_card(assigns) do
    # `type` isn't part of dynamic_tag/1's default global-attr allowlist (it's
    # element-specific, not a universal HTML global), so it can't be passed as
    # a plain attr like `id`/`class`/`aria-label` without tripping the
    # compile-time "undefined attribute" check — spread it in via `rest`-style
    # map instead, same trick as `{@rest}` below.
    assigns =
      assign(assigns, :button_attrs, if(assigns.interactive, do: %{type: "button"}, else: %{}))

    ~H"""
    <.dynamic_tag
      tag_name={if @interactive, do: "button", else: "div"}
      id={@id}
      aria-label={if @interactive, do: @aria_label || "#{@eyebrow}: #{@value}"}
      {@button_attrs}
      class={[
        "bg-surface border border-border rounded-[var(--radius-md)] shadow-sm text-text",
        "p-[var(--space-5)]",
        @interactive &&
          [
            "block w-full text-left cursor-pointer hover:opacity-90 transition-opacity",
            "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
          ],
        @class
      ]}
      {@rest}
    >
      <div class="flex items-center gap-[var(--space-2)] text-xs font-semibold uppercase tracking-wide text-text-muted">
        <span aria-hidden="true" class={["inline-block size-2 rounded-full", tone_dot(@tone)]} />
        <span :if={@icon} aria-hidden="true"><.icon name={@icon} class="size-4" /></span>
        <span>{@eyebrow}</span>
      </div>

      <div class="mt-[var(--space-2)] text-2xl font-semibold tabular-nums">{@value}</div>

      <div :if={@detail} class="mt-[var(--space-1)] text-sm text-text-muted">{@detail}</div>
      <div :if={@hint} class="mt-[var(--space-1)] text-sm text-text-muted">{@hint}</div>

      <progress
        :if={@progress}
        value={@progress}
        max="100"
        aria-label={@progress_label || @eyebrow}
        class={["mt-[var(--space-3)] block w-full h-2", tone_accent(@tone)]}
      />

      <div
        :if={@interactive && @action_label}
        class={[
          "mt-[var(--space-3)] text-xs font-semibold uppercase tracking-wide",
          tone_text(@tone)
        ]}
      >
        {@action_label}
      </div>
    </.dynamic_tag>
    """
  end

  defp tone_dot("primary"), do: "bg-primary"
  defp tone_dot("success"), do: "bg-success"
  defp tone_dot("warning"), do: "bg-warning"
  defp tone_dot("danger"), do: "bg-danger"

  defp tone_text("primary"), do: "text-primary"
  defp tone_text("success"), do: "text-success"
  defp tone_text("warning"), do: "text-warning"
  defp tone_text("danger"), do: "text-danger"

  defp tone_accent("primary"), do: "accent-[var(--color-primary)]"
  defp tone_accent("success"), do: "accent-[var(--color-success)]"
  defp tone_accent("warning"), do: "accent-[var(--color-warning)]"
  defp tone_accent("danger"), do: "accent-[var(--color-danger)]"
end
