defmodule GlobalCombatWeb.Components.Boutique.SegmentedControl do
  @moduledoc """
  Exclusive option switcher — LiveView mirror of
  `components/react/SegmentedControl` (a thin wrap of Mantine
  `SegmentedControl`), ported from the claude-design systems' `.seg` control
  (`data/*/components/forms.html`). Renders one native `<input
  type="radio">` per option, visually hidden and paired with a sibling
  `<label>` styled via the CSS `peer` pattern so the group reads as a
  pill-shaped track with one active segment lifted off it — while behaving
  like a real radio group (full keyboard/AT semantics inherited from the
  native inputs, same reasoning as `Radio`). The container carries
  `role="radiogroup"` + `aria-label` directly (mirroring how the React side
  passes `aria-label` straight through to Mantine's own `role="radiogroup"`
  root) rather than a `<fieldset>`/`<legend>` pair, so the accessible name is
  never left to browser-specific name-from-content behavior — the required
  group label is non-negotiable (robo-hub's QualitySelector shipped without
  one; don't repeat that gap).

  Use it for 2-5 short exclusive options a user flips between in place; for
  a section switcher with panels use Tabs, and for stacked labelled choices
  use Radio.Group.
  """
  use Phoenix.Component

  attr :name, :any, required: true
  attr :value, :any, default: nil
  attr :label, :string, required: true, doc: "accessible name for the group (role=radiogroup)"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :option, required: true do
    attr :value, :any, required: true
  end

  def segmented_control(assigns) do
    ~H"""
    <div
      role="radiogroup"
      aria-label={@label}
      class={[
        "inline-flex p-[var(--space-1)] bg-surface-muted rounded-[var(--radius-full)] gap-[var(--space-1)]",
        @class
      ]}
      {@rest}
    >
      <div :for={opt <- @option} class="contents">
        <input
          type="radio"
          id={"#{@name}-#{opt.value}"}
          name={@name}
          value={opt.value}
          checked={to_string(opt.value) == to_string(@value)}
          class="peer sr-only"
        />
        <label
          for={"#{@name}-#{opt.value}"}
          class={[
            "px-[var(--space-3)] py-[var(--space-1)] rounded-[var(--radius-full)]",
            "text-sm text-text-muted cursor-pointer transition-colors",
            "peer-checked:bg-surface peer-checked:text-text peer-checked:shadow-sm",
            "peer-focus-visible:outline peer-focus-visible:outline-2",
            "peer-focus-visible:outline-offset-2 peer-focus-visible:outline-focus-ring"
          ]}
        >
          {render_slot(opt)}
        </label>
      </div>
    </div>
    """
  end
end
