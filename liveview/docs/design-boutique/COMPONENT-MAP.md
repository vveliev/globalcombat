# Component map — robo-hub → design-boutique

One row per robo-hub component (the 30 in `ds-bundle/components/` plus live-only components found in `frontend/src/components/`), mapped to this repo's Layer 2 set. Machine-readable sibling: `components/component-map.json` (consumed by the selector/assembly layer). Evidence and full API detail: `research/robohub-design-survey.md` + `research/survey-sections/`.

**Status vocabulary:** `exists (React)` · `exists (React+LiveView)` · `port-needed` · `new-primitive` (we built it this pass) · `app-specific (out of scope)` — app-domain composites stay in the map as *patterns with a slot recipe*, not Layer 2 primitives.

## 1. Design-system primitives

| robo-hub component | source (path:line) | purpose / role | our equivalent | status | framework coverage | notes |
|---|---|---|---|---|---|---|
| PageHeading | `react-platform/src/PageHeading.tsx:14-35` (ds-bundle `general/PageHeading`) | page `<h1>` + supporting line; single owner of the h1-per-page rule | none — pages compose `Title order={1}` + `Text` | port-needed | — | Low urgency: our layouts put the h1 in slot fills. If ported: wrap Mantine `Title`, props `title/description`, no color props. |
| PageLoadingState | `react-platform/src/PageStates.tsx:5-14` | centered spinner + required label | `PageState.Loading` | new-primitive | React | We add `role="status"` (gap flagged in survey §02: source announces nothing). |
| PageErrorState | `react-platform/src/PageStates.tsx:16-37` | async-failure alert, explicit `role="alert"` | `PageState.Error` | new-primitive | React | Carries the "silent replacement is the failure mode" rule (WCAG 3.3.1). |
| PageEmptyState | `react-platform/src/PageStates.tsx:39-67` | empty/needs-setup state, decorative icon badge | `PageState.Empty` | new-primitive | React | Icon `aria-hidden`; measure capped. |
| RetryAction | `react-platform/src/PageStates.tsx:69-75` | standard retry button | `PageState.Retry` | new-primitive | React | Folded into the PageState namespace; wraps our Button `intent="neutral"`. |
| ConfirmDestructive | `react-platform/src/ConfirmDestructive.tsx:15-63` | destructive-action confirm: required `consequence`, verb-phrase confirm, type-to-confirm gate, `emergencyAction` inside the focus trap | `ConfirmDestructive` | new-primitive | React | Wraps our Modal (inherits labelled close + non-banner header from theme). 9 production uses in robo-hub. |
| RelativeTimestamp | `react-platform/src/RelativeTimestamp.tsx:5-12` | relative time with exact stamp on hover/focus/touch | none | port-needed | — | Wrap Mantine `Tooltip` (+`title` attr duplicate for touch); needs a date-formatting dep decision first. |
| FleetStatCard | `frontend/src/components/FleetStatCard.tsx:5-16` | KPI tile: eyebrow, value, detail/hint, progress, click-through; tone system cyan/lime/yellow/red | `StatCard` | new-primitive | React | Generalized: tone → semantic `primary/success/warning/danger`; interactive variant is a real `<button>` (UnstyledButton) instead of robo-hub's hand-rolled key handling. Their lime "action-card" tone maps to `success` (their own docs call the tone system a separate language from status hues). |
| QualitySelector | `frontend/src/components/QualitySelector.tsx:7-12` | two-tier segmented switch (preview/focus) | none — app vocabulary | app-specific (out of scope) | — | The *generic* need (labelled SegmentedControl) is Mantine direct; if we ever wrap one, fix robo-hub's missing `aria-label` (survey §02 gap 1). |
| TimezoneSelect | `frontend/src/components/TimezoneSelect.tsx:10-34` | searchable IANA zone select | `ThemedSelect` covers the pattern | exists (React) | React | API drift: theirs injects the current value so stale records can't blank (worth adopting if we build a data-backed select preset). |
| NotificationAnnouncer | `frontend/src/components/a11y/NotificationAnnouncer.tsx:15-57` | mirrors toasts into an `aria-live` region (WCAG 4.1.3) | none | port-needed | — | Infrastructure singleton, pairs with our `Notification`; port when the preview grows toast flows. |

## 2. Primitives robo-hub uses straight from Mantine (usage counts drive priority)

| Mantine component (uses) | our equivalent | status | notes / API drift |
|---|---|---|---|
| Table (403) | `Table` (+ `.Head/.Body/.Row/.HeaderCell/.Cell`, `dense`, `minWidth` scroll container) | new-primitive | Pins Mantine's `--table-border-color`/`--table-hover-color` to semantic tokens; uppercase micro-label headers (robo-hub `.fleet-table th` convention, `styles.css:9246-9251`). |
| Button (172) | `Button` | exists (React) | Drift: robo-hub relies on stock-cyan `primaryShade: 9` fills — that's the Mantine-theme layer, provenance-protected; our intent API is unchanged. |
| Card (91) | `Card` | exists (React) | Drift: robo-hub enforces ONE card radius (10px `--panel-radius`, cardRadius.test.ts). Ours uses `--radius-md`; `--radius-panel` now exists for robohub-flavored fills. |
| Alert (71) | `Notification` covers intent-alert; inline alert variant is Mantine direct | exists (React) | robo-hub alerts are consistently `role="alert"`. |
| Badge (70) | `Badge` (`intent`, `dot`) | new-primitive | Light variant default (their status badges); dot variant for shape-redundant signaling. |
| TextInput (57) | `Input` | exists (React) | Drift: robo-hub leans on Mantine `error` prop for aria-invalid wiring — same with ours. |
| Select (25) | `ThemedSelect` | exists (React) | Ours adds compound options + stateReducer. |
| Tabs (30) | `Tabs` (pills, keepMounted=false) | new-primitive | Mirrors their SettingsPage migration (vertical pills). robo-hub also has two *non*-Tabs tab idioms (hand-rolled tablist, SegmentedControl-as-tabs) — map both to `Tabs` in ports. |
| Modal (14) | `Modal` | exists (React) | Their labelled-close/non-banner-header fixes already live in our shared theme. |
| Skeleton (28) | none | port-needed | Loading rows for Table; thin wrapper, low risk. |
| Progress (12) | inside `StatCard`; standalone none | port-needed | robo-hub rule: every Progress carries `aria-label`. |
| SegmentedControl (14) | none | port-needed | Must ship with a required label prop (their QualitySelector omission). |
| Popover/Menu/Tooltip (30/22/21) | none | port-needed | Chrome-level; needed by a future AppShell port, not by page fills. |
| Notification/toasts | `Notification` | exists (React) | Pair with a NotificationAnnouncer port for AT parity. |
| Calendar (`@mantine/dates`) (0 uses in robo-hub) | `Calendar` | exists (React) | We lead; robo-hub has no date-picking surface. |
| Pagination (0 uses — `design-system.md:232-238`) | none | not needed | Confirmed real gap in robo-hub; don't invent. |

## 3. App-domain composites → patterns with slot recipes

These are **not** Layer 2 candidates; the selector treats them as fill patterns built from primitives above. `pattern` keys match `component-map.json`.

| robo-hub component | source | pattern (slot recipe) | status |
|---|---|---|---|
| AdminShell | `frontend/src/components/app/AdminShell.tsx:810-1605` | `app-shell`: skip link → sidebar (grouped nav + signals) → topbar (scope chip, search, utilities, account) → content. Maps to AdminLayout slots; decompose, don't translate (1606 lines). | app-specific (out of scope) |
| DeviceHealthTable | `frontend/src/components/DeviceHealthTable.tsx:8-11` | `health-table`: `Table` (dense) + status `Badge` per row + labelled `Progress` meters + row deep-links; below-md swap to stacked Cards. | app-specific (out of scope) |
| RobotStatusBoard | `frontend/src/components/RobotStatusBoard.tsx:7-10` | `availability-board`: rows of `role="img"` strips with sentence alt-text + Badge + Progress. **Orphaned in robo-hub (0 production uses)** — do not prioritize. | app-specific (out of scope) |
| WorkQueuePanel / EventCommandPanel / FocusPanel / ActCluster / BoardFloorMap / BoardFilmstrip | `frontend/src/components/board/*` | `ops-cockpit` fills: queue list Card (aria-current rows), mono ticker Card, inspector Card (StatCard mini-grid + actions incl. ConfirmDestructive w/ emergencyAction), canvas region, filmstrip strip. | app-specific (out of scope) |
| AddDeviceModal / EditDeviceModal / BulkImportModal / InteractionProfileModal | `frontend/src/components/devices/*` | `record-form-modal`: Modal + labelled inputs + focus-on-invalid + permission text; disabled controls state why. | app-specific (out of scope) |
| SitePropertyDefinitions / ConnectivityPanel | `frontend/src/components/devices/*` | `schema-editor`, `heartbeat-strip` (KIND_COLOR = status tokens; word + hue). | app-specific (out of scope) |
| FloorMapViewer / FloorSceneCanvas / FloorPointDrawer / FloorPanelCard / FloorMapImportCard / FloorMapStatusSummary / RobotDetailsDrawer | `frontend/src/components/floor/*` | `canvas-inspector` fills: toolbar + fixed-height scene (`role="application"`, keyboard pan) + legend + fact cards + right Drawer. Domain tokens (`--floor-*`) stay app-side. | app-specific (out of scope) |
| WallGrid / VideoWallTileStream / WebRTCSessionPlayer / VideoWallControls / FocusedAdjacentPreview / PushToTalkControl / TalkActivityIndicator / QualitySelector | `frontend/src/components/video/*` (2 deleted upstream) | `media-wall` fills: explicit `repeat(N, minmax(0,1fr))` grid (never SimpleGrid — collapses), fixed-flag error text, per-camera labels, wall-level autoplay pause (WCAG 2.2.2). | app-specific (out of scope) |
| SessionExpiryWarning / ProtectedRoute | `frontend/src/components/a11y|/` | `session-guard`: role=alert warning + "Stay signed in" (WCAG 2.2.1), countdown aria-hidden. | app-specific (out of scope) |
| EventFeed (deleted upstream) | `git 2019ff4:frontend/src/components/EventFeed.tsx` | `live-feed`: Card + status-dot rows, three distinct empty states keyed to stream state. | app-specific (out of scope) |
| AlertRulesManager | `frontend/src/components/alerts/AlertRulesManager.tsx` | `rules-manager`: list-primary + collapsed create form (spec 014). | app-specific (out of scope) |

## 4. LiveView mirror plan (per gap, when the mirror ships)

Every `new-primitive` above is React-lead and listed in DESIGN-CONTRACTS.md pending ports. Mishka Chelekom counterparts: Table → `table`; Badge → `badge`; Tabs → `tabs`; StatCard → compose `card` + `progress`; PageState → `alert` + `spinner` + custom empty block; ConfirmDestructive → `modal` + `button` (danger) with the same required-`consequence` attr contract. All consume the same semantic tokens through `build/tailwind/tokens.cjs`.

## 5. Unverified / UNKNOWN

- react-platform internals were read from robo-hub's `node_modules` copy at v0.3.0 — a newer upstream may have drifted.
- Deleted components (EventFeed, VideoWallControls, FocusedAdjacentPreview) were read from git objects; their patterns may be intentionally retired.
- RobotStatusBoard's orphaned status: intent UNKNOWN (flagged in robo-hub survey; not ported).
