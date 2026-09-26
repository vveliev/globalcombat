---
target: Game Over game screen
total_score: 20
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
timestamp: 2026-09-05T23-52-16Z
slug: lib-global-combat-web-live-game-live-ex
---
# Critique — Game Over state, `lib/global_combat_web/live/game_live.ex`

Method: dual-agent (A: design review · B: detector + browser). Target inspected live at http://localhost:11400/Game-25/ (finished game, viewer is the winner).

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|-----------|-------|-----------|
| 1 | Visibility of system status | 3 | "Turn 14 · Ended" is live, but the pill uses tone `done` (green status-online dot) for the loser too |
| 2 | Match system / real world | 1 | "Ended", "place 1", "Region Bonuses" on a finale; winner rendered through the eliminated branch |
| 3 | User control and freedom | 2 | Only exit is a bare "Back to Home" link; no rematch / new game |
| 4 | Consistency and standards | 2 | Only primary button on the finale is chat "Send"; banner uses off-token `rounded` + `border-divider`, Card uses radius-md + shadow |
| 5 | Error prevention | 2 | Finished board still takes orders: `select_area` guards on `:playing`, no `ended` check; order panel still renders |
| 6 | Recognition rather than recall | 2 | No legend on the board; owner colour decodable only via 12px dots in the rail |
| 7 | Flexibility and efficiency | 2 | 42 territory tab stops before the one link that matters; no "Play again" |
| 8 | Aesthetic and minimalist design | 2 | Everything one weight; Region Bonuses (rules reference) survives into the finale, 700px dead space beside it |
| 9 | Error recovery | 2 | Chat form clipped in the rail with no feedback |
| 10 | Help and documentation | 2 | "place" and score unexplained; score never reaches PlayerView |
| **Total** | | **20/40** | **Needs work** |

## Design Specificity Verdict
Category-interchangeable admin UI with a map in the content slot. The shell is the ERP admin shell, the status vocabulary is ERP lifecycle vocabulary, the finale is a border box with an 18px heading that carries less weight than the Region Bonuses card under it. The active brand theme (industry: Barlow Condensed / Barlow) never reaches the page: both layouts hardcode `font-sans` → Segoe UI/Helvetica Neue/Arial (measured live: body 16px Segoe UI stack). Deterministic scan: 0 findings, but the detector does not scan `.ex/.heex` natively; a `.tsx`-copy rescan also returned 0.

## Priority Issues
- [P0] Finished game still takes orders — `game_live.ex:253` matches `status: :playing` (also the status of an ended game); `handle_area_click/2` never checks `view.ended`; territories stay `role="button"` (`world_map.ex:187-200`). Fix: short-circuit on `ended`, add an `interactive` attr to `WorldMap.world_map`, clear selection when `ended` flips. → harden
- [P0] Chat "Send" button overflows the rail — measured: button right edge 1294px vs aside right 1260px vs viewport 1280px at desktop; the input has no `min-w-0`. Fix: `min-w-0 w-full`, stack the form or icon-button Send, add a real label and an empty state. → harden
- [P1] The finale has no hierarchy or emotion — `game_over/1` (`:546-564`): 18px h2, muted "You win!", inline standings, bare link. Fix: `font-heading` at `--heading-2`, "Victory / Defeat / {name} wins" headline, winner-colour rule via `--map-owner-fill`, ranked standings with swatches + territory counts, primary "Play again", hide Region Bonuses when ended, caption the board. → bolder, delight
- [P1] Brand typography never reaches the game — `game_layout.ex:47`, `admin_layout.ex:27` use `font-sans`; theme defines `--font-body: Barlow`, `--font-heading: Barlow Condensed` and fonts.css already loads them. Fix: shells use `font-body`, headings/Card headers use `font-heading`. → typeset
- [P2] Status vocabulary inverted for a game — green `done` dot for "Ended"; winner shown via eliminated branch as "place 1" with armies hidden; "place N" is engine vocabulary. Fix: finished roster presentation with ordinals, neutral pill or Victory/Defeat, "You won." / "You placed 2nd of 2." → clarify

## Persona Red Flags
- Sam (screen reader): `role="status" aria-live` present at initial render so outcome never announced; 42 territory tab stops on an unplayable board; chat input placeholder-only; no `page_title` → no h1.
- Morgan (mobile): sidebar nav (7 links, 273px) stacks above the game; document scrollWidth 857 vs 375 at mobile and 856 vs 768 at tablet (page scrolls horizontally, source: the `position:absolute` sr-only board table, width 824); map clipped to North America at 375.
- Riley (colour-blind): owner 1 blue-6 vs owner 2 green-5 close in lightness; only legend is the 12px dot; green "Ended" dot reads as "go".
- Returning legacy player: colour order preserved (ADR-0003) but the score computed at `engine/game.ex:440` is never shown.

## Minor Observations
- Off-token `rounded` at `:550`, `:482`, `:782`.
- `<ol>` with manual "1." prefixes under `flex`.
- Region Bonuses `min-w-[16rem]` in flex-wrap leaves the column two-thirds empty.
- Sidebar links have no active state; "Log Off" is a button styled as a link.
- Status strip is `--text-sm`: the turn number is the smallest type on the page.
- Dark theme: owner 6 (`gray-6`) on `gray-8` sea will nearly vanish; sr-only table is the mobile overflow source in both themes.
- Card header is an h2, structural peer of the outcome h2.
- No theme toggle exists on the game page.

## Questions to Consider
1. Where is the `:finished` view? finished games are already rehydrated on demand but the render still goes through `:playing`.
2. Whose room is this: winner's trophy room, loser's post-mortem, or the archive's record?
3. The board is the celebration. Why is it captioned by a Region Bonuses table?
4. The brand ships Barlow Condensed at 42px for exactly this moment. What stops "VICTORY" being the largest thing on the page?
