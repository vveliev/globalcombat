# design-boutique token vendor

Generated CSS copied from `vveliev/design-boutique` @ d9931c8 (branch BLA-615-heex-layout-shells), 2026-08-28.

| file | source in design-boutique |
| --- | --- |
| fonts.css | `build/css/fonts.css` |
| variables.css | `build/css/variables.css` (all themes, `data-theme` switched) |
| theme.css | `build/tailwind/theme.css` (Tailwind v4 `@theme inline` fragment) |

**Do not hand-edit.** These are build outputs of `npm run build:tokens` in design-boutique
(source: `tokens/`). To update, rebuild there and re-copy, recording the new SHA above.

## Also vendored from the same SHA

| here | source in design-boutique |
| --- | --- |
| `liveview/test/global_combat_web/components/boutique/*_test.exs` | `liveview/test/boutique_live_web/components/boutique/` (28 files, plain `ExUnit.Case`, no database) |
| `liveview/docs/design-boutique/*.md` | `DESIGN-CONTRACTS.md`, `DESIGN-SYSTEM-PLAN.md`, `tokens/STYLE.md`, `components/COMPONENTS.md`, `layouts/LAYOUTS.md` and the two map files |
| `.claude/skills/design-{tokens,components,layouts}` | `.claude/skills/` — the per-layer recipes to load before touching a layer |

The tests read component source paths, so they were rewritten `boutique_live_web` → `global_combat_web` as well as by module name.
