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

## Known local divergences from upstream

| file | line | what | why |
| --- | --- | --- | --- |
| `variables.css` | `[data-theme="industry-dark"] --color-danger` | `var(--red-4)` → `var(--red-3)` | GIF-89: `--red-4` measures ~3.82:1 against `--color-surface` (`--zinc-8`) here, below the WCAG AA 4.5:1 floor for text; `--red-3` clears it at ~4.87:1. This is an upstream token bug (`tokens/themes/industry-dark.json` in `vveliev/design-boutique`), not something specific to this vendor copy — file it there too. Re-running `sync_design_boutique.sh` will silently revert this override unless the upstream fix lands first; re-verify the contrast after any re-vendor. |
