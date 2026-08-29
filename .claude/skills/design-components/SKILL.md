---
name: design-components
description: Create or modify Layer 2 components. Use when touching files under components/ — adding a component to the React or LiveView set, changing a component's interface, or porting a component across frameworks.
---

# Design Components (Layer 2)

**Trigger:** any change under `components/`. Also load `design-tokens` if the
component needs a value no semantic token provides.

**Contracts enforced here:** C1 (semantic tokens only), C5 (React and
LiveView sets expose the same inventory), C6 (variation is a theme mapping,
never component logic), C7 (docs move with the code) — `DESIGN-CONTRACTS.md`.

**Golden rule:** wrap an accessible primitive, don't hand-roll. React → Mantine
(or React Aria); Phoenix → Mishka Chelekom. You own styling (semantic tokens)
and your specific behavior; keyboard/focus/screen-reader work is inherited.

## Recipe (React)

1. Check the inventory table in `components/COMPONENTS.md` — extend an
   existing component before creating a new one.
2. Create `components/react/<Name>/<Name>.tsx`:
   - Wrap the Mantine/React Aria primitive; re-export a **typed** props
     interface. Omit the primitive's raw styling props (`color`, `variant`)
     and expose **semantic intent props** instead
     (`intent="primary" | "neutral" | "danger"` — see `Button`).
   - Style via semantic tokens only: `var(--color-*)`, `var(--space-*)`,
     `var(--radius-*)`, `var(--shadow-*)`. No hex/rgb/hsl, no primitives
     (`--gray-4`), no magic px.
   - Multiple named parts → **compound components** sharing context
     (`Card.Header`, `ThemedSelect.Option`), not prop explosions.
   - Behavior consumers may need to bend → **state reducer prop**
     (`stateReducer?: (state, action, proposed) => state`, see
     `ThemedSelect`). Don't add one speculatively.
3. Colocate `<Name>.test.tsx`, rendered through
   `components/react/test/test-utils.tsx` (real shipped theme, so
   theme-level a11y fixes are exercised — never a bare provider). Cover:
   behavior, a11y roles/labels, and a zero-literal-colors assertion.
4. Export from `components/react/index.ts` (component + prop types).
5. Register the component in the inventory table in
   `components/COMPONENTS.md`, same change. If the LiveView mirror exists,
   add the counterpart or add the name to the pending-port list in
   `DESIGN-CONTRACTS.md`.
6. Demo it in the preview sandbox if it's user-visible surface area.
7. Verify: `cd components/react && npx vitest run <Name>` while iterating,
   then `npm test` and `npm run check:consistency` before calling it done.

## Recipe (LiveView) — when the mirror exists

Same shape: start from Mishka Chelekom, restyle via the Tailwind token
fragment (`build/tailwind/theme.css`), mirror the React component's
props/attrs and intent vocabulary, colocated test, register in the inventory.

## Never

- Reference a primitive token or literal color/dimension.
- Encode light/dark or brand awareness in a component — themes are a
  `data-theme` concern (Layer 1).
- Add layout responsibilities (page arrangement) — that's Layer 3.
- "Mechanically fix" the robohub Mantine `primaryShade: 9` stock-cyan choice
  without a contrast pass (see CLAUDE.md provenance notes).

## Definition of done

- Wraps an accessible primitive; typed props; semantic tokens only.
- Colocated test passes via shared test-utils; `npm test` and
  `npm run check:consistency` green.
- Exported from `index.ts`; inventory table in `COMPONENTS.md` updated;
  cross-framework parity handled (ported or pending-port listed).
