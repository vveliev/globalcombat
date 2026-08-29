---
name: design-layouts
description: Create or modify Layer 3 layout shells. Use when touching files under layouts/ — adding a page shell, changing slots, or porting a layout to another framework.
---

# Design Layouts (Layer 3)

**Contracts enforced here:** C2 (layouts reference tokens only; pages compose
components), C5 (framework parity), C7 (docs move with the code) —
`DESIGN-CONTRACTS.md`.

**Trigger:** any change under `layouts/`. A layout is a **shell with slots**
— it arranges, it never contains content or business UI. If you're writing
copy, data, or a specific component instance inside a layout file, stop:
that belongs to the page that fills the slot.

## Recipe (React)

1. Prefer an existing shell (`Blog`, `Admin`, `Management`, `Marketing`) —
   only create a new one when no starter fits the surface type, and say so
   in the change description.
2. Create `layouts/react/<Name>Layout/<Name>Layout.tsx`:
   - **Compound slot API**: `<Name>Layout` container + named slot children
     (`<Name>Layout.Sidebar`, `.Content`, …). Slots self-place via CSS
     `gridArea` so child order never matters; optional slots leave an empty
     area the grid absorbs (see `ManagementLayout.Inspector`'s `auto`
     column).
   - **Semantic landmarks**: slots render `header`/`nav`/`main`/`aside`/
     `footer` with `aria-label` where the role repeats.
   - **Tokens only**: colors via `var(--color-*)`, spacing via
     `var(--space-*)`, structural dimensions via `var(--size-*)` — if a
     dimension token doesn't exist, add one (load `design-tokens`), never
     hardcode.
   - Typed props: every slot extends `ComponentPropsWithoutRef` of its
     element and merges `style` last so callers can extend.
3. Colocate `<Name>Layout.test.tsx`: landmarks present with slot content,
   child-order independence, optional-slot omission, structural dimensions
   come from `--size-*` tokens, zero literal colors
   (use `layouts/react/test/no-hex.ts`).
4. Export from `layouts/react/index.ts`.
5. Register in `layouts/LAYOUTS.md`: shipped-set table row (slots +
   structure) **and** its intended use case, so the selector can pick it.
   If it's a new *surface type*, extend the selector's abstract layout
   names and mapping table (`selector/`) in the same change — the selector
   must never encounter a layout it can't name.
6. Demo it in the preview view switcher.
7. Verify: `cd layouts/react && npx vitest run <Name>Layout` while iterating,
   then `npm test` and `npm run check:consistency` before calling it done.

## Recipe (LiveView) — when the mirror exists

Same shells as `.heex` with named slots, mirroring the React grid structure
and landmark semantics, styled via the Tailwind token fragment. Game/
real-time shells live only on the LiveView side.

## Never

- Put a raw color, px value, or content in a shell.
- Import Layer 2 components into a layout file — layouts define the frame;
  pages compose components into slots.
- Add a layout without documenting its use case in `LAYOUTS.md` (an
  undocumented layout is invisible to the selector).

## Definition of done

- Compound slots, grid-area placement, semantic landmarks, tokens only.
- Colocated test passes; `npm test` and `npm run check:consistency` green.
- Exported; `LAYOUTS.md` table + use case updated; selector updated if a
  new surface type; preview demo added.
