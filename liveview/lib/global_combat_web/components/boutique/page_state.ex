defmodule GlobalCombatWeb.Components.Boutique.PageState do
  @moduledoc """
  Async page-state trio + retry action — LiveView mirror of
  `components/react/PageState` (ported from robo-hub's PageStates.tsx).
  `error/1` carries `role="alert"`, `loading/1` carries `role="status"` (the
  source survey flagged Loading's silent-by-default gap; both announce
  here).
  """
  use Phoenix.Component
  alias GlobalCombatWeb.Components.Boutique.Button

  attr :label, :string, required: true, doc: "Required — no anonymous spinners (robo-hub rule)."

  def loading(assigns) do
    ~H"""
    <div
      role="status"
      class="flex flex-col items-center justify-center gap-[var(--space-3)] text-center text-text p-[var(--space-6)]"
    >
      <span
        aria-hidden="true"
        class="size-8 rounded-full border-2 border-border border-t-primary animate-spin"
      />
      <span class="text-text-muted">{@label}</span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :message, :string, required: true
  slot :actions, doc: "Recovery actions, typically <PageState.retry>."

  def error(assigns) do
    ~H"""
    <div
      role="alert"
      class="rounded-[var(--radius-md)] border border-danger bg-danger/10 p-[var(--space-5)] text-text"
    >
      <p class="font-semibold text-danger">{@title}</p>
      <div class="mt-[var(--space-2)] flex flex-col gap-[var(--space-4)]">
        <span>{@message}</span>
        <div :if={@actions != []} class="flex gap-[var(--space-3)]">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :icon, :string, default: nil, doc: "Decorative glyph in a soft badge; hidden from AT."
  slot :actions

  def empty(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center gap-[var(--space-3)] text-center text-text p-[var(--space-6)]">
      <span
        :if={@icon}
        aria-hidden="true"
        class="inline-flex items-center justify-center size-11 rounded-full bg-surface-muted text-warning"
      >
        <.icon name={@icon} class="size-5" />
      </span>
      <strong>{@title}</strong>
      <span class="text-text-muted max-w-[var(--size-content)]">{@message}</span>
      <div :if={@actions != []} class="flex gap-[var(--space-3)]">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :label, :string, default: "Retry"
  attr :rest, :global, include: ~w(phx-click phx-target phx-value-id)

  def retry(assigns) do
    ~H"""
    <Button.button intent="neutral" {@rest}>{@label}</Button.button>
    """
  end

  defp icon(assigns), do: GlobalCombatWeb.Components.Icon.icon(assigns)
end
