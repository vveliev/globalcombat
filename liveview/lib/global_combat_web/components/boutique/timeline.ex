defmodule GlobalCombatWeb.Components.Boutique.Timeline do
  @moduledoc """
  Date-anchored milestone timeline — LiveView mirror of
  `components/react/Timeline` (pure tokens, no Mishka primitive: a
  connected-dot list has no interaction to inherit). Dots on a connecting
  rule, chronological. Distinct from StagePipeline (a *process* with
  per-stage states): Timeline records WHEN things happened/happen —
  milestones up to and including the `current` one render filled
  (history), later ones outlined (future). All milestones render filled
  when no event is marked current (a finished history). Horizontal,
  scrolls in place when cramped via `overflow-x-auto` (the `Table`
  convention in this set).
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil

  attr :events, :list,
    required: true,
    doc: "list of %{date: string, title: string, detail: string | nil, current: boolean | nil}"

  attr :label, :string, required: true, doc: "accessible name for the list"
  attr :rest, :global

  def timeline(assigns) do
    assigns = assign(assigns, :items, items(assigns.events))

    ~H"""
    <div id={@id} class={["overflow-x-auto", @class]} {@rest}>
      <ol aria-label={@label} class="m-0 flex min-w-min list-none p-0">
        <li
          :for={item <- @items}
          aria-current={if item.current, do: "step"}
          class="relative min-w-[9rem] flex-1"
        >
          <span
            :if={item.index > 0}
            aria-hidden="true"
            class={[
              "absolute right-1/2 top-[0.3125rem] h-[0.125rem] w-full",
              if(item.reached, do: "bg-primary", else: "bg-border")
            ]}
          />
          <span
            aria-hidden="true"
            class={[
              "relative mx-auto box-border block h-3 w-3 rounded-full border-2",
              if(item.reached, do: "border-primary bg-primary", else: "border-border bg-surface")
            ]}
          />
          <div class="px-[var(--space-2)] pt-[var(--space-2)] text-center">
            <div class="text-xs tabular-nums text-text-muted">{item.date}</div>
            <div class="text-sm font-semibold text-text">{item.title}</div>
            <div :if={item.detail} class="text-xs text-text-muted">{item.detail}</div>
          </div>
        </li>
      </ol>
    </div>
    """
  end

  defp items(events) do
    current_idx = Enum.find_index(events, &Map.get(&1, :current, false))

    events
    |> Enum.with_index()
    |> Enum.map(fn {e, i} ->
      reached = is_nil(current_idx) or i <= current_idx

      %{
        date: e.date,
        title: e.title,
        detail: Map.get(e, :detail),
        current: Map.get(e, :current, false),
        index: i,
        reached: reached
      }
    end)
  end
end
