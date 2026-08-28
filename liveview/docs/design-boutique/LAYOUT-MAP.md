# Layout map — robo-hub pages → design-boutique shells

Derived from robo-hub's actual page structure (`frontend/src/pages/*.tsx`, routing at `frontend/src/App.tsx:22-58`), clustered by **observed grid structure**, not page name. Machine-readable sibling: `layouts/layout-map.json`. Evidence: `research/survey-sections/04-pages-routing.md`.

robo-hub wraps every authed page in one `AdminShell` (AppShell: 60px header, 222px collapsible navbar — `AdminShell.tsx:817-825`); the archetypes below describe what each page builds *inside* that shell. In design-boutique terms the shell chrome maps to `AdminLayout.Sidebar`/`.TopBar`, and the per-page archetype fills the content region — except the cockpit archetype, which owns the whole viewport and gets its own shell.

## Archetypes

| Archetype | robo-hub pages (source) | Grid skeleton observed | Our shell | Slot-fill guide |
|---|---|---|---|---|
| **Operations cockpit** | ControlBoardPage (`ControlBoardPage.tsx:188-278`), ControlPage (`ControlPage.tsx:155-321`) | flex-none header/banner + `flex:1 min-height:0` rail row (fixed 15rem queue rail · flexible stage · fixed 16.25rem focus rail) + flex-none filmstrip (84px); **no page scroll**, every region scrolls itself; stacks below 64rem (`styles.css:1849-2012`) | **`ConsoleLayout` (new)** | `Banner`: session/incident alert or control bar, omit when calm · `Queue`: prioritized work cards + mono ticker · `Stage`: the live surface (map/canvas/stream) · `Focus`: selected-item detail + actions (ConfirmDestructive with emergencyAction for destructive controls) · `Strip`: media tiles |
| **Media wall** | VideoWallPage (`VideoWallPage.tsx:180-403`; `WallGrid.tsx:54-60`) | flex-none control bar + `flex:1` CSS grid `repeat(N, minmax(0,1fr))`; immersive `role="dialog"` fullscreen variant | `ConsoleLayout` (Stage-only shape) | `Banner`: wall controls (labelled SegmentedControls, autoplay pause) · `Stage`: the tile grid — explicit column count, never an auto-collapsing grid |
| **Fleet dashboard** | FleetPage (`FleetPage.tsx:319-615`) | stacked full-width cards: [stat-row `SimpleGrid {base:1,sm:3}` + chip filter row + health table] then 2-up `Grid lg:6` card pair | `AdminLayout` | `Content`: StatCard row first (zero-count cards non-interactive), then dense `Table` with status `Badge`s, then supporting card pair — matches the existing admin slot intent |
| **Detail / inspector record** | DeviceDetailsPage (`DeviceDetailsPage.tsx:532-1002`), SiteDetailsPage (`SiteDetailsPage.tsx:659-1200`) | back-link + h1 + badge header row → banner alert region → two-column `md:6` card grid (device) or stacked section cards (site) → confirm dialogs | `ManagementLayout` | `FilterBar`: back link + title + status badges + refresh · `Primary`: the record's card grid · `Inspector`: live status / actions (the drawer contents, promoted to a pane) |
| **Admin CRUD list** | AlertsPage (`AlertsPage.tsx:112-172`), NotificationsPage, UsersPage (`UsersPage.tsx:365-509`), ApiKeysPage (`ApiKeysPage.tsx:326-450`), RolesPage (`RolesPage.tsx:636-1090`) | `.admin-*` spine: head row (h1 + gate/spec chips \| primary action) → state alerts → filter idiom (tabs / search / none) → `.admin-table` → footer note (`styles.css:2725-2872`) | `ManagementLayout` | `FilterBar`: title + chips + search/tabs + primary action · `Primary`: dense `Table` (severity word in `Badge`, reason as wrapping text) · `Inspector`: selected row detail or inline form (Roles' grant panel) |
| **Canvas inspector** | MapViewerPage (`MapViewerPage.tsx:148-400`); SiteDetails' map card is a nested relative | heading + file action → toolbar (metadata badges \| view controls) → fixed-height canvas viewport → legend → fact-card pair | `ManagementLayout` | `FilterBar`: toolbar · `Primary`: canvas card + legend + fact cards · `Inspector`: omit (facts inline) |
| **Settings** | SettingsPage (`SettingsPage.tsx:179-196`; grid at `styles.css:1119-1139`) | in-page sidebar grid `minmax(13rem,15rem) minmax(0,1fr)`, sticky nav card, vertical pills Tabs, 5 panels | `AdminLayout` | `Content`: vertical `Tabs` (pills) — nav column ≈ `--size-rail`; no new shell warranted, the Tabs component carries the structure |
| **Auth / entry** | LoginPage (`LoginPage.tsx:57-59`; `styles.css:1207-1213`) | full-viewport flex, single `maw 420` card, top-aligned (below-fold rationale) | none — deferred | No selector surface maps to an auth screen yet; adding an "entry" shell without a criteria path would make it unreachable. Revisit if the selector grows an auth surface. |
| **Style-guide gallery** | DesignSystemPage (`DesignSystemPage.tsx:337-360`) | flat run of 23 section cards | `BlogLayout` (structurally) | Out of selector scope — robo-hub's own living style guide; our equivalent is the preview sandbox itself |

## Structural dimensions used

`ConsoleLayout` consumes the Phase 1 imports: `--size-rail` (15rem, robo-hub `.board-rail-queue`), `--size-rail-lg` (16.25rem, `.board-rail-focus`), `--size-filmstrip` (5.25rem, `BoardFilmstrip.tsx:45-49`). The shell-width token `--size-shell` (1600px) is available to pages that want robo-hub's centered-column behavior.

## Responsive note

robo-hub stacks the cockpit to a single scrolling column below 64rem (`styles.css:1994-2012`). Our shells are inline-styled grids (no media queries by convention); the responsive collapse is a documented gap shared by all five shells — tracked in LAYOUTS.md, not silently dropped.

## Unverified / UNKNOWN

- The 7 canonical board states (watch/alert/focused/control-session/multi-robot-incident/degraded/viewer-role, `frontend/e2e/proposal-reference.spec.ts:19-27`) are a *content* contract for cockpit fills, not shell structure — recorded for the assembly layer, not encoded in the shell.
- Wide-screen behavior beyond 1600px: unconstrained in robo-hub; ours inherits the same.
