defmodule GlobalCombatWeb.GameLive.TurnResults do
  @moduledoc """
  The last resolved turn, told twice: as a client-side replay (`turn_replay_controls/1` in the
  status strip, driven by the `.TurnReplay` hook) and as an always-present, accessible list of
  the same steps (`turn_results/1` in the players drawer, kept in step by `.TurnResultsList`).

  Both read the steps `GameLive.Replay.steps/4` builds once per render, already fog-filtered.
  The two hooks never call each other: `.TurnReplay` broadcasts where the replay is as a
  `gc:replay` window event, and the list (and `WorldMap`'s `.MapReplay` on the board) apply it
  to their own markup.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card

  # Play/back/forward for the last-turn replay, plus the live-region
  # announcement span the `.TurnReplay` hook narrates each step into (picked up by
  # `GameLayout`'s already-`aria-live="polite"` `:status` section — see that
  # module's moduledoc). The wrapper itself renders every turn regardless of
  # whether there's anything to replay, and only its *contents* are conditional —
  # `data-turn` has to change on an element the hook stays mounted on the whole
  # time for `updated/0` to reliably tell "a new turn resolved" from "this turn
  # simply had no visible events", including the very next turn that does.
  # Stepping/announcing here is otherwise plain client-side JS (no phx-click):
  # "the hook owns the timing", not the server.
  attr :turn, :integer, required: true, doc: "the current turn, `@view.turn`"
  attr :steps, :list, required: true

  def turn_replay_controls(assigns) do
    assigns = assign(assigns, :steps_json, Jason.encode!(assigns.steps))

    ~H"""
    <div
      id="turn-replay-controls"
      phx-hook=".TurnReplay"
      data-turn={@turn}
      data-steps={@steps_json}
      class="flex items-center gap-[var(--space-2)]"
    >
      <span :if={@steps != []} class="flex items-center gap-[var(--space-2)]">
        <Button.button id="turn-replay-play" type="button" data-replay-play>
          Turn {resolved_turn(@turn)} results ▶
        </Button.button>
        <Button.button id="turn-replay-back" type="button" intent="neutral" data-replay-back>
          ◀ Step
        </Button.button>
        <Button.button id="turn-replay-forward" type="button" intent="neutral" data-replay-forward>
          Step ▶
        </Button.button>
      </span>
      <span id="turn-replay-announce" class="sr-only"></span>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TurnReplay">
      // Replays the last resolved turn from the JSON payload LiveView
      // put in `data-steps` (`GameLive.Replay.steps/4`, already fog-filtered) —
      // every play/step/back afterwards is pure client-side timing, no
      // `pushEvent` round trip ("the hook owns the timing"). Mounted on a
      // wrapper that renders every turn regardless of whether there's anything
      // to replay, so `updated()` reliably fires exactly once per resolved
      // turn (comparing `data-turn`) whether or not the *previous* turn had
      // any visible events of its own.
      //
      // This hook only owns its own buttons and announcement. Where the
      // replay is goes out as a `gc:replay` window event
      // (`{current, animate, counts}`); the board (`WorldMap`'s
      // `.MapReplay`) and the results list (`.TurnResultsList`) each apply
      // it to their own markup and re-apply it after LiveView patches them.
      // `gc:replay-sync` asks for a resend (a listener mounting late).
      //
      // Delegates clicks from the wrapper rather than binding the buttons
      // directly: the buttons themselves come and go (rendered only when
      // `@steps != []`), but this element's `id` never does, so LiveView
      // never remounts the hook — only a plain `updated()` patch.
      export default {
        mounted() {
          this.current = -1
          this.timer = null
          this.seenTurn = this.el.dataset.turn
          this.el.addEventListener("click", (e) => this.onClick(e))
          this.onSync = () => this.broadcast()
          window.addEventListener("gc:replay-sync", this.onSync)
          this.render()
        },

        updated() {
          const turn = this.el.dataset.turn
          const isNewTurn = turn !== this.seenTurn
          this.seenTurn = turn

          if (!isNewTurn) {
            // Some *other* part of this LiveView patched (a chat message, a
            // player's status pill) and happened to touch this subtree —
            // must not wipe a viewer's in-progress replay position.
            this.render()
            return
          }

          this.stop()
          this.current = -1

          if (!this.reducedMotion() && this.steps().length > 0) {
            this.play()
          } else {
            this.render()
          }
        },

        destroyed() {
          this.stop()
          window.removeEventListener("gc:replay-sync", this.onSync)
        },

        onClick(e) {
          if (e.target.closest("[data-replay-play]")) this.play()
          else if (e.target.closest("[data-replay-back]")) { this.stop(); this.show(this.current - 1) }
          else if (e.target.closest("[data-replay-forward]")) { this.stop(); this.show(this.current + 1) }
        },

        steps() {
          return JSON.parse(this.el.dataset.steps)
        },

        reducedMotion() {
          return window.matchMedia("(prefers-reduced-motion: reduce)").matches
        },

        play() {
          this.stop()
          this.show(-1)
          this.timer = setInterval(() => {
            if (this.current >= this.steps().length - 1) { this.stop(); return }
            this.show(this.current + 1)
          }, 900)
        },

        stop() {
          if (this.timer) clearInterval(this.timer)
          this.timer = null
        },

        show(index) {
          const steps = this.steps()
          this.current = Math.max(-1, Math.min(index, steps.length - 1))
          this.render()
        },

        // The running army count of every area touched up to the current
        // step; areas no step has touched yet keep their live count.
        counts(steps) {
          const counts = {}
          for (let i = 0; i <= this.current; i++) {
            (steps[i]?.counts || []).forEach(({area, value}) => { counts[area] = value })
          }
          return counts
        },

        broadcast() {
          const detail = {
            current: this.current,
            animate: !this.reducedMotion(),
            counts: this.counts(this.steps())
          }
          window.dispatchEvent(new CustomEvent("gc:replay", { detail }))
        },

        render() {
          const steps = this.steps()
          this.broadcast()

          const announce = document.getElementById("turn-replay-announce")
          if (announce) announce.textContent = this.current >= 0 ? (steps[this.current]?.text || "") : ""

          const back = this.el.querySelector("[data-replay-back]")
          const forward = this.el.querySelector("[data-replay-forward]")
          if (back) back.disabled = this.current <= -1
          if (forward) forward.disabled = this.current >= steps.length - 1
        }
      }
    </script>
    """
  end

  # The accessible equivalent of the board's replay arrows/counts — every
  # `GameLive.Replay.steps/4` line as ordinary, always-present text next to the
  # board (works with no JS, and is exactly what `prefers-reduced-motion` falls
  # back to). The `.TurnResultsList` hook toggles `aria-current`/`.is-current`
  # on each `<li>` as the sighted replay steps through them (following
  # `.TurnReplay`'s `gc:replay` broadcast); nothing here depends on it.
  attr :turn, :integer, required: true
  attr :steps, :list, required: true

  def turn_results(assigns) do
    ~H"""
    <Card.card id="turn-results" class="min-w-[16rem]">
      <:header>Turn {resolved_turn(@turn)} results</:header>
      <ol
        id="turn-results-list"
        phx-hook=".TurnResultsList"
        class="flex flex-col gap-[var(--space-1)] text-sm list-decimal pl-[var(--space-4)]"
      >
        <li :for={step <- @steps} data-step={step.index}>{step.text}</li>
      </ol>
    </Card.card>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TurnResultsList">
      // Marks the step the replay is on in the accessible results list
      // (`turn_results/1`), from `.TurnReplay`'s `gc:replay` broadcast, and
      // re-applies it after LiveView patches the list (the drawer it sits
      // in re-renders on every chat message).
      export default {
        mounted() {
          this.current = -1
          this.onReplay = (e) => {
            this.current = e.detail.current
            this.apply()
          }
          window.addEventListener("gc:replay", this.onReplay)
          window.dispatchEvent(new CustomEvent("gc:replay-sync"))
        },

        updated() {
          this.apply()
        },

        destroyed() {
          window.removeEventListener("gc:replay", this.onReplay)
        },

        apply() {
          this.el.querySelectorAll("[data-step]").forEach((el) => {
            const isCurrent = Number(el.dataset.step) === this.current
            el.classList.toggle("is-current", isCurrent)
            if (isCurrent) el.setAttribute("aria-current", "step")
            else el.removeAttribute("aria-current")
          })
        }
      }
    </script>
    """
  end

  # The last turn's events are logged against the turn the engine already advanced to
  # (`Engine.Game.resolve_turn/1`), so the turn they *resolved* is one before `@view.turn` —
  # legacy's results post reads "Turn {Turn - 1} Results" for the same reason.
  defp resolved_turn(turn), do: turn - 1
end
