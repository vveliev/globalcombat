# Design System Plan

A code-based, agent-driven design system. You define the pieces once; an agent
selects a layout and a color theme, fills it with components, and returns a
mock-up. Two framework targets are supported from a single shared foundation.

## Goal

> Predefine a small set of templates and design styles in code. Given a set of
> criteria, an agent picks the right template + style and produces a mock-up
> website.

## The three layers

The whole system is three stacked layers. Each layer has its own guide file so
the agent (and humans) can read the conventions in isolation.

| Layer | What it is | Framework-specific? | Guide |
|-------|-----------|---------------------|-------|
| **1. Tokens / Style** | Colors, typography, spacing, radius, shadows — the raw design values, plus the multiple color themes | **No** — pure data, shared | `tokens/STYLE.md` |
| **2. Components** | Buttons, custom select, calendar, cards — consume tokens, own their responsive + accessibility behavior | **Yes** — one set per framework | `components/COMPONENTS.md` |
| **3. Layouts** | Page shells: blog, admin-with-sidebar, management view — arrange components | **Yes** — one set per framework | `layouts/LAYOUTS.md` |

The seam that makes dual-framework work: **tokens stay framework-neutral**, and
only layers 2 and 3 fork per framework.

```
                 ┌─────────────────────────┐
                 │  Tokens (JSON, shared)   │   ← single source of truth
                 └────────────┬─────────────┘
              Style Dictionary builds outputs
        ┌─────────────────────┴──────────────────────┐
        ▼                                             ▼
  CSS vars + Mantine theme (React)          CSS vars + Tailwind (Phoenix)
        │                                             │
   React components                          LiveView components
        │                                             │
   React layouts                             LiveView layouts
```

## Framework decision

Support **both**, deliberately, because they serve different parts of the product:

- **React + Mantine** — the standard app surface. Agents generate it well,
  Mantine's theme system gives color-swapping almost for free, mature ecosystem.
- **Phoenix LiveView** — the game and any real-time surface. One language front
  to back, PubSub gives multiplayer sync for free. Turn-based games have no
  meaningful round-trip latency problem, so LiveView is a strong fit here.

### Trade-offs (honest version)

| | Pros | Cons |
|--|------|------|
| **React + Mantine** | Agent-friendly, built-in theming, huge ecosystem, best-in-class custom-component wrapping | Heavier frontend, more moving parts, JS/TS context switch |
| **Phoenix LiveView** | One language, real-time for free, less client state to manage, great for the game | Thinner component ecosystem, agents have seen less of it, styling via Tailwind not a Mantine-style lib |
| **Supporting both** | Right tool per surface, shared token source keeps them visually consistent | **Every component built twice** — the real ongoing cost |

## When LiveView actually beats React

Server-as-source-of-truth, live-pushed workloads: real-time dashboards, chat,
collaborative tools, live order/bid tracking, and turn-based multiplayer games.
React pulls ahead for highly interactive client-side work (drawing tools,
offline apps, twitch-latency games).

## Agent workflow

1. Read criteria (audience, surface type, brand mood, framework target).
2. Pick a **framework target** → React or LiveView.
3. Pick a **layout** from that framework's layout set (`layouts/LAYOUTS.md`).
4. Pick a **color theme** from the token themes (`tokens/STYLE.md`).
5. Fill the layout with **components** (`components/COMPONENTS.md`).
6. Emit the mock-up.

**Shipped (v1)** as a hybrid: steps 2–4 are deterministic code —
`@design-boutique/selector` (`selector/index.ts`) maps `Criteria` →
`{layout, brand, theme, slots}` via private data tables
(surface→layout, mood→brand), fully tested. `Selection` speaks
framework-neutral vocabulary — abstract layout names ("blog", "admin") that
each framework's adapter resolves to its concrete shell (React:
`LAYOUT_BY_NAME` in `@design-boutique/react-layouts`). Steps 1 and 5–6 are
the assembly agent's job, following `selector/AGENT.md`. Worked examples of
the full loop live in `preview/src/generated/`.

## Recommended starting points (don't build from scratch)

- **Tokens:** Style Dictionary — define once, output CSS vars + Mantine theme + Tailwind config.
- **React:** Mantine (theme system for color versions); React Aria / Mantine primitives under custom components.
- **Phoenix LiveView:** Mishka Chelekom (90+ Tailwind components, dark/light), PhiaUI as a second option.

## Open questions to resolve next

- Exact list of layouts to ship in v1 (blog, admin, management, marketing, game?).
- How many color themes at launch, and are they per-brand or per-mode (light/dark) or both?
- Does the agent output editable code, a running preview, or both?
