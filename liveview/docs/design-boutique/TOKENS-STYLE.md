# Layer 1 — Tokens / Style Guide

The source of truth for every visual value. **Framework-neutral.** Nothing in
here knows about React or LiveView. Both frameworks read the outputs this layer
produces.

## Principle

Define values as **named semantic tokens**, never raw hex inline. Swapping a
color theme = pointing the same names at a different value set. This is what
makes "multiple color versions" cheap.

```
❌  color: #2563eb;
✅  color: var(--color-primary);   // theme decides what primary is
```

## Token groups

| Group | Examples | Notes |
|-------|----------|-------|
| **Color** | `primary`, `surface`, `text`, `border`, `danger`, `success` | Semantic names, not `blue-500`. This is where themes vary. |
| **Typography** | `font-sans`, `font-mono`, `text-sm…text-2xl`, weights, line-heights | Same across themes usually. |
| **Spacing** | `space-1 … space-12` on a consistent scale (e.g. 4px base) | |
| **Radius** | `radius-sm/md/panel/lg/full` | `panel` (10px) is robo-hub's single card/panel radius — use it for card-like surfaces in robohub-flavored output. |
| **Shadow** | `shadow-sm/md/lg` | |
| **Z-index / motion** | layering scale, durations, easings | Optional but keep them tokenized too. |
| **Size** | `size-sidebar/topbar/content/inspector/page/rail/rail-lg/filmstrip/shell/collapse` | Structural dimensions consumed by Layer 3 shells — layouts never hardcode a width/height. `rail`/`rail-lg`/`filmstrip`/`shell` are imported from robo-hub's control-board + shell dimensions (see `research/robohub-token-diff.md`). `collapse` is the viewport width at/below which shells stack to one column (read via `layouts/react/useCollapsed.ts`, since inline styles can't media-query). |

## Two tiers of color tokens

1. **Primitive** — the raw palette: `blue-500`, `gray-100`. Never used directly
   in components.
2. **Semantic** — the intent: `primary`, `surface`, `text-muted`. Components use
   **only** these. A theme maps semantic → primitive.

```
primary  →  blue-500   (Theme: Ocean)
primary  →  violet-600 (Theme: Grape)
```

## Themes = the color versions

Each theme is a mapping from semantic tokens to primitive values. Ship several;
the agent selects one.

```
tokens/
  primitives.json      # raw palette, shared
  themes/
    robohub-light.json # semantic → primitive (one file per brand × mode)
    robohub-dark.json
    ocean-light.json … organic-dark.json
  brands.json          # brand character: fonts, density, radius, button style
  typography.json      # shared
  scales.json          # spacing, radius, shadow, size, z-index, motion
```

### Shipped semantic vocabulary

Every theme file must define exactly this key set (enforced by
`scripts/validate-tokens.mjs`; a build fails if a theme misses or adds a key):

`primary`, `primary-contrast`, `focus-ring`, `background`, `surface`,
`surface-muted`, `text`, `text-muted`, `border`, `divider`, `danger`,
`success`, `warning`, `info`, and the five-hue status system
`status.online`, `status.warning`, `status.partial`, `status.offline`,
`status.unknown` (adopted from robo-hub's color-blind-legibility-checked
design). `divider` is the section rule between content blocks (the
claude-design brands run it as an ink veil — 16% alpha, 40% for modernist's
deliberately heavy rules); on the original brands it aliases `border`.

Theme values must be `{references}` into primitives — a hex literal in a
theme file fails validation. Translucent veils use
`$extensions: { "design-boutique": { alpha: 0.84 } }` on a reference, which
builds to `color-mix(in srgb, var(--x) 84%, transparent)`.

### Brand character (`tokens/brands.json`)

Themes carry only color; everything else a brand *is* lives in one
`brands.json` entry per brand (contract C9 — identical key set, validated
with the themes): `font.heading` / `font.body` / `font.heading-weight`, a
`webfont` stylesheet URL ("" for system stacks), `density` (spacing
multiplier), a `radius` scale (`sm/md/panel/lg`), a `shadow` set (`light` +
`dark` × `sm/md/lg` — the one mode-forked group, since elevation derives
from the ground; values may hold `{color.x.y}` references, resolved to
`var()` at build), a `type` scale (`display` — the fluid hero size above
heading-1, a per-brand `clamp()` from the source landings, emitted as
`--heading-display`; `heading-1…6`, `heading-leading`, `heading-tracking`,
`body-size`, `body-leading` — brands matching the
Mantine defaults emit no Mantine size override), `button-style`
(`fill` | `outline`), and two informational hints for the assembly agent
(`icon-set`, `image-treatment` — applied per `selector/BRAND-GUIDES.md`). The build
injects it into both of the brand's `[data-theme]` blocks (fonts, scaled
`--space-*`, brand `--radius-*`), mirrors it into the brand's Mantine theme
(fontFamily/headings/radius/spacing and the outline-primary Button default),
and collects the webfont URLs into `build/css/fonts.css` — import that
alongside `variables.css` wherever webfont brands render. The selector
exposes the same record as `Selection.character`.

### Brands

Eleven brands × light/dark = 22 themes: **robohub** (imported from
../robo-hub's audited system), **ocean** (blue), **grape** (violet),
**slate** (gray-primary), **erpion** (indigo — the business/ERP brand), and
the six **claude-design imports** — **broadsheet** (newsprint grey, print
cyan/magenta), **classical** (warm grey, antique bronze), **industry** (cool
grey, blueprint steel-blue), **modernist** (warm grey, vermilion red),
**nocturne** (blue-grey night ground, blurple — dark is its native band),
**organic** (cream ground, terracotta/sage). The
gray/cyan/green/yellow/orange/red primitive ramps are robo-hub's OKLCH ramps;
blue/violet/indigo are Open Color.

The claude-design brands are color imports of the six systems in `data/`
(Broadsheet, Classical, Industry, Modernist, Nocturne, Organic): each
system's OKLCH 100–900 ramps land as primitives (steps 1–9 plus a derived
step 0), its exact ground/ink pins as `paper`/`card`/`ink`, and its pinned
accent as `base`. The system's native band maps those pins verbatim; the
counterpart band is derived from the ramps following the ocean/erpion
patterns. The systems' non-color identity — font pair, heading weight,
density, radius scale, button style — crosses over through the brand
character axis (`tokens/brands.json`, below); their photo assets, templates
and component HTML stay in `data/`.
`primary` uses the nearest ramp step to the pinned accent that clears 4.5:1
under its contrast color; `focus-ring` keeps the exact accent pin in the
native band (a non-text ring only needs 3:1). Status hues stay the audited
robo-hub set, with `status.unknown` on the brand's own neutral.

**erpion** is the business brand: neutral-dominant, opaque surfaces (no alpha
veils — dense tables read better on solid panels), a single deep indigo accent
reserved for the primary action and focus, and the five audited status hues
doing all the signalling. It is deliberately the quietest brand in the set;
on an ERP screen the data is the design.

The robohub theme mappings were reconciled (2026-08) against what robo-hub
actually ships (`@vveliev/react-platform/tokens/base.css`, its live token
source): light status hues are yellow-6 / orange-7 / red-7 (text-grade, not
the mid-ramp steps), dark `status.unknown` is gray-5, and light `surface`
veils gray-0 at 83%. Per-token provenance and every deliberate divergence is
recorded in `research/robohub-token-diff.md`.

## Build pipeline (Style Dictionary)

One definition, three outputs so both frameworks stay in sync:

- `css` → `:root` CSS custom properties (used by LiveView/Tailwind and as the
  runtime layer for React).
- `mantine` → a Mantine theme object (JS/TS) for the React side.
- `tailwind` → a Tailwind config fragment for the Phoenix side.

```
Style Dictionary
   ├── build:css       → variables.css        (both)
   ├── build:mantine   → mantine-theme.ts      (React)
   └── build:tailwind  → tailwind.tokens.js    (Phoenix)
```

## Rules for the agent

- Read available theme names from `tokens/themes/`.
- Never invent a hex value; only reference semantic tokens.
- Light/dark is just another theme axis — treat it as a token mapping, not a
  component concern.
