defmodule GlobalCombatWeb.Components.Boutique.FeatureList do
  @moduledoc """
  LiveView mirror of `components/react/FeatureList` (claude-design landing
  grammar, pure tokens): numbered asymmetric rows — number/title/copy on
  one baseline — parted by fading structural rules. "No equal cards": the
  grammar is deliberately a list, not a card grid. Copy is measure-capped
  so long text stays readable.

  React's compound `FeatureList.Item` becomes two public function
  components here: `feature_list/1` (the `<div>` wrapper, taking a
  repeatable `:item` slot) and `feature_list_item/1` (one numbered row).
  React inserts the fading rule automatically between children via
  `Children.toArray`/`flatMap`; HEEx has no equivalent runtime child
  inspection, so `feature_list_item/1` owns its own *leading* rule instead,
  suppressed with a `first` attr that `feature_list/1` sets from the loop
  index — the same "expose what React cascades" move `table.ex` makes for
  `dense`. Calling `feature_list_item/1` directly (outside the wrapper)
  still renders its leading rule by default, which is the sane assumption
  for a row appended after others by hand.
  """
  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global

  slot :item, required: true do
    attr :index, :any, required: true, doc: ~s|Row number; numbers render zero-padded ("01").|
    attr :title, :any, required: true
  end

  def feature_list(assigns) do
    assigns = assign(assigns, :rows, Enum.with_index(assigns.item))

    ~H"""
    <div class={@class} {@rest}>
      <.feature_list_item
        :for={{item, i} <- @rows}
        index={item.index}
        title={item.title}
        first={i == 0}
      >
        {render_slot(item)}
      </.feature_list_item>
    </div>
    """
  end

  attr :index, :any, required: true, doc: ~s|Row number; numbers render zero-padded ("01").|
  attr :title, :any, required: true
  attr :first, :boolean, default: false, doc: "Suppresses the leading fading rule."
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def feature_list_item(assigns) do
    assigns = assign(assigns, :number, pad_index(assigns.index))

    ~H"""
    <hr
      :if={!@first}
      class="m-0 h-px border-0"
      style="background: linear-gradient(to right, transparent, var(--color-border) 3rem calc(100% - 3rem), transparent)"
    />
    <section
      class={[
        "grid grid-cols-[minmax(3rem,8rem)_minmax(0,26rem)_minmax(0,1fr)]",
        "gap-[var(--space-6)_clamp(1.5rem,4vw,4.5rem)] items-baseline py-[var(--space-9)]",
        @class
      ]}
      {@rest}
    >
      <p class="m-0 font-heading font-[var(--font-heading-weight)] text-[length:var(--text-sm)] text-primary tabular-nums">
        {@number}
      </p>
      <h3 class="m-0 font-heading font-[var(--font-heading-weight)] text-[length:var(--heading-4)] leading-[var(--heading-leading)] tracking-[var(--heading-tracking)]">
        {@title}
      </h3>
      <p class="m-0 text-[length:var(--font-body-size)] leading-[var(--font-body-leading)] text-text-muted max-w-[52ch]">
        {render_slot(@inner_block)}
      </p>
    </section>
    """
  end

  defp pad_index(index) when is_integer(index) do
    index |> Integer.to_string() |> String.pad_leading(2, "0")
  end

  defp pad_index(index), do: index
end
