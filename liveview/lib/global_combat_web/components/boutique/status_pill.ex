defmodule GlobalCombatWeb.Components.Boutique.StatusPill do
  @moduledoc """
  LiveView mirror of `components/react/StatusPill` — the shared status
  vocabulary. An ERP carries a different status set per module (quotes,
  POs, work orders, packing slips each have their own words), and every
  module maps its words onto six lifecycle tones, which resolve to the
  audited status hues. The word is always rendered; hue is reinforcement,
  never the signal (WCAG 1.4.1), same principle as `badge.ex`'s `dot`
  variant — a pill stays legible in greyscale and to a colour-blind reader.

  Tone -> token mirrors the React source's `toneToken` map exactly. Five of
  the six tones resolve through the audited `status.*` five-hue system;
  `active` is the one exception — the source itself points it at
  `var(--color-info)`, the plain intent, not a status hue:

      new      -> status.unknown  (created, not yet acted on: New, Draft)
      active   -> info            (in its normal path: In production, Approved)
      waiting  -> status.warning  (waiting outside the room: Sent to vendor)
      partial  -> status.partial  (fulfilled in part: Back-ordered)
      blocked  -> status.offline  (stopped, needs intervention: Overdue)
      done     -> status.online   (terminal: Closed, Shipped, Paid)
  """
  use Phoenix.Component

  attr :tone, :string, values: ~w(new active waiting partial blocked done), required: true
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true, doc: "The module's own status word — required, the signal."

  def status_pill(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-[var(--space-2)] whitespace-nowrap",
        "rounded-[var(--radius-full)] border border-border bg-surface-muted",
        "px-[var(--space-3)] py-[var(--space-1)] text-xs leading-tight font-semibold text-text",
        @class
      ]}
      {@rest}
    >
      <span aria-hidden="true" class={["size-2 flex-none rounded-full", tone_dot(@tone)]} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp tone_dot("new"), do: "bg-status-unknown"
  defp tone_dot("active"), do: "bg-info"
  defp tone_dot("waiting"), do: "bg-status-warning"
  defp tone_dot("partial"), do: "bg-status-partial"
  defp tone_dot("blocked"), do: "bg-status-offline"
  defp tone_dot("done"), do: "bg-status-online"
end
