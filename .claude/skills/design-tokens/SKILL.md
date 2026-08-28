---
name: design-tokens
description: Add or modify design tokens (Layer 1). Use when touching anything under tokens/ — primitives, scales, typography, or theme mappings — or when a component/layout needs a value that no token provides yet.
---

# Design Tokens (Layer 1)

**Trigger:** any change under `tokens/`, or any moment you're tempted to write
a raw color/dimension in a component or layout — the fix is a token, never a
literal.

**Contracts enforced here:** C3 (every referenced token exists), C4 (themes
complete or invalid), C8 (generated outputs never hand-edited) —
`DESIGN-CONTRACTS.md`.

**Canonical format:** W3C DTCG JSON (`$value` / `$type` / `$extensions`).
Never DESIGN.md YAML, never Material naming. Generated outputs in `build/`
are never edited by hand — edit `tokens/`, then `npm run build:tokens`.

## Structure (two tiers, non-negotiable)

1. **Primitives** (`tokens/primitives.json`) — raw ramps (`gray.0…9`,
   `cyan.0…9`, …). Components never reference these.
2. **Semantic** (`tokens/themes/*.json`) — intent names (`color.primary`,
   `color.surface-muted`). One file per brand × mode; each is purely a
   mapping `semantic → {primitive.reference}`. Hex/rgb literals in a theme
   file fail validation.

Alpha veils: put `"$extensions": { "design-boutique": { "alpha": 0.84 } }` on
a reference — the build emits `color-mix(...)`. Never pre-bake transparency
into a primitive.

## Recipe

1. Decide the tier. New raw color → primitive ramp (with provenance note if
   imported). New *meaning* → semantic key. New structural dimension →
   `size` group in `tokens/scales.json`. Most requests need only a new
   mapping in existing themes, or nothing at all — check the shipped
   vocabulary in `tokens/STYLE.md` first.
2. Adding a semantic key: add it to **all 8 theme files** in the same change
   (`{brand}-{light,dark}` × robohub/ocean/grape/slate). Partial themes fail
   `npm run validate:tokens`.
3. Reference primitives only in themes; pick light/dark values as a pair and
   sanity-check contrast against the surfaces they'll sit on.
4. `npm run build:tokens` — validates, then regenerates `build/css/
   variables.css`, `build/mantine/theme.ts`, `build/tailwind/theme.css`.
   Commit the regenerated outputs with the source change.
5. Update `tokens/STYLE.md` (vocabulary table / group table) in the same
   change.
6. Run `npm run check:consistency` (C1–C5/C8; `--json` for machine-readable
   violations) — a renamed or dropped semantic key breaks consumers here
   before CI does.
7. Run `npm test` — component tests render against the real built theme.

## Never

- Edit anything in `build/` directly.
- Flatten a semantic value to hex "just this once".
- Add a brand or mode without producing the complete 18-key semantic set.
- Rename a semantic key without migrating every consumer (grep
  `--color-<name>` across `components/`, `layouts/`, `preview/`).

## Definition of done

- `npm run build:tokens` passes (validation + regeneration).
- All 8 themes still define the identical semantic key set.
- Regenerated `build/` outputs are committed alongside `tokens/` sources.
- `tokens/STYLE.md` reflects the change.
- `npm run check:consistency` and `npm test` green.
