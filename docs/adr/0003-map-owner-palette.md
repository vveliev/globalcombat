# ADR-0003: An app-level categorical palette for map owner colours

- Status: Accepted
- Date: 2026-09-04
- Issue: none (maps artwork improvement, PR #42 on the fork)

## Context

The `:original` game board became a vector SVG (`GlobalCombatWeb.GameLive.WorldMap`)
whose territories are filled by CSS from the owner number, replacing GIF sprites that
had the colour baked into their pixels. That needs a *categorical* palette: up to eight
players plus "unclaimed" must be told apart at a glance, and the mapping from player
number to hue should stay stable across turns and, ideally, match the ordering long-time
players remember from the legacy site (`Player.GetColor()`: blue, green, yellow, orange,
purple, grey, red, brown).

The design-boutique semantic vocabulary (`docs/design-boutique/TOKENS-STYLE.md`,
contract C1 in `DESIGN-CONTRACTS.md`) deliberately has no categorical palette — its
charts are single-series and carry `--color-primary` (see `BarChart`'s moduledoc). The
five status hues exist, but they mean something (online/warning/offline...) and there
are only five. No semantic token can express "player 3".

## Decision

`assets/css/app.css` defines an app-level token group, `--map-*`, on `:root` with a
`[data-theme$="-dark"]` override block:

- `--map-owner-0` … `--map-owner-8` — one per owner slot (`WorldMap.owner_slot/1`,
  the legacy `owner % 9`), aliasing design-boutique **primitives** (`--blue-6`,
  `--green-5`, …) in the legacy order. Slot 0 is "unclaimed".
- `--map-sea`, `--map-fog-a`, `--map-fog-b` — board surfaces, likewise primitives, with
  dark-mode values.

Everything else on the board (ink, borders, focus ring, danger, surface halo) reads the
ordinary semantic tokens. One CSS ladder maps `data-owner="N"` to `--map-owner-fill` on
the shared `.world-map-owner` class, so the territory fill and the player-list legend
dot can never disagree.

This is a knowing exception to C1's "semantic tokens only", scoped to `app.css`
(application code, not `components/`). It is recorded here rather than added to the
boutique vocabulary because the palette is a game-domain concept with no meaning
elsewhere in the system.

## Consequences

- Themes can restyle the sea and fog per mode, and could re-alias the owner slots
  per brand if a brand ever needed it, without touching the component.
- Contrast is not the palette's job: army counts sit on a dark stroke under a light
  fill (`paint-order: stroke`, GIF-83), so any owner colour stays legible and the
  palette can change without a contrast re-audit. Territory fills are not text.
- The `dark` Tailwind custom variant in `app.css` used to match the bare
  `[data-theme=dark]`, which the `<brand>-<mode>` theme names never satisfy; it now
  matches the same `-dark` suffix the map tokens do. The only `dark:` utilities in the
  codebase sit in the generated Mishka `modal`/`native_select` colour branches
  (`primary`/`success`/...) that the boutique wrappers never select (they keep the
  `natural` default), so nothing changed visibly — but the variant is no longer a trap.
- If the boutique vocabulary ever gains a categorical/chart palette, the `--map-owner-N`
  aliases should be re-pointed at it and this ADR superseded.

## Amendment (2026-09-05): dark-mode owner contrast

The "contrast is not the palette's job" consequence above is about army-count *text*
legibility, which the stroke-under-fill treatment noted above does guarantee regardless of
fill colour. It says nothing about a territory being visually distinguishable from the
sea it sits in — that's a fill-vs-fill contrast, and a 2026-09-05 design critique of the
Game Over screen found two owner slots fail it against dark mode's
`--map-sea` (`--gray-8`, deliberately much darker than light mode's pale sea):
`--map-owner-6` (`--gray-6`, ~2.7:1) and `--map-owner-8` (`--orange-7`, ~1.7:1), both
under the 3:1 WCAG 1.4.11 floor for non-text UI. `--map-owner-3` (`--yellow-3`) was
audited alongside them and clears 3:1 comfortably in both themes.

`[data-theme$="-dark"]` now re-aliases owner 6 to `--gray-4` (two steps lighter than
`--gray-6`) and owner 8 to `--orange-3` (four steps lighter than `--orange-7`), chosen
to land in the same ~4-7:1 band the rest of the palette already gets against
`--gray-8`, while keeping owner 8 far enough from owner 4's unchanged `--orange-5` on
the same orange ramp that the two stay easy to tell apart. Light mode is untouched.
