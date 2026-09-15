# Mobile battle mode — spec and delegation plan

Status: proposed, 2026-09-14. Scope: the LiveView game screen (`GameLive`) only.

## 1. Problem

On a phone the game screen is a tall scrolling column and the board is clipped.
Observed on an iPhone (390px wide) against the deployed app:

| Symptom | Cause |
|---|---|
| Only the Americas are visible; the rest of the map is off screen to the right | `.world-map { min-width: 40rem }` in `assets/css/app.css` forces a 640px board inside a scrolling board slot |
| Tapping a territory means scrolling down to find the order panel; End Turn is at the very bottom | `board/1` in `lib/global_combat_web/live/game_live.ex` stacks lens, map, region bonuses, order panel, results, turn controls, then the players rail and chat |
| The soft keyboard covers the Assign button and offers text suggestions for a number | `type="number"` with no `inputmode`, no `autocomplete="off"`, and nothing keeps the form above the keyboard |
| Small territories (Japan, Iceland, Indonesia) are nearly impossible to tap | The map cannot be zoomed on its own; page pinch zoom scales the chrome too and `.world-map` has `overflow: hidden` |
| The topbar and Menu disclosure eat a third of the first screen | The site chrome is always rendered; nothing uses `100dvh` or the safe-area insets and the viewport meta lacks `viewport-fit=cover` |

What already works and must be preserved:

- The board is one responsive SVG with a `viewBox`; territories are `<g role="button">` with `phx-click="select_area"`, order arrows use `phx-click="select_order"`. Geometry lives in static `<defs>` and never re-sends.
- Accessibility: the sr-only board table, the `.FocusManager` hook restoring focus to the status landmark, `aria-live` regions, reduced-motion CSS. Tests assert no horizontal document scroll at 375px and 768px.
- Hooks already own client-side state that survives patches (`.TurnReplay` re-applies count text in `updated()`); the map viewport hook follows the same pattern.

## 2. Target experience

Below the `lg` breakpoint (64rem, the `--size-collapse` token) and only while a game is in play (`status == :playing` and not `view.ended`), the game screen becomes a full-height map stage with overlays. The lobby and the finished-game screen keep today's stacked layout. Above `lg` nothing changes visually except the lens control moving into the status strip.

```
┌──────────────────────────────────────────┐
│ Turn 7  ● In progress   [Owner|Region|Fr]│  top strip: status slot (fixed)
│                        [⛶] [☰ Players]  │  fullscreen + drawer buttons
├──────────────────────────────────────────┤
│                                          │
│                                          │
│              MAP  STAGE                  │  board slot: fills the rest,
│         pan / pinch / double-tap         │  no page scroll, map fitted
│                                          │
│                                          │
├──────────────────────────────────────────┤
│ Attack Ukraine with how many armies?     │  dock slot: bottom sheet,
│ [ − ] [  12  ] [ + ] [Max]               │  contextual (see §4.3)
│ [ Attack ]  [ Cancel ]                   │
└──────────────────────────────────────────┘
      ┌───────────────────────┐
      │ Players  ▸ drawer     │  off-canvas: roster, chat, bonuses,
      │ chat, bonuses, orders │  your orders, turn results, Quit,
      │ results, Quit, Home…  │  site nav links
      └───────────────────────┘
```

Interaction rules:

1. One-finger drag pans the map. Two-finger pinch zooms about the pinch midpoint. Double tap zooms in 2.5x about the tap; double tap again resets to fit. A tap that moved less than 8px is a territory click, exactly as today.
2. Tapping a territory opens the order panel in the dock. Tapping a second territory sets the target (existing `select_area` behaviour). Cancel clears the selection and the dock returns to the idle row.
3. The dock's idle row is End Turn (or "Waiting on other players…") plus Force Turn. Quit moves into the drawer so it cannot be hit by accident.
4. The drawer opens from the top strip, traps focus, closes on Escape, backdrop tap, or its Close button, and returns focus to the button that opened it.
5. The fullscreen button uses the Fullscreen API where available (Android Chrome, desktop). On iPhone Safari it is hidden; there the web app manifest and Apple metas give a chrome-free window when the game is added to the home screen.
6. The soft keyboard never covers the dock: the stage height tracks `visualViewport.height`.
7. Reduced motion: no zoom animation, instant viewBox changes.

## 3. Architecture decisions

| Decision | Choice | Why |
|---|---|---|
| Mobile breakpoint | Below `lg` (64rem) | Matches `--size-collapse` and every other shell; tablets in portrait get the stage too |
| Where the mobile placement logic lives | `GameLayout` gains a `:dock` slot and a `stage` boolean attr; `GameLive` places the same components in different slots | No new events, no duplicated markup, one server-rendered tree that CSS rearranges per breakpoint |
| Map pan and zoom | A colocated hook `.MapViewport` that rewrites the SVG `viewBox` from pointer events and re-applies it in `updated()` | Keeps `<use>` geometry, `phx-click`, highlight and arrow layers untouched; LiveView's DOM patch resets attributes the server rendered, so the hook must re-apply after every patch (same pattern as `.TurnReplay`) |
| Drawer | Native `<dialog>` styled as a side sheet, opened by a small `.Drawer` hook | Focus trap, Escape, and inertness of the page come for free; no dependency |
| Fullscreen | Fullscreen API on `#game-board` where `document.fullscreenEnabled`, else hidden button; PWA manifest for iOS | iPhone Safari has no element fullscreen; standalone mode is the only chrome-free option there |
| Site chrome in stage mode | `site_chrome` gets an `immersive` boolean; below `lg` it hides the topbar and sidebar and removes content padding | The drawer carries the nav links so nothing becomes unreachable |
| Lens control placement | Moves into the `:status` slot at every breakpoint | It is a view control, not board content; avoids rendering the same form twice with one id |
| Scope of stage mode | `:playing` and not ended only | Lobby and game-over screens are short and read better stacked; `players_first` keeps working for the ended case |

## 4. Detailed design

### 4.1 `GameLayout` (`lib/global_combat_web/components/boutique/layouts/game_layout.ex`)

New attrs and slot:

```elixir
attr :stage, :boolean, default: false,
  doc: "below lg: status becomes a fixed top strip, board fills the viewport height, dock is a bottom sheet, players is an off-canvas drawer"
slot :dock, doc: "contextual actions; rendered inline in the players rail above lg, as the bottom sheet below lg when stage is set"
```

Grid below `lg` when `stage` is true:

- Wrapper: `h-[100dvh] grid grid-rows-[auto_minmax(0,1fr)_auto] [grid-template-areas:'status'_'board'_'dock'] overflow-hidden` plus `pt-[env(safe-area-inset-top)]`.
- `:status` section: unchanged semantics (`aria-live`, `tabindex="-1"`, `data-focus-landmark`), gains `flex-wrap` and the two overlay buttons (drawer toggle, fullscreen toggle) rendered by the layout, not the consumer, so the smoke page and the game share them.
- `main` (board): `overflow-hidden min-h-0` instead of `overflow-auto`; `p-0`.
- `:dock` section: `[grid-area:dock] max-h-[45dvh] overflow-y-auto bg-surface border-t border-border p-[var(--space-3)] pb-[max(var(--space-3),env(safe-area-inset-bottom))]`, `aria-label="Actions"`.
- `:players` aside: rendered inside a `<dialog id="game-drawer" class="game-drawer">` with a close button, `aria-label="Players"`. Above `lg` the same content renders as today's side rail (the dialog is not used; a `hidden lg:block` twin is not acceptable because chat and roster carry ids, so the aside markup must be one element whose container differs by breakpoint. Implementation: render the aside once inside the dialog; above `lg` the dialog is forced open and styled as a static column via CSS `dialog[open]` rules, below `lg` it behaves as a modal sheet. Verify `dialog.show()` vs `showModal()` handling in the `.Drawer` hook on breakpoint change.)
- When `stage` is false, today's grid is rendered exactly as now, plus the dock rendered after the board in the stacked order and in the players rail above `lg`.

Above `lg` with `stage` true: same as today's side-by-side grid, dock content rendered at the top of the players rail.

### 4.2 `SiteChrome` (`lib/global_combat_web/components/site_chrome.ex`)

New attr `immersive :boolean, default: false`. When true, the topbar and sidebar wrappers get `hidden lg:flex` (or the admin layout's equivalent), and the content slot drops its padding below `lg`. `GameLive` passes `immersive={@status == :playing and not @view.ended}`. The `sidebar_links/1` function becomes public so the drawer can render the same links.

### 4.3 `GameLive` slot placement (`lib/global_combat_web/live/game_live.ex`)

| Component | Today | After |
|---|---|---|
| Lens segmented control | top of board | `:status` slot, after the pills |
| `WorldMap` figure | board | board (unchanged) |
| `game_over/1` | board | board (stage mode is off when ended, so unchanged) |
| `order_panel/1` | rail column beside the map | `:dock` |
| Turn controls (End Turn, Waiting, Force Turn) | below the board table | `:dock`, rendered only when no area is selected |
| Quit button | turn controls | `:players` (drawer), bottom, `intent="danger"` |
| `region_bonuses/1` | rail column beside the map | a legend drawn into the map's bottom-left sea (`WorldMap.legend/1`); the list is a wrapping strip under the map below `md`, screen-reader only from `md` up |
| `your_orders_card/1`, `turn_results/1` | rail column beside the map | `:players`, after the roster and before chat |
| `board_table/1` (sr-only) | board | board (unchanged) |
| Replay controls | status strip | status strip (unchanged; compact button labels below `lg`) |

Dock contents by state (`@selected_area`):

- `nil`: `#turn-controls` row. End Turn `intent="primary"` full width on phones; Force Turn `intent="neutral"`.
- selected, no target: order panel in `:assign` mode.
- selected with target: order panel in `:transfer` or `:attack` mode. Title stays as `order_panel_title/2`.

Order panel changes:

- Amount input: add `inputmode="numeric"`, `pattern="[0-9]*"`, `autocomplete="off"`, `enterkeyhint="done"`.
- Stepper: `−` and `+` buttons (`phx-click="step_amount"` with `phx-value-delta`) and `Max` (`phx-click="max_amount"`). New handlers set `order_amount` only; `submit_order` validation is unchanged. `Max` uses the source area's `armies` for transfer and attack, and the viewer's unassigned reinforcements for assign if `PlayerView` exposes that number (otherwise `Max` is omitted in assign mode; note it in the PR).
- Buttons stay `Assign`/`Transfer`/`Attack`, `Unassign`, `Cancel`; on phones they wrap to full-width rows.

### 4.4 `.MapViewport` hook (`lib/global_combat_web/live/game_live/world_map.ex`)

Mounted on the `.world-map` wrapper, which gains `phx-hook=".MapViewport"`, `data-view-box={@view_box}`, `id="world-map"`, and CSS `touch-action: none; user-select: none; -webkit-user-select: none`.

State: `base` (parsed from `data-view-box`), `current` `{x, y, w, h}`, `pointers` map (pointerId → last point), `moved` flag for the current gesture, `lastTap` timestamp and point.

Behaviour:

- `mounted()`: parse base, apply fit (see below), attach `pointerdown/move/up/cancel`, `wheel` (zoom with ctrl or trackpad pinch, plain wheel scrolls the page), `dblclick` suppressed in favour of the manual double-tap detector, and a capture-phase `click` listener that calls `stopPropagation()` and `preventDefault()` when `moved` is true so `phx-click` never fires after a drag.
- Pan: one active pointer, delta in client px converted to user units with `current.w / svg.clientWidth`.
- Pinch: two active pointers; scale = previous distance / new distance applied to `w` and `h`, anchored at the midpoint so the point under the fingers stays put. Clamp scale between 1 (fit) and 6.
- Clamp pan so at least 20% of the map stays inside the stage on each axis.
- Double tap: two taps within 300ms and 24px, no movement: zoom 2.5x about the point, or reset to fit if already zoomed.
- `updated()`: re-apply `current` to the `viewBox` attribute (LiveView will have reset it to the server value). Also runs after `.TurnReplay` patches; ordering between hooks is irrelevant because both only touch their own attributes.
- Fit: on mount and on a `resize`/`orientationchange` event, fit = contain (whole map visible) when `matchMedia("(min-width: 64rem)")` is false; above `lg` the hook does nothing but still supports wheel zoom. Persist `current` in `sessionStorage` under `gc:viewport:<game id>` and restore on mount so a chat patch or reconnect does not reset the player's zoom.
- Exposes `data-zoomed="true|false"` on the wrapper for CSS (e.g. hide the fit hint once zoomed) and a `[data-map-fit]` button target in the status strip that resets to fit.
- Keyboard: `+`/`-` zoom and arrow keys pan when the wrapper has focus (`tabindex="0"`), so the stage is operable without touch.

Do not use `phx-update="ignore"`: territory fills, counts, arrows, and highlights inside the SVG must keep patching.

### 4.5 `.Drawer` hook and drawer markup

- `<dialog id="game-drawer" class="game-drawer" aria-label="Players and chat">` containing the `:players` slot and a Close button at the top.
- Below `lg`: `showModal()` on open; slides in from the right; `min(22rem, 92vw)` wide; backdrop `::backdrop` dimmed; closes on Escape, backdrop click (check `event.target === dialog`), Close.
- Above `lg`: the hook calls `dialog.show()` once on mount and CSS positions it as the static rail column (`position: static; width: var(--size-rail)`), matching today's `aside`. On breakpoint change (`matchMedia` listener) the hook closes and re-opens in the right mode.
- The opener button in the status strip has `aria-expanded` kept in sync, `aria-controls="game-drawer"`, and receives focus back on close.
- Unread indicator: a dot on the opener when a chat message arrives while closed. Implemented in the hook by observing `#chat-messages` child count (add that id to the chat `<ul>`); cleared on open.

### 4.6 Fullscreen and PWA

- `.Fullscreen` hook on the status-strip button: hidden when `!document.fullscreenEnabled`; toggles `document.getElementById("game-board").requestFullscreen({navigationUI: "hide"})` / `document.exitFullscreen()`; keeps `aria-pressed` in sync via `fullscreenchange`.
- `priv/static/manifest.webmanifest`: `name`, `short_name` "Global Combat", `display: "standalone"`, `orientation: "any"`, `start_url: "/"`, `background_color`/`theme_color` from the industry theme tokens, icons 192 and 512 PNG under `priv/static/images/` (derive from the existing favicon or logo; maskable variant optional).
- Add `manifest.webmanifest` to `static_paths/0` in `lib/global_combat_web.ex`.
- `root.html.heex`: viewport becomes `width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content`; add `<link rel="manifest">`, `<meta name="apple-mobile-web-app-capable" content="yes">`, `<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">`, `<meta name="theme-color">` for light and dark via `media`.
- Keyboard inset: in `.MapViewport` or a tiny `.StageViewport` hook on `#game-board`, listen to `window.visualViewport` `resize` and set `style.height = visualViewport.height + "px"` on the wrapper while in stage mode; clear it on blur. This keeps the dock visible above the iOS keyboard.

### 4.7 CSS (`assets/css/app.css`)

- `.world-map { min-width: 40rem }` becomes `@media (min-width: 64rem)` only. Below `lg` the map is `width: 100%; height: 100%` inside the stage and the SVG gets `preserveAspectRatio="xMidYMid meet"` (already the default; state it explicitly).
- Below `lg`, `.world-map-count { font-size: 1.6em }` and `.world-map-order-amount` likewise, so counts stay legible at fit scale before the player zooms. Verify against the elements map viewBox as well.
- `.game-drawer` sheet styles, `::backdrop`, slide transition guarded by `prefers-reduced-motion`.
- Dock sheet: sticky bottom, `max-height: 45dvh`, scrolls internally; buttons at least 44px tall on touch.
- Status strip in stage mode: translucent `bg-surface/90` with `backdrop-filter: blur(6px)`.

### 4.8 Tests

LiveView and component tests (ExUnit, no browser):

- `game_layout_test.exs`: `stage` renders the `status/board/dock` grid areas and the dialog-wrapped players; without `stage` today's assertions hold; `:dock` renders inside the players rail above `lg`.
- `game_live_test.exs`: lens form is inside the status section; with an area selected the order panel is inside `[aria-label="Actions"]` and `#turn-controls` is absent; with no selection `#turn-controls` is in the dock; Quit is inside `#game-drawer`; amount input carries `inputmode="numeric"`; `step_amount` and `max_amount` update the rendered value and never call the engine; ended games do not set `stage`; the horizontal scroll assertions remain green.
- `world_map_test.exs`: wrapper carries `phx-hook=".MapViewport"`, `data-view-box`, `tabindex="0"`.
- `site_chrome_test.exs`: `immersive` hides the topbar and sidebar below `lg` and leaves them above.
- Controller test: `GET /manifest.webmanifest` returns 200 with `application/manifest+json`.

Manual verification (required in every PR that touches WP2 to WP5): screenshots from the Browser pane at 390x844 portrait and 844x390 landscape, light and dark, attached to the PR; a note of which real device was used if any. The local preview workflow is documented in the repo memory notes (render against a running dev stack or the design smoke page).

## 5. Work packages

Each package is one PR, sized for one engineer, and lists what it depends on. Keep tracker ids out of titles, bodies, and commits (the public repo scan rejects them).

### WP1 — Quick wins, no layout change

Depends on: nothing. Effort: half a day.

- Drop `.world-map` min-width below `lg`; bump count font size below `lg` (§4.7).
- Amount input attributes (§4.3), stepper and Max buttons with `step_amount`/`max_amount` handlers.
- Viewport meta with `viewport-fit=cover` and `interactive-widget=resizes-content`.
- Move the lens control into the `:status` slot.
- Tests: input attrs, handlers, lens placement, scroll assertions.

Done when: at 390px the whole map is visible without horizontal scroll, the numeric keypad opens for the amount field, and the desktop layout is visually unchanged apart from the lens control's new position.

### WP2 — Map pan and zoom

Depends on: nothing (can run in parallel with WP1). Effort: one day.

- `.MapViewport` hook per §4.4, wrapper attrs, CSS `touch-action`.
- Fit button in the status strip (`[data-map-fit]`).
- Session persistence of the viewport.
- Tests: wrapper attrs; manual: drag does not select, tap selects, pinch zooms about the fingers, chat message arriving does not reset zoom, replay still animates while zoomed.

Done when: on a phone every territory including the smallest islands can be zoomed to and tapped, and no gesture ever triggers a spurious `select_area`.

### WP3 — Stage layout and dock

Depends on: WP1. Effort: one to two days.

- `GameLayout` `stage` attr and `:dock` slot (§4.1); `SiteChrome` `immersive` (§4.2).
- `GameLive` slot placement per the table in §4.3; dock idle row and order panel; Quit into `:players`.
- Stage CSS, translucent status strip, dock sheet (§4.7).
- Design smoke page (`design_smoke_live.ex`) gains a `stage` example.
- Update `docs/design-boutique/LAYOUTS.md` game_layout row.
- Tests per §4.8 for layout, placement, ended-game fallback.

Done when: on a phone in play the page does not scroll, the map fills the space between the status strip and the dock, End Turn is always one tap away, and selecting a territory shows the order panel without scrolling.

### WP4 — Players drawer

Depends on: WP3. Effort: one day.

- `<dialog>` drawer, `.Drawer` hook, opener button with `aria-expanded`, unread dot (§4.5).
- Region bonuses, your orders, turn results, Quit, and the site nav links move into the drawer.
- Tests: drawer contains roster, chat form, Quit, nav links; opener attributes.

Done when: chat and roster are reachable from the top strip, focus is trapped while open and restored on close, and the desktop side rail is unchanged.

### WP5 — Fullscreen and installable web app

Depends on: WP3. Effort: half a day to one day.

- `.Fullscreen` hook and button; PWA manifest, icons, static path, root metas (§4.6).
- Keyboard inset handling via `visualViewport`.
- Tests: manifest served; manual: Android Chrome fullscreen toggle; iPhone add-to-home-screen launches without browser bars; typing an amount on iPhone keeps the Assign button visible.

Done when: Android users get true fullscreen from the button, iPhone users get it via home-screen install, and the keyboard never hides the dock.

### WP6 — QA and polish pass

Depends on: WP1 to WP5. Effort: half a day.

- Device matrix: iPhone Safari, Android Chrome, iPad portrait and landscape, desktop at `lg` boundary (1023px and 1024px).
- Accessibility check with VoiceOver on iOS: territory labels, dock buttons, drawer dialog name, status live region still announces turn changes.
- Confirm no regression in the finished-game and lobby screens.
- Record any follow-ups (landscape phone dock as a side column, region-lens labels at fit scale) as new issues, not in this PR.

## 6. Out of scope

- Native apps, push notifications, offline play.
- Rewriting the map geometry or moving to canvas/WebGL.
- Changing game rules or the order validation in `submit_order`.
- Redesigning the lobby or the game-over screen for phones beyond what `players_first` already does.
- Landscape-specific dock placement (recorded as a follow-up in WP6).

## 7. Open questions with the default taken

| Question | Default in this spec | Change if |
|---|---|---|
| Does `PlayerView` expose unassigned reinforcements? | Assume not; `Max` omitted in assign mode | It does: wire `Max` to it in WP1 |
| Should tablets in portrait (768px) get the stage? | Yes, anything below `lg` | Play testing shows the stacked layout is better on iPad |
| Default zoom on phones: fit whole map or fill height? | Fit whole map, then double tap | Players consistently double tap first thing; then start at 1.5x centred on the viewer's territories |
| Drawer side | Right | Left-handed feedback |
