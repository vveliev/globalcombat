# Design Contracts

The consistency spine. Short, absolute, testable. Every statement here is (or
will be) enforced by `scripts/check-consistency`; agents and humans follow
them without exception. Statements marked `PROPOSED` fill gaps where the
planning docs are silent — flag them for review, don't treat them as settled.

## C1 — Components reference semantic tokens only

Component sources (`components/**`) contain **no** hex colors, `rgb()`/
`hsl()` calls, primitive palette names (`--gray-4`, `--cyan-6`), or raw
Mantine color props. Color enters a component only as `var(--color-…)`.

`PROPOSED` — dimensions: no raw px values in component sources except `0`
and `1px` borders; spacing/radius/size come from `var(--space-*)`,
`var(--radius-*)`, `var(--size-*)` or the wrapped primitive's own scale
props (`size="xs"`).

## C2 — Layouts reference tokens only; pages compose components

Layout shells (`layouts/**`) contain no literal colors or dimensions (same
scan as C1, including structural dimensions → `--size-*`) and do **not**
import Layer 2 components. Filling slots with components is the page's job
(preview demos, generated pages), never the shell's.

## C3 — Every referenced token exists

Every `var(--…)` reference in `components/`, `layouts/`, and
`preview/src/` resolves to a variable emitted in `build/css/variables.css`.
No speculative tokens, no typo'd names.

## C4 — Themes are complete or invalid

Every theme file defines the identical semantic key set (19 keys — see
`tokens/STYLE.md`). No partial themes, ever: a new semantic key lands in
every theme file (22 today) in the same change. Theme values are primitive
references only; literals fail validation. (Enforced today by
`scripts/validate-tokens.mjs`.)

## C5 — Framework sets expose the same inventory

The React and LiveView component sets expose the same component names with
equivalent props/attrs, and the layout sets mirror the same abstract layout
names — except entries on the pending-port list below, which lets one side
lead. An entry must name the component/layout and the side that's behind.

### Pending ports (LiveView side not yet started)

The full Layer 2 component inventory (28 components — core set, robo-hub
extraction set, ERP set, Radio/SegmentedControl, landing-grammar set,
data-graphics set) shipped its LiveView mirror in BLA-613; see
`components/COMPONENTS.md`'s "Shipped LiveView set" table for the
per-component API and any named C5 deviations (ThemedSelect's
`stateReducer`/context hook, Money/LineChart's client-formatter props —
both become caller-preformatted values server-side, documented in their
`@moduledoc`s). Blog/Admin/Management/Marketing/Console shipped their
LiveView mirror in BLA-615, alongside a new LiveView-only Game shell; see
`layouts/LAYOUTS.md`'s "Shipped LiveView set" table for the per-shell slot
API. Layer 3's one remaining asymmetry:

| Item | Leads | Notes |
|------|-------|-------|
| document layout | React | ERP document lifecycle shell (quote/PO/packing slip/invoice) |
| game layout | LiveView | LiveView-only by design (turn-based multiplayer owns its socket) — no React counterpart planned |

## C6 — Variation is a theme mapping, never component logic

Light/dark and brand differences live entirely in the `data-theme` axis
(Layer 1 mappings). No component or layout branches on brand or color
scheme; a page renders under every theme (22 today) with zero code changes.
Brand character (C9) rides the same axis: fonts, density, radius and button
style reach components only through the `data-theme` CSS blocks and the
per-brand Mantine themes — never through component props or conditionals.

## C7 — Docs move with the code

Any new or changed token group, component, or layout updates its layer's
guide doc (`tokens/STYLE.md`, `components/COMPONENTS.md`,
`layouts/LAYOUTS.md`) in the same change. A new layout also registers its
use case so the selector can pick it (and extends `selector/` if it's a new
surface type).

## C8 — Generated outputs are never hand-edited

`build/**` changes only via `npm run build:tokens`, committed together with
the `tokens/` source change that caused them.

## C9 — Brand character is complete or invalid

Every brand with theme files has exactly one entry in `tokens/brands.json`
and vice versa, and every entry defines the identical character key set
(font pair + heading weight, webfont, density, radius scale, shadow set,
type scale, button-style, icon-set, image-treatment — see
`tokens/STYLE.md`). `button-style` is `fill` or `outline`; nothing else.
Character is keyed by brand alone and the build injects it into both of the
brand's `[data-theme]` blocks — with one deliberate exception: `shadow`
defines a `light` and a `dark` set, because elevation is derived from the
ground (ink-tinted drops on a light ground, a hairline edge plus ambient
darkness on a dark one). (Enforced by `scripts/validate-tokens.mjs`.)

## Enforcement

`npm run check:consistency` (locally; also in CI via
`.github/workflows/ci.yml`) checks C1–C5 and C8 mechanically — add `--json`
(`node scripts/check-consistency.mjs --json`) for structured
`{contract, file, line, message}` output agents can consume. C6 is covered
by the all-themes test convention, C7 by review. Token validation (C4, C9)
runs inside `npm run build:tokens` as today, now with non-blocking WCAG
contrast advisories for text/surface pairs.

`PROPOSED` — token lint tooling: the planning docs fix the token format as
W3C DTCG JSON, so the lint step builds on `scripts/validate-tokens.mjs`
(extended with WCAG contrast warnings for text/surface pairs) rather than
`@google/design.md lint`, which assumes a DESIGN.md YAML source this repo
deliberately does not use.
