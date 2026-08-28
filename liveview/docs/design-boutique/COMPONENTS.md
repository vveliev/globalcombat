# Layer 2 — Components Guide

Reusable UI pieces that **consume tokens** and **own their own behavior**
(responsive rules, accessibility, interaction). Forks per framework — a React
set and a LiveView set — but both read the same Layer 1 tokens, so they stay
visually consistent.

## What lives here vs. not

- **Here:** buttons, inputs, custom select, calendar/date picker, cards,
  modals, notifications — plus their mobile↔desktop and admin-variant behavior.
- **Not here:** how components are arranged on a page. That's Layer 3 (layouts).

## Golden rule: wrap primitives, don't hand-roll

The hard parts — keyboard nav, screen-reader support, focus management,
positioning — are painful and easy to get subtly wrong. Inherit them.

- **React:** build your custom select on **Mantine's `Select`** (or **React
  Aria** primitives); build a calendar on Mantine's `DatePicker`. You own only
  styling (via tokens) + your specific behavior.
- **Phoenix:** start from **Mishka Chelekom** / **PhiaUI** components and restyle
  to tokens.

```
Your <ThemedSelect>
   └── wraps Mantine <Select>  (a11y + keyboard handled)
        └── styled via semantic tokens
```

## React best practices (2026)

1. **Compound components.** Expose a base + named children sharing state via
   Context, instead of one component with 50 props.
   ```tsx
   <Select>
     <Select.Trigger />
     <Select.Option value="a">A</Select.Option>
   </Select>
   ```
   Readable for humans, and clean for an agent to generate.

2. **Build on accessible primitives.** React Aria (unstyled, fully accessible)
   or Mantine (uses React Aria under the hood). Bring styling, inherit behavior.

3. **TypeScript for props.** Type every prop; it's your contract and the agent's
   guardrail.

4. **State reducer pattern.** Let consumers override state transitions
   (`stateReducer` prop) so a design-system component flexes to cases you didn't
   predict. This is how Downshift-style autocompletes work.

5. **Colocate a test per component.** Behavior + visual + a11y. Avoid
   over-abstraction and don't mix business logic into UI.

## Responsive & variants

- Responsive logic lives **with the component**, driven by token breakpoints —
  not duplicated in every layout.
- Admin vs. public is usually a **variant/prop** on the same component (or a
  different layout using the same components), not a separate component.

## Folder shape

```
components/
  react/
    ThemedSelect/
      ThemedSelect.tsx
      ThemedSelect.test.tsx
    Calendar/
    ...
```

The LiveView set lives in the Phoenix app itself, not under `components/` —
`liveview/lib/boutique_live_web/components/boutique/<name>.ex` (one module
per component, e.g. `BoutiqueLiveWeb.Components.Boutique.ThemedSelect`),
colocated tests under `liveview/test/boutique_live_web/components/boutique/`.
That's a deliberate divergence from the folder sketch above: Phoenix
components are Elixir modules resolved through `lib/`, not files a bundler
imports by path, so there is no `components/liveview/` mirror directory —
`npm test`'s repo-root scan only ever covered `components/react/`.

## Shipped React set (v1)

Lives in `components/react/` as the npm workspace
`@design-boutique/react-components` (source-exported via `index.ts`; run tests
with `npm test` at the repo root). Every component: wrapped Mantine primitive,
semantic tokens only, typed props, colocated test rendered against the real
shipped theme (`build/mantine/theme.ts`), not a bare provider.

| Component | Wraps | API notes |
|-----------|-------|-----------|
| `Button` | Mantine `Button` | `intent="primary\|neutral\|danger"` instead of raw color/variant; primary fills from `--color-primary`/`--color-primary-contrast` (data-theme recolors it, no provider change); danger is deliberately stock red + autoContrast until a `--color-danger-contrast` token exists |
| `Input` | Mantine `TextInput` | contract point for future defaults |
| `ThemedSelect` | Mantine `Select` | compound `<ThemedSelect.Option>`, `stateReducer` prop (Downshift-style veto/override), `useThemedSelect()` context hook |
| `Card` | — (pure tokens) | compound `Card.Header/Body/Footer`; the first component with no Mantine base — a headed panel has no interaction to inherit (the ERP set and the landing grammar are pure tokens for the same reason) |
| `Modal` | Mantine `Modal` | a11y defaults (labelled close, non-banner header) inherited from the shared theme |
| `Calendar` | `@mantine/dates` `DatePicker` | |
| `Notification` | Mantine `Notification` | `intent` maps to theme status hues; labelled close button |
| `Table` | Mantine `Table` (+`ScrollContainer`) | compound `Table.Head/Body/Row/HeaderCell/Cell`; `dense` ops variant; `minWidth` scroll wrapper; Mantine table CSS vars pinned to semantic tokens; uppercase micro-label headers (robo-hub convention) |
| `Badge` | Mantine `Badge` | `intent="neutral\|info\|success\|warning\|danger"`; `dot` variant so hue is never the only signal |
| `Tabs` | Mantine `Tabs` | compound `Tabs.List/Tab/Panel`; pills variant, `keepMounted=false` default (robo-hub SettingsPage migration) |
| `StatCard` | Mantine `UnstyledButton`/`Progress` | KPI tile from robo-hub's FleetStatCard; `tone` maps to semantic intents; interactive variant is a real button; labelled meter |
| `PageState` | Mantine `Alert`/`Loader` | namespace compound `PageState.Loading/Error/Empty/Retry`; Error `role="alert"`, Loading `role="status"`; Retry wraps `Button` |
| `ConfirmDestructive` | our `Modal` + `Button` | required `consequence`; verb-phrase confirm; optional type-to-confirm gate; `emergencyAction` slot inside the focus trap |
| `StatusPill` | — (pure tokens) | the shared status vocabulary: six lifecycle `tone`s (`new/active/waiting/partial/blocked/done`) that every module maps its own words onto; the word is required, hue is reinforcement |
| `Money` | — (pure tokens) | amount + required ISO `currency`, tabular figures; optional `rate` records the manually entered conversion and exposes it to pointer and AT |
| `Quantity` | — (pure tokens) | value + required `unit`; optional `min` marks a stock breach in words as well as hue |
| `StagePipeline` | — (pure tokens) | ordered linear stages with `done/current/pending/blocked/outsourced` states written out; `aria-current="step"` on the active stage; optional cumulative `elapsed` |
| `Radio` | Mantine `Radio`/`Radio.Group` | compound `Radio.Group`; ported from the claude-design systems' `.radio` control (`data/*/components/forms.html`); checked dot takes the theme primary |
| `SegmentedControl` | Mantine `SegmentedControl` | ported from the claude-design systems' `.seg` control; 2-5 short exclusive options flipped in place — Tabs switches sections with panels, Radio.Group stacks labelled choices |
| `Kicker` | — (pure tokens) | claude-design landing grammar: uppercase tnum section label in the primary ink, led by a solid dash (`dash={false}` to omit); wayfinding only, never a hero eyebrow |
| `FadingRule` | — (pure tokens) | the DS-wide rule treatment: 1px `--color-divider` separator fading to transparent over 3rem each end; marks stay solid, rules fade |
| `StatGroup` | — (pure tokens) | compound `StatGroup.Stat`; display figures (`--heading-1`, tnum) over uppercase muted labels as a `<dl>`; draws no band ground — that's the page's call per BRAND-GUIDES |
| `FeatureList` | — (pure tokens) | compound `FeatureList.Item`; numbered asymmetric rows (num/title/copy on one baseline) parted by fading structural rules; "no equal cards" |
| `PullQuote` | — (pure tokens) | display quote with hanging `“` and hung `—` attribution via the theme's font-measured `--quote-hang`/`--attribution-hang` (0em on original brands) |
| `TreatedImage` | — (pure tokens) | photograph through the brand's image treatment via the theme's `--image-*` vars (halftone/plate/duotone/grayscale/lighten/washed); `shape` maps to radius tokens; `alt` required |
| `BarChart` | — (pure tokens, SVG) | single-series bars on `--color-primary`, values in text ink, divider grid, per-mark `<title>` tooltips + hidden table fallback; required `label`. One series by design — no categorical palette exists in the vocabulary |
| `LineChart` | — (pure tokens, SVG) | 1–2 series: accent solid + ink dashed (identity never hue-alone), legend at 2, surface-ringed markers, `formatValue`; a third series throws — small multiples, not a new color |
| `Timeline` | — (pure tokens) | date-anchored milestones: reached dots fill with the accent, future outlined, `aria-current="step"` on `current`; horizontal, scrolls in place. StagePipeline is the process, Timeline is the calendar |

Conventions locked by this set: semantic `intent` props instead of raw color
props; compound children over prop explosions; tests must use
`components/react/test/test-utils.tsx` so theme-level a11y fixes are exercised.

## Shipped LiveView set (v1)

Lives in `liveview/lib/boutique_live_web/components/boutique/` (module
`BoutiqueLiveWeb.Components.Boutique.<Name>`; run tests with `mix test` in
`liveview/`). Mirrors every React component above, one-for-one (C5) — same
`intent`/tone vocabulary, same semantic tokens, consumed as Tailwind
utilities that resolve through `build/tailwind/theme.css`
(`bg-primary`, `text-danger`, `rounded-[var(--radius-md)]`, …) rather than
`var(--color-*)` inline styles, since that's the idiomatic entry point on
this side. Golden rule for Phoenix is "start from Mishka Chelekom and
restyle to tokens" (`design-components` skill) — in practice, two generated
Mishka Chelekom primitives were worth keeping and wrapping
(`BoutiqueLiveWeb.Components.Modal` for its focus-trap + show/hide JS
commands, `NativeSelect` for its accessible `<select>`), because Mishka's
generated files ship large multi-brand color matrices we don't need and
that reference vendor CSS variables (`assets/vendor/mishka_chelekom.css`,
literal hex) this repo deliberately never imports — everything else in the
set is hand-built HEEx on plain semantic HTML/ARIA, which stays leaner and
still inherits real accessibility (native `<input type="radio">`,
`role="tablist"`/`"tab"`/`"tabpanel"`, `role="alert"`/`"status"`, a real
`<table role="grid">` calendar, etc.) without fighting generated bulk.
Compound React APIs (`Card.Header`, `Table.Row`, …) become either named
HEEx slots (`:header`, `:col`) or multiple public function components in
one module (`Table.th`/`Table.tr`/`Table.td`), whichever mirrors the shape
more directly — see each component's `@moduledoc` for which it picked.

Theme-swap verification for the set (all 8 themes shown at once, reusing
`TokensLive`'s `data-theme` swap mechanism) was done via a throwaway
preview route — built, checked live in a browser across brands/modes,
then deleted, since a permanent LiveView catalog (the equivalent of the
React preview's Component catalog view) is its own scoped follow-up, not
part of this pass. No such route ships in this repo as a result — that's
deliberate, not an oversight, but it does mean there's no committed
artifact of that check beyond this note. Every component is
semantic-tokens-only (C1) and never branches on brand (C6) by
construction, which is what makes an 8-theme render a mechanical
consequence rather than something that could regress per-component; the
one-time browser check confirmed that construction actually holds.

| Component | Base | API notes |
|-----------|------|-----------|
| `button/1` | plain `<button>` | `intent="primary\|neutral\|danger"`; danger is Tailwind stock `bg-red-600 text-white` — same deliberate exception as React's Button (no `--color-danger-contrast` token yet) |
| `input/1` | restyles `CoreComponents.input/1` | thin token-class wrap; error state via `border-danger` |
| `themed_select/1` | wraps generated `NativeSelect` primitive | `:option` slot; React's `stateReducer`/`useThemedSelect()` are client-state ergonomics with no server-rendered-`<select>` equivalent — named, reasoned C5 deviation in the moduledoc, not a silent gap |
| `card/1` | pure tokens | `:header`/`:inner_block`/`:footer` slots, each only rendered when used |
| `modal/1`, `show_modal/1,2`, `hide_modal/1,2` | wraps generated `Modal` primitive | real focus-trap + JS show/hide inherited; DOM/JS-driven open state, no LiveView assign round-trip needed just to open/close |
| `calendar/1` | hand-built `<table role="grid">` | pure `Date`/`Calendar` stdlib grid math, no new dep; stateless — caller LiveView owns `year`/`month`/`selected`, `today` is a required attr (never `Date.utc_today()` internally, keeps render pure) |
| `notification/1` | pure tokens | `intent` → soft `bg-{intent}/10` fill (Mantine's default weight, not solid); `danger`/`warning` get `role="alert"`, `info`/`success` get `role="status"`; dismiss is a pure client `JS.hide`, with an `on_close` JS escape hatch for a server round trip |
| `table/1`, `thead/1`, `tbody/1`, `tr/1`, `th/1`, `td/1` | pure tokens | compound React shape mirrored as sibling function components (HEEx has no dot-children); `dense` is a per-cell attr on `th`/`td` rather than a cascading root prop (no context-like cascade in HEEx); `min_width` on `table/1` gives the horizontal-scroll wrapper |
| `badge/1` | pure tokens | `intent`, `dot` — same vocabulary as React |
| `tab_list/1`, `tab/1`, `tab_panel/1` | pure tokens + `Phoenix.LiveView.JS` | pills variant; `keepMounted=false` is literal — `tab_panel/1` guards its own root on `:if={@active == @id}`, so the inactive panel's content isn't in the HTML at all; `active` is an attr the calling LiveView threads through (stateless function components can't own it themselves) |
| `stat_card/1` | pure tokens | `eyebrow`/`value`/`tone`/optional labelled `<progress>`/`interactive` (renders a real `<button>` via `dynamic_tag/1`, never a div with a click handler) |
| `loading/1`, `error/1`, `empty/1`, `retry/1` | pure tokens | same namespace-by-module pattern as React's `PageState.*`; `error/1` is `role="alert"`, `loading/1` is `role="status"` |
| `confirm_destructive/1` | wraps `modal/1` + `button/1` | required `title`/`consequence`/`confirm_label`; optional type-to-confirm gate (`typed_phrase`/`required_phrase`, compared on every render — caller-owned state, no local assign); `:emergency_action` slot |
| `radio/1`, `group/1` | native `<input type="radio">` | `accent-[var(--color-primary)]` styling — full keyboard/AT semantics inherited for free, no ARIA hand-rolling needed |
| `segmented_control/1` | native radios, `peer`-styled | hidden (`sr-only`, never `hidden`/`display:none` — stays focusable) radios drive a pill-track look via `peer-checked:`/`peer-focus-visible:`; `role="radiogroup"` + required `aria-label` (explicitly not repeating robo-hub's QualitySelector gap) |
| `kicker/1` | pure tokens | uppercase tracked label, optional leading dash |
| `fading_rule/1` | pure tokens | `<hr>` styled via inline `style` referencing `var(--color-divider)` in a `linear-gradient` — the one component where an inline style beats Tailwind utilities, since gradients aren't expressible as one |
| `stat_group/1`, `stat_group_stat/1` | pure tokens | `<dl>` compound; `tabular-nums` for figures |
| `feature_list/1`, `feature_list_item/1` | pure tokens | numbered asymmetric rows; each item owns its own leading fading rule, suppressed via a `first` attr (no runtime child-position inspection like React's `Children.toArray`) |
| `pull_quote/1` | pure tokens | hang via inline `style="text-indent: var(--quote-hang)"` / `var(--attribution-hang)` |
| `treated_image/1` | pure tokens | `alt` required; treatment applied via `var(--image-*)` refs only — component never branches on which brand is active (C6) |
| `bar_chart/1` | pure tokens, SVG | `role="img"` SVG + `sr-only` `<table>` fallback (visually hidden, never `aria-hidden` — it's the tabular truth for AT) |
| `line_chart/1` | pure tokens, SVG | React's client `formatValue` callback becomes a caller-preformatted string per point (`%{value:, formatted:}`); a 3rd series raises `ArgumentError`, same "small multiples, not a new color" rule |
| `timeline/1` | pure tokens | reached/current/future dots; `aria-current="step"` |
| `money/1` | pure tokens | `amount` is a caller-preformatted string — no `Intl.NumberFormat` equivalent in Elixir stdlib, so number formatting stays the caller's job; `currency` required |
| `quantity/1` | pure tokens | breach wording ("below min"), not hue-only |
| `stage_pipeline/1` | pure tokens | takes a `stages` list attr (not a slot) — mirrors the React source's own `stages: Stage[]` prop shape, same pattern `timeline/1` already uses for `events` |
| `status_pill/1` | pure tokens | `tone` → the same underlying token each tone maps to on the React side (`active` routes through `--color-info`, the rest through the `status.*` five-hue system) |

### Seeing the set

The table above is the inventory of record; the preview's **Component
catalog** view (L2 Elements, `preview/src/CatalogDemo.tsx`) is its rendered
twin — one titled card per component, every enum variant of every prop drawn
out, with an anchor index at the top. It complements the Elements view, which
stays a scenario: which pieces belong together on a real surface.

Adding a component means adding it in three places in the same change — this
table, `components/react/index.ts`, and the catalog. The registry the catalog
renders from lives apart from the JSX in `preview/src/catalog.ts` so two
guards can hold it: `preview/src/catalog.test.ts` compares it against the
package's export list, and `CatalogDemo`'s demo table is keyed by the
registry's union type, so a registered name with no demo fails the typecheck.

## Rules for the agent

- Reach for an existing wrapped component before generating a new one.
- New custom component → wrap the framework's accessible primitive, style with
  tokens, add a colocated test, type the props.
