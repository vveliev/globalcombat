defmodule GlobalCombatWeb.Components.Boutique.StagePipeline do
  @moduledoc """
  Linear work-order stage list — LiveView mirror of
  `components/react/StagePipeline` (pure tokens, no Mishka primitive: an
  ordered status list has no interaction to inherit). Work orders move
  through a linear stage list — a stage cannot start before its
  predecessor — and some stages leave the building to an outsource vendor
  and come back. The operator's question is always the same: where is
  this, what is next, and is anything stuck.

  **Structure:** the React source is a single component over a
  `stages: Stage[]` data prop — not a compound `StagePipeline.Stage`, since
  every stage renders identically and there's nothing to compose. The most
  literal HEEx mirror keeps that shape: one `stage_pipeline/1` taking
  `stages` as a list of maps and mapping internally, exactly like this
  set's `timeline.ex` (its sibling — "StagePipeline is the process,
  Timeline is the calendar" per COMPONENTS.md) already does for its own
  `events` list.

  Rendered as an `<ol>` so the sequence survives without sight. Each
  stage's state is written out in words (mirrors the React source's
  `stateWord`: done -> "complete", current -> "in progress", pending ->
  "not started", blocked -> "blocked", outsourced -> "outsourced") rather
  than implied by colour alone; `aria-current="step"` marks the current
  stage for assistive tech. `elapsed`, when present, is a
  caller-preformatted cumulative-time string (e.g. "4h 20m"), same as the
  React side — no duration math happens here.
  """
  use Phoenix.Component

  attr :id, :any, default: nil
  attr :class, :any, default: nil

  attr :stages, :list,
    required: true,
    doc: ~s"""
    list of %{name: string, state: "done" | "current" | "pending" | "blocked" | "outsourced", elapsed: string | nil}
    """

  attr :label, :string,
    required: true,
    doc: ~s(Names the pipeline for assistive tech, e.g. "Work order WO-1183 stages".)

  attr :rest, :global

  def stage_pipeline(assigns) do
    ~H"""
    <ol
      id={@id}
      aria-label={@label}
      class={["m-0 flex list-none flex-wrap gap-[var(--space-2)] p-0", @class]}
      {@rest}
    >
      <li
        :for={{stage, i} <- Enum.with_index(@stages)}
        aria-current={if stage.state == "current", do: "step"}
        class={[
          "flex items-center gap-[var(--space-2)] rounded-[var(--radius-sm)] text-xs text-text",
          "px-[var(--space-3)] py-[var(--space-2)]",
          "border-t border-r border-b border-l-[length:var(--space-1)]",
          "border-t-border border-r-border border-b-border",
          state_accent(stage.state),
          if(stage.state == "current", do: "bg-surface-muted", else: "bg-surface")
        ]}
      >
        <span class="tabular-nums text-text-muted">{i + 1}</span>
        <span class={if stage.state == "current", do: "font-bold", else: "font-medium"}>
          {stage.name}
        </span>
        <span class="text-text-muted">· {state_word(stage.state)}</span>
        <span :if={stage[:elapsed]} class="tabular-nums text-text-muted">· {stage[:elapsed]}</span>
      </li>
    </ol>
    """
  end

  defp state_word("done"), do: "complete"
  defp state_word("current"), do: "in progress"
  defp state_word("pending"), do: "not started"
  defp state_word("blocked"), do: "blocked"
  defp state_word("outsourced"), do: "outsourced"

  defp state_accent("done"), do: "border-l-status-online"
  defp state_accent("current"), do: "border-l-info"
  defp state_accent("pending"), do: "border-l-status-unknown"
  defp state_accent("blocked"), do: "border-l-status-offline"
  defp state_accent("outsourced"), do: "border-l-status-partial"
end
