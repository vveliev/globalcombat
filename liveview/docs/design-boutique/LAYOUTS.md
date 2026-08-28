# Layer 3 — Layouts Guide

Page **shells** that arrange components. This is where blog, admin-with-sidebar,
and management views live. Forks per framework, but every layout pulls from the
same components and tokens, so they stay consistent regardless of arrangement.

## What a layout is

A layout is the skeleton — header, sidebar, content regions, footer — with slots
that components fill. It is **not** a component and **not** a token; it composes
both.

```
AdminLayout
 ├── Sidebar        (components)
 ├── TopBar         (components)
 └── <content slot> ← agent fills with page-specific components
```

## Starter layout set (v1 candidates)

| Layout | Shape | Typical use |
|--------|-------|-------------|
| **Blog** | Centered content column, optional TOC | Content/marketing reading |
| **Admin** | Left sidebar + top bar + content | Dashboards, CRUD admin |
| **Management** | Dense tables, filters, split panes | Ops / data-heavy views |
| **Marketing** | Hero + sections + footer | Landing pages |
| **Console** | Fixed-viewport rails around a live stage, optional media strip | Live operations: fleet control boards, monitoring cockpits, media walls |
| **Document** | Toolbar + form beside a live print preview | Business documents that get generated, exported and sent: quotes, purchase orders, packing slips, invoices |
| **Game** *(LiveView)* | Board region + player panel + live status | Turn-based multiplayer |

## Admin vs. public

Different **layouts** using the **same components**. The sidebar, breadcrumb,
and chrome differ; the buttons, inputs, and cards inside are identical and
inherit the active theme.

## Folder shape

```
layouts/
  react/
    BlogLayout/BlogLayout.tsx
    AdminLayout/AdminLayout.tsx
    ManagementLayout/ManagementLayout.tsx
```

The LiveView side has no `layouts/liveview/` mirror directory — Phoenix
layout shells are Elixir modules with named slots (grid-area placement and
slots need `attr`/`slot` macros, which a bare `.heex` template can't
declare), not files a bundler imports by path. Same deviation Layer 2 made
from this doc's original aspiration (`components/COMPONENTS.md`'s "Folder
shape", BLA-613). One module per shell at
`liveview/lib/boutique_live_web/components/boutique/layouts/<name>_layout.ex`
(module `BoutiqueLiveWeb.Components.Boutique.Layouts.<Name>Layout`; run
tests with `mix test` in `liveview/`).

## Shipped React set (v1)

Lives in `layouts/react/` as the npm workspace `@design-boutique/react-layouts`
(source-exported via `index.ts`; tests run with the root `npm test`). Every
layout: a compound shell whose slots position themselves via CSS grid areas —
child order never matters — with semantic landmarks (`header`/`nav`/`main`/
`aside`/`footer`), tokens only, typed props, colocated test asserting
landmarks + zero literal colors.

| Layout | Slots | Structure |
|--------|-------|-----------|
| `BlogLayout` | `Header`, `Toc`*, `Content`, `Footer` | Reading column `min(--size-content, 100%)`, sticky TOC rail (labelled nav) |
| `AdminLayout` | `Sidebar`, `TopBar`, `Content` | Full-height `--size-sidebar` nav + `--size-topbar` header + scrollable main |
| `ManagementLayout` | `FilterBar`, `Primary`, `Inspector`* | Dense (one padding step tighter, `--text-sm`); inspector column is `auto` so omitting the slot collapses it |
| `MarketingLayout` | `Nav`, `Hero`, `Section` (repeatable, `muted?`), `Footer` | Full-bleed bands wrapping a centered `--size-page` column; sticky nav |
| `DocumentLayout` | `Toolbar`, `Form`, `Preview`*, `Trail`* | The ERP document lifecycle (quote, PO, packing slip, invoice): actions pinned above, editable fields left, the document as it will print in a `--size-content` column right, revision trail below. Editing beside the artefact is the point. |
| `ConsoleLayout` | `Banner`*, `Queue`*, `Stage`, `Focus`*, `Strip`* | Fixed-viewport (100vh, no page scroll) ops cockpit from robo-hub's control-board archetype: `--size-rail` queue rail, flexible stage, `--size-rail-lg` focus rail, `--size-filmstrip` media strip; every region scrolls itself. Stage-only shape doubles as a media wall. |

\* optional — the grid absorbs the empty area.

Responsive collapse (all shells): at or below `--size-collapse` (64rem,
`tokens/scales.json`) every shell stacks to a single column via the
`useCollapsed()` hook (`layouts/react/useCollapsed.ts`) — inline styles
can't media-query, so the hook watches `matchMedia` against the token.
Collapsed shapes: Admin `topbar/sidebar/content`, Management
`filter/primary/inspector`, Blog `header/toc/content/footer` (TOC becomes an
"on this page" block, never dropped), Console `banner/stage/focus/queue/strip`
(robo-hub's own stacking order; the no-page-scroll rule holds only at width),
Document `toolbar/form/preview/trail`, Marketing just wraps its nav. Each
shell's collapsed shape has a colocated test (`mockViewport(true)` from
`test/match-media.ts`).

Structural dimensions come from the `size` token group in `tokens/scales.json`
(`--size-sidebar/topbar/content/inspector/page`) — never hardcode a shell
dimension; add a token if a new one is needed.

## Shipped LiveView set (v1)

Lives in `liveview/lib/boutique_live_web/components/boutique/layouts/`
(see "Folder shape" above). Mirrors the shipped React set one-for-one
(C5) plus a new LiveView-only Game shell. React's compound `<Name>Layout
+ <Name>Layout.Slot>` API becomes named HEEx slots on a single component
— `grid-area`/landmark placement is baked into each slot's own markup, so
(unlike React) there's no per-slot sub-component and slot order at the
call site was never coupled to visual position in the first place.
Optional slots use `:if={@slot != []}` (mirroring `card.ex`'s precedent)
to drop the wrapper landmark entirely when unused, same as the grid
absorbing an empty React slot's area.

| Layout | Slots | Structure |
|--------|-------|-----------|
| `blog_layout` | `:header`*, `:toc`*, `:content`, `:footer`* | Same reading column + sticky TOC rail as the React shell |
| `admin_layout` | `:sidebar`*, `:topbar`*, `:content` | Same full-height nav + header + scrollable main |
| `management_layout` | `:filter_bar`*, `:primary`, `:inspector`* | Same dense filter/primary/inspector split; omitting `:inspector` collapses its column |
| `marketing_layout` | `:nav`*, `:hero`*, `:section` (repeatable, `muted` slot attr)*, `:footer`* | Same full-bleed bands wrapping a centered `--size-page` column; sticky nav |
| `console_layout` | `:banner`*, `:queue`*, `:stage`, `:focus`*, `:strip`* | Same fixed-viewport cockpit; `lg:h-screen` (100vh, no page scroll) holds only at `lg:` and above |
| `game_layout` | `:status`*, `:board`, `:players`* | **New, LiveView-only** — board region + player panel + live status for turn-based multiplayer (`DESIGN-CONTRACTS.md`'s C5 pending list). No React shape to mirror: designed directly against this doc's slot/grid-area/token contract. |

\* optional — same absorbed-empty-area behavior as the React table above.

Responsive collapse (all shells except Marketing, which has no grid to
collapse): at `lg:` — Tailwind's default 64rem breakpoint is the same
value as `--size-collapse` (`tokens/scales.json`), so the built-in `lg:`
variant *is* the token, not a coincidence — each shell ships both the
collapsed (mobile-first, unprefixed) and expanded (`lg:`-prefixed) grid
classes as plain CSS, standing in for the React version's `useCollapsed()`
`matchMedia` hook (server-rendered HEEx has no client hook to run it
through). Each shell's colocated test asserts landmark presence and
optional-slot omission; the collapsed/expanded visual shapes themselves
were not verified in a browser for this pass (no local Elixir/Phoenix
toolchain in the environment that wrote them) — same evidence gap
`components/COMPONENTS.md` names for its own theme-swap check, tracked
here rather than silently assumed clean.

## How the agent uses this layer

1. Read the criteria → decide the surface (content? admin? game?).
2. Select the matching layout from the target framework's set.
3. Apply the chosen theme (from Layer 1) — layout doesn't hardcode color.
4. Fill the layout's slots with components from Layer 2.
5. Return the assembled mock-up.

## Rules for the agent

- Never put color/spacing values in a layout — reference tokens/components only.
- Prefer an existing layout; only create a new shell when no starter fits, and
  document it here when you do.
- Keep game/real-time layouts on the LiveView side; standard app surfaces on React.
