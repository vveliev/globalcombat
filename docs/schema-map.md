# MySQL → Ecto Schema Map

Source: `globalcombat MySql Schema.sql` (11 tables, 119 columns) + `gc_games MySql Schema.sql` (2 tables,
7 columns) = **13 tables, 126 columns**. Verified: `grep -c '^  \`' *.sql` → 119 + 7 = 126; this document's
per-column tables below contain exactly 126 rows (23+5+9+3+23+7+7+15+18+7+2 = 119, plus 4+3 = 7).

Target: `liveview/lib/global_combat/repo.ex` — already scaffolded as a **single** `Ecto.Repo` on
`Ecto.Adapters.MyXQL` (`liveview/config/dev.exs` → database `global_combat_dev`). The port stays on
MySQL/MariaDB; "utf8mb4" below is a literal MySQL charset migration, not a stand-in for Postgres.
No migrations exist yet (`liveview/priv/repo/migrations/` is empty except `.formatter.exs`) — this doc is
the plan those migrations get written from.

Method: every decision below is grounded either in the DDL itself or in a live code path (`grep`ped across
`Web/`, `GlobalCombat.Core/`), not guessed. Where a column has **zero** references in the C# codebase, that
is stated explicitly with the evidence, because "no code reads this" is itself a decision input.

---

## 1. One database or two?

**Decision: merge into the single already-scaffolded `GlobalCombat.Repo` (one MySQL database), not two
repos.** Reasons, in order of weight:

1. The scaffold already committed to exactly one `Ecto.Repo`. Standing up a second repo for `gc_games`
   would be new infrastructure the port doesn't otherwise need.
2. `gc_games` is tiny (2 tables, 7 columns) and one of its tables (`game`) is the **only live** `game` table
   in the whole system — see §1.1. There's no independent bounded context here to justify a separate
   database; `gc_games` reads as an ops-driven split (maybe a permissions/backup boundary in production),
   not a domain boundary.
3. The app already crosses this boundary at runtime: `Web/Models/GameServer.cs` opens a second
   `DBConnection` (`GameServer.CreateDB()`, keyed off the `"Global Combat Games"` connection string) purely
   to reach `gc_games`, while every other query in the same methods uses the default `globalcombat`
   connection — e.g. `GameServer.OnMessage`/`OnEliminated` mix both inside one logical operation. A single
   Ecto repo removes that split and lets those operations be one transaction instead of two uncoordinated
   connections.

**Caveat this decision surfaces, not hides:** both schemas independently declare a table named `game`
(and `player`), with *completely different columns*. They cannot both become an Ecto schema named `Game` in
one repo. §1.1 explains why that collision is actually easy to resolve.

### 1.1 The `game`/`player` name collision is not really a collision — one side is dead

- `gc_games.game` (`id`, `status`, `serialized`, `private`) and `gc_games.player`
  (`game_id`, `account_id`, `isInvite`) are the **live** tables: every read/write to a table named `game` or
  `player` anywhere in `Web/Models/GameServer.cs` goes through `GameServer.CreateDB()`, which connects to
  `gc_games` (confirmed by reading every call site in `GameServer.cs`: `SaveNewGame`, `SaveGame`, `GetGame`,
  `GetNewGames`, `GetPlayerGames`, `GetActiveGames`, `PlayerJoined`, `PlayerUnjoined`, `PlayerInvited`,
  `KillGame` — all use `CreateDB()`, none use the default `globalcombat` connection for these tables).
- `globalcombat.game` (23 columns: `game_name`, `start_time`, `map_name`, `turn`, `fogged`, `attack_order`,
  `realtime`, `tourney_id`, `config_string`, …) and `globalcombat.player` (15 columns: `name`, `player_num`,
  `done`, `armies`, `score`, `rating`, …) are **not referenced by any `.cs` file with a default (non-`CreateDB`)
  connection** — grepped `from game`/`into game`/`update game`/`from player`/`into player` across the whole
  repo; every hit outside `GameServer.CreateDB()` calls is a comment or resolves to `tourneygame`.
  These columns are the *old, pre-serialization* relational shape of a game. That's confirmable, not just
  absence-of-evidence: `GlobalCombat.Core/Game.cs`'s live in-memory model has `[ProtoMember]` fields named
  `GameName`, `MapName`, `TurnLength`, `MaxPlayers`, `IsFogged`, `ReverseAttackOrder`, `Turn`,
  `PreviousTurnTime`, `LastTurnTime`, `StartTime`, `EndTime`, `TourneyId` — a near 1:1 match to
  `globalcombat.game`'s column list — and `GlobalCombat.Core/Player.cs` similarly mirrors
  `globalcombat.player`'s columns (`Number`, `Done`, `Areas`, `Armies`, `Score`, `ScoreExpected`, `Rating`,
  `RatingChange`). Those fields now live **inside the ProtoBuf blob** in `gc_games.game.serialized`
  (out of scope — GIF-25 owns it), and `globalcombat.game`/`globalcombat.player` are what they were
  superseded from. Same story for `globalcombat.area` vs. `GlobalCombat.Core/Area.cs` (§3.4).

**Decision:** the live `game`/`player` tables become real Ecto schemas, named to avoid the collision:
`gc_games.game` → table `games`, schema `GlobalCombat.Games.Game`; `gc_games.player` → table
`game_players`, schema `GlobalCombat.Games.GamePlayer`. The dead `globalcombat.game`, `globalcombat.player`,
`globalcombat.area` do **not** get Ecto schemas — nothing in the app would ever query them through one. If
their historical rows have retention value, import them unmodified into differently-named tables
(`legacy_game`, `legacy_player`, `legacy_area`) with no schema module and no app code touching them; whether
that retention is actually required is a records-retention question for Dev, not a schema question — flagging
it rather than deciding it silently. Same treatment applies to `cheat` and `ledger` — see §3.5 and §3.7,
both entirely unreferenced by any code path (zero grep hits for `from cheat`/`into cheat`/`from ledger`/
`into ledger`/`ledger.status` etc. across `.cs`), i.e. dead on arrival even in the *current* app, not just
superseded.

**AUTO_INCREMENT implication:** the id sequence that must be preserved for `/Game-{id}/` URLs is
`gc_games.game`'s `AUTO_INCREMENT=751207` (the live table), **not** `globalcombat.game`'s `684316`. Both
numbers exist in the DDL; only one of them is the counter that matters. The Ecto migration for the `games`
table must seed the MySQL auto-increment starting value at 751207 post-import, or every future game gets an
id that collides with a URL some pre-migration game already used.

---

## 2. Cross-cutting decisions (apply across tables)

### 2.1 `latin1`/`latin1_general_ci` → `utf8mb4`: not a naive `CONVERT`, and here's proof why

Every text-bearing column across both schemas is tagged `CHARACTER SET latin1 COLLATE latin1_general_ci`.
The instinct is "MySQL can `ALTER TABLE ... CONVERT TO CHARACTER SET utf8mb4`, done." **That is provably
wrong for this data.** `Web/Lib/DBConnection.cs`'s `AddSlashes` — the escaping function every raw-SQL insert
in the codebase runs free-text through before splicing it into a query string — explicitly escapes four
non-ASCII Unicode punctuation marks:

```csharp
text = text.Replace("’", "\\’"); // unicode 8217 "Closing Single Quote"
text = text.Replace("‘", "\\‘"); // unicode 8216 "Opening Single Quote"
text = text.Replace("′", "\\′"); // unicode 8242 "Prime"
text = text.Replace("ʹ", "\\ʹ"); // unicode 697 #02b9 "MODIFIER LETTER PRIME"
```

None of these characters exist in latin1 (ISO-8859-1 only covers U+0000–U+00FF; U+2019/U+2018/U+2022/U+02B9
are outside that range entirely). The only way this code path makes sense is if the .NET
MySQL driver is sending UTF-8-encoded bytes over the wire into a column MySQL believes is latin1 — MySQL,
seeing no charset mismatch it's configured to reject, stores the raw UTF-8 byte sequence uninterpreted
(each byte becomes its own latin1 codepoint on read-back), and the same .NET driver reads it back the same
way, so round-tripping through *this app* looks correct while the bytes on disk are actually UTF-8, not
latin1. This is the standard "double-encoding" failure mode for old ASP.NET/MySQL pairings, and the escaping
code is direct evidence it has already happened to production data (message text, account names, tourney
descriptions — anywhere free text flows through `AddSlashes`).

**Consequence for the migration:** a blind `CONVERT ... USING latin1` → `utf8mb4` would re-interpret
already-valid UTF-8 byte sequences *as if they were latin1*, corrupting them a second time (mojibake on top
of mojibake). The correct migration is per-row: read the raw bytes, check whether they already form valid
UTF-8; if so, copy through as-is; if not, decode as latin1/cp1252 and re-encode to UTF-8. This can't be
verified as globally safe from the DDL or the code alone — it requires running that check against real
row bytes, which needs the production dump the issue already notes is a separate ask to Dev. Recorded here
as the exact validation step that ask should perform, not deferred silently.

Applies to every `varchar`/`char`/`text` column across all 13 tables — see the per-table decision, marked
`utf8mb4 (needs byte-validation pass)`.

### 2.2 `int(11)` unix timestamps: two different consumption patterns, one decision per table

Two distinct ways the codebase reads these columns, found by grep:

- **Plain integer comparison/arithmetic** — e.g. `Utility.cs`'s `UnixTimestamp`/`FromUnixTimestamp` pair
  used in `select ... where last_on > {0}` (`HomeController.Stats`), `where time > {0}` (`GameServer.CanSend`).
  This ports to an Ecto integer field with zero query-shape change.
- **SQL-side calendar bucketing via `FROM_UNIXTIME()`** — `HomeController.cs`'s admin stats dashboard:
  `SELECT Date(FROM_UNIXTIME(datetime)) Day, Count(*) ... from Account_login ... group by Date(FROM_UNIXTIME(datetime))`,
  same pattern for `signed_up`. This is a query shape that doesn't exist if the column becomes an opaque
  Ecto `:integer` — MySQL's `FROM_UNIXTIME` still works against an integer column, so this isn't blocked,
  but if the column is converted to `:utc_datetime` the query must be rewritten to `DATE(datetime)` (no
  `FROM_UNIXTIME` needed) rather than left as-is.

**Decision:** convert to `:utc_datetime` only on columns that are both **live** and **currently read** —
`account.last_on`, `account.signed_up`, `account_login.datetime`, `message.time`, `tourney.create_time`,
`tourney.start_time`, `tourney.end_time`. These all get real value from being real datetimes in Ecto
(sorting, `Ecto.Query` date functions, no more manual `Utility.FromUnixTimestamp` marshaling), and the admin
stats queries need rewriting during the port anyway since raw SQL doesn't survive a straight Ecto port.
Leave every timestamp column on the dead tables (`globalcombat.game.start_time`/`end_time`/
`created_time`/`prev_turn_time`/`last_turn_time`, `globalcombat.player` has none, `ledger.time`) as plain
`:integer` if imported at all — converting them buys nothing since no live code reads them, and effort spent
reconciling their format is effort not spent on tables that matter. Per-column call in each table's section
below.

### 2.3 Enums: `Ecto.Enum` for real multi-value enums, `:boolean` for binary `True`/`False` ones

MySQL `enum('True','False')` columns are semantically booleans wearing an enum's clothes. Ecto has no native
MySQL-enum type either way, so the choice is between `Ecto.Enum` (keeps the string values, adds
enum-membership validation) and `:boolean` (matches how the code actually uses them). Every `enum('True','False')`
column across both schemas is compared/assigned as a two-state flag in the C# (e.g.
`(string)row["admin"] == "True"`, `readflag = 'False'`) — nothing branches on a third state, because there
isn't one. **Decision: map every `enum('True','False')` column to `:boolean`.** Migration: `'True' → true`,
`'False' → false`, both directions reversible (`CASE WHEN col THEN 'True' ELSE 'False' END` regenerates the
original bytes exactly, so this is safe to do without data loss). The nine columns this applies to:
`account.info_visible`, `account.admin`, `account_login.adminused`, `game.fogged`, `game.realtime`,
`tourney.doubleelim`, `tourney.AutoStart`, `tourney.Recurring`, `message.readflag`.

`game.attack_order enum('Largest','Smallest')` is the same binary shape but isn't literally `True`/`False`.
It has a direct analog already decided upon in the live blob model: `GlobalCombat.Core/Game.cs` stores this
as `public bool ReverseAttackOrder` (`[ProtoMember(8)]`). **Decision: mirror that** — map to `:boolean`
named `reverse_attack_order`, `'Largest' → false` (the DDL default), `'Smallest' → true`. (This table is
dead per §1.1, so the decision is recorded for consistency/if it's ever revived, not because it needs a
live migration today.)

Real multi-value enums (kept as `Ecto.Enum`, values mapped explicitly to preserve the exact legacy strings
via `values: [atom: "String"]` rather than relying on Elixir's snake_case default, since several source
values contain spaces or mixed case that don't round-trip through default atom naming):

| Column | Values | Ecto.Enum mapping |
|---|---|---|
| `account.status` | `Civilian, Enlisted, Comissioned, Admin, SuperAdmin, Discharged, Disabled` | `civilian: "Civilian", enlisted: "Enlisted", comissioned: "Comissioned", admin: "Admin", super_admin: "SuperAdmin", discharged: "Discharged", disabled: "Disabled"` (typo `Comissioned` preserved verbatim — it's the actual stored string) |
| `account.forward_emails` | `GameStarts, AllGame, All, None, GameAll` | `game_starts: "GameStarts", all_game: "AllGame", all: "All", none: "None", game_all: "GameAll"` |
| `tourney.status` | `New, Running, Finished` | `new: "New", running: "Running", finished: "Finished"` |
| `ledger.status` (dead, §3.7) | `Pending, Paid, Declined, Canceled` | `pending: "Pending", paid: "Paid", declined: "Declined", canceled: "Canceled"` |
| `ledger.type` (dead, §3.7) | `Deposit, Withdrawal, Prize, Enlistment Fee, Tourney Fee, Game Fee` | `deposit: "Deposit", withdrawal: "Withdrawal", prize: "Prize", enlistment_fee: "Enlistment Fee", tourney_fee: "Tourney Fee", game_fee: "Game Fee"` |

`account.status`'s only *currently read* branch is `IsDisabled = status == "Disabled"`
(`Web/Models/Account.cs:77`) — the other six values are written (registration defaults to `Civilian`) but
never compared against in the C# outside that one check. `Ecto.Enum` is still the right call over a plain
boolean here because the column genuinely carries 7 distinct values on disk today (rank/role tiers), even
though only one is currently load-bearing in application logic.

### 2.4 `account.password` — storage facts for GIF-29, not an algorithm choice

Out of scope to *decide* the hashing algorithm (GIF-29's call), but the `account` table's shape constrains
what GIF-29 can choose, and that's worth recording precisely:

- `password varchar(30) CHARACTER SET latin1 COLLATE latin1_general_ci` — 30 bytes max.
- Every write path stores the raw password: `BaseController.CreateAccount` inserts
  `DBConnection.AddSlashes(password)` directly; `AccountController.ModifyPassword`/`ResetPassword` update
  with `DBConnection.AddSlashes(newPassword)` directly. **No hashing call appears anywhere on a write path.**
  Passwords are plaintext in this column today, column-width-visible fact, not inference.
- `Web/Lib/UserPage.cs`'s `CalculateHash` (SHA-512 + hardcoded salt `"s&~D$L{a8_"`, base64-encoded output)
  is referenced exactly once, as a **read-side fallback** in `AccountController.Login`:
  `password != accountRow["password"] && CalculateHash(password) != accountRow["password"]`. SHA-512 is 64
  bytes; base64-encoding 64 bytes always produces 88 characters (with padding). An 88-character value cannot
  fit in `varchar(30)` — so `CalculateHash`'s own output has never actually been the value on the right-hand
  side of that comparison for any row this application itself wrote; the fallback branch is effectively dead
  for this schema, kept perhaps for compatibility with some other never-seen import path.
- **What this means for GIF-29:** the 30-byte column rules out storing a bcrypt hash (~60 chars), Argon2id
  (~95+ chars depending on params), or even a hex-encoded SHA-256 (64 chars) in that column as-is — every
  realistic modern hash format exceeds 30 bytes. Whatever algorithm GIF-29 picks, the `password` column
  needs to widen (`varchar(255)` or `text` is the safe default for all common hash output lengths) as part
  of that change; it isn't optional based on algorithm choice.

### 2.5 `game.Serialized` (the ProtoBuf blob) — explicitly out of scope

`gc_games.game.serialized longblob` is GIF-25's, not this issue's. Recorded here only for completeness in
the per-column table (§3.13) with `decision: out of scope (GIF-25)`. One fact worth surfacing though: under
GIF-25's gRPC-front-the-.NET-engine option, Phoenix may never issue a SQL read against this column at all —
the .NET side would own `gc_games.game.serialized` entirely and hand Phoenix decoded game state over gRPC,
in which case the Ecto schema for `games` might legitimately omit the `serialized` field rather than map it
to `:binary`. That's a consequence of which GIF-25 option gets picked, not a decision this doc makes.

### 2.6 What `DBConnection.cs`'s string-concatenation implies beyond the DDL

The issue asks specifically to flag anywhere the raw-SQL concatenation pattern implies a type/format
assumption the DDL alone wouldn't show. Beyond encoding (§2.1) and the password fallback (§2.4):

- **Int columns used as ad-hoc booleans, invisibly.** `account.OptOut int(11) DEFAULT '0'` is written via
  `db.Execute("update Account set OptOut = 1 where Id = {0}", account)` (`HomeController.cs:308`) — a plain
  `int(11)` in the DDL, but the only value ever written to it besides the default is `1`. Same shape for
  `gc_games.game.private int(11) DEFAULT '0'`, written as
  `Private = (game.TourneyId != 0 || game.IsPrivate ? 1 : 0)`. Neither the DDL nor a cursory read of the
  type tells you these are booleans; only the call sites do. Both get `:boolean` in the Ecto mapping
  (§3.1, §3.13) rather than `:integer`, even though MySQL's `int(11)` gives no hint of that on its own.
- **`disabled_by` is dual-purpose, not a flag.** `account.disabled_by mediumint(8) DEFAULT '0'` reads as
  "0 = not disabled" in `AccountController.Login` (`if (disabled_by != 0) → blocked`), but the value written
  when disabling an account is the **acting admin's account id**
  (`HomeController.cs:97`: `update account set disabled_by = " + Account.Id`) — it's simultaneously a
  disabled-flag and an audit trail of who disabled the account. Mapping it to `:boolean` would silently drop
  that audit data; it must stay `:integer` (nilable-by-convention `0`, or better, migrated to a real nullable
  FK to `account.id` with `nil` meaning "not disabled" — a schema improvement worth doing during the port
  since the self-referential FK now expresses the invariant the raw `int` never did).
- **`account.OptOutKey`** is inserted as a random int at account-creation time
  (`BaseController.CreateAccount`) and compared exactly against a query-string value on the opt-out link
  (`HomeController.cs:301`) — it's a capability token, not a counter; `:integer` is fine but it should never
  be treated as sequential/incrementing, worth a code comment carried into the Ecto schema.
- **`account.session_id`/`account.session_exp`** are dead columns — `Web/Models/Account.cs` has them
  commented out (`//result.SessionId = (int)row["session_id"];`) — session identity actually lives in
  ASP.NET's own session (`AccountController.cs:211`: `account.SessionKey = HttpContext.Session.Id`), not in
  these columns. Confirmed unread anywhere else too. Carried into the per-column table as unused (§3.1).
- **`account.cc_info`/`account.visible_cc_info`** (credit-card info, plaintext `varchar(255)`) have **zero**
  references anywhere in `.cs` — combined with `ledger` (§3.7) being entirely unreferenced too, this reads
  as a payment/monetization subsystem that was already ripped out of the live app before this snapshot,
  leaving the columns behind. Worth flagging as a data-sensitivity item regardless of dead-code status: if
  the production table actually holds real cardholder data in those bytes, that's a PCI-relevant fact for
  whoever handles the historical-data decision in §1.1, independent of whether the port ever reads the
  column again.

---

## 3. Per-table column decisions

Legend for the **Decision** column: Ecto type mapped to, or `dead — <reason>` for columns imported at most
as inert historical data with no schema/app-code binding, per §1.1.

### 3.1 `globalcombat.account` (23 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `int(11)` PK AUTO_INCREMENT | `:id` | AUTO_INCREMENT=99371 — preserve on import, same reasoning as §1.1's game id. |
| `name` | `varchar(30)` latin1 | `:string`, utf8mb4 (needs byte-validation pass, §2.1) | Login name; unique in practice (checked via `select name from account where name=`) — add a DB unique index, the legacy schema has none (only a non-unique `KEY name`). |
| `password` | `varchar(30)` latin1 | `:string`, width TBD by GIF-29 | See §2.4 — column must widen regardless of algorithm chosen. |
| `email` | `varchar(255)` latin1 | `:string`, utf8mb4 | Used for login (`where name = '{0}' or email = '{0}'`) as well as contact. |
| `cc_info` | `varchar(255)` latin1 | `dead — zero code references (§2.6); possible PCI-sensitive historical data, flag for Dev before drop` | |
| `visible_cc_info` | `varchar(255)` latin1 | `dead — zero code references (§2.6)` | Same subsystem as `cc_info`. |
| `info_visible` | `enum('True','False')` | `:boolean` | §2.3. |
| `wins` | `smallint(8) unsigned` | `:integer` | Ecto has no unsigned int type; enforce non-negative via a DB check constraint if that invariant matters, since the type itself won't carry it forward. |
| `games` | `smallint(8) unsigned` | `:integer` | Same unsigned note as `wins`. |
| `last_on` | `int(11)` unix ts | `:utc_datetime` | §2.2 — live, read for DAU/MAU stats. |
| `num_logins` | `int(11)` | `:integer` | Incremented on every login. |
| `session_id` | `int(11)` | `dead — commented out in Account.Load (§2.6)` | |
| `session_exp` | `int(11)` unix ts | `dead — commented out in Account.Load (§2.6)` | |
| `last_ip` | `varchar(15)` latin1 | `:string` (consider `EctoNetwork.INET` if adding real IP typing) | latin1-safe already (dotted-quad/IPv6 text), but no reason not to standardize to utf8mb4 with the rest. |
| `signed_up` | `int(11)` unix ts | `:utc_datetime` | §2.2 — live, read for signup-rate stats. |
| `status` | `enum(7 values)` | `Ecto.Enum` | §2.3 table. |
| `disabled_by` | `mediumint(8)` | `:integer` (consider nullable self-FK to `account.id`) | §2.6 — dual-purpose flag+audit column. |
| `forward_emails` | `enum(5 values)` | `Ecto.Enum` | §2.3 table. |
| `OptOut` | `int(11)` | `:boolean` | §2.6 — only ever written as 0/1. |
| `OptOutKey` | `int(11)` | `:integer` | §2.6 — capability token, not sequential. |
| `rating` | `smallint(11) unsigned` | `:integer` | Elo-style rating; default 8500, drives `Account.Rank` thresholds (8400/8750/9100/9500/10000) — keep threshold logic identical, it's untouched by the type change. |
| `referred_by` | `mediumint(8)` | `:integer` (consider nullable self-FK to `account.id`) | Set at registration from a `ReferredBy` form field; `0` means no referrer. |
| `admin` | `enum('True','False')` | `:boolean` | §2.3 — distinct from `status='Admin'`; this is the actual `IsAdmin` flag checked in code (`Account.cs:64`), `status`'s `Admin` value is not what gates admin access. |

### 3.2 `globalcombat.account_login` (5 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `account_id` | `int(11)`, part of composite PK | `:integer`, FK to `account.id` | |
| `datetime` | `int(11)` unix ts, part of composite PK | `:utc_datetime` | §2.2 — read via `FROM_UNIXTIME()` for daily login-count stats; that query needs rewriting to `DATE(datetime)` post-migration, not left as-is. |
| `ipaddress` | `varchar(255)` latin1 | `:string`, utf8mb4 | Looked up directly (`where ipaddress = '{0}'`) in the admin IP-lookup page — plain string match, no need for a network type. |
| `browser` | `varchar(255)` latin1 | `:string`, utf8mb4 | User-agent string; free text, definitely a §2.1 candidate for byte corruption given how wide the char range in real UA strings is. |
| `adminused` | `enum('True','False')` | `:boolean` | §2.3 — records whether the login was performed by an admin (`insert ... adminused, 'False'` hardcoded at every real call site found — worth checking whether admin-impersonation-login actually sets this anywhere, or whether it's permanently dead-false in practice; out of scope to resolve here, flagging as a possible latent bug). |

### 3.3 `globalcombat.cheat` (3 columns) — dead, zero code references

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `account_id` | `int(10) unsigned`, part of composite PK | `dead — no `.cs` file references this table at all (no `from cheat`/`into cheat` anywhere)` | |
| `game_id` | `int(10) unsigned` | `dead` | |
| `datetime` | `int(11)` unix ts | `dead` | |

No anti-cheat feature currently exists in the reviewed code; this table predates or was built for a feature
that was never wired up (or was removed) before this snapshot.

### 3.4 `globalcombat.area` (9 columns) — dead, superseded by the blob (§1.1)

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `game_id` | `int(11)`, part of composite PK | `dead — no code references outside `GlobalCombat.Core/Area.cs`'s in-memory (ProtoBuf) shape` | |
| `area` | `int(11)`, part of composite PK | `dead` | Matches `Area.Number`. |
| `owner_id` | `int(11)` | `dead` | Matches `Area.Owner` (a `Player` reference in the live blob). |
| `armies` | `int(11)` | `dead` | Matches `Area.Armies`. |
| `com` | `int(11)` | `dead` | Matches `Area.Command` (the `Command` enum: None/Transfer/Attack). |
| `com_target` | `int(11)` | `dead` | Matches `Area.Target`. |
| `com_amount` | `int(11)` | `dead` | Matches `Area.Amount`. |
| `new_armies` | `int(11)` | `dead` | Matches `Area.AssignedArmies`. |
| `region` | `int(11)` | `dead` | Region membership now comes from the static `MapInfo`/`AreaInfo` catalog (`GlobalCombat.Core/MapInfo.cs`), not a per-row DB column. |

### 3.5 `globalcombat.game` (23 columns) — dead, superseded by the blob (§1.1)

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `int(11)` PK AUTO_INCREMENT | `dead` | AUTO_INCREMENT=684316 — **not** the counter to preserve; see §1.1, `gc_games.game`'s 751207 is the live one. |
| `game_name` | `varchar(30)` latin1 | `dead` | Matches `Game.GameName`. |
| `start_time` | `int(11)` unix ts | `dead` | Matches `Game.StartTime` (a `DateTime` in the live blob already — this column's format is moot). |
| `end_time` | `int(11)` unix ts | `dead` | Matches `Game.EndTime`. |
| `status` | `int(11)` | `dead` | Distinct from `gc_games.game.status`, which is live. |
| `owner_num` | `mediumint(8)` | `dead` | No corresponding `Game.cs` field found; likely predates the current player-list model. |
| `armies` | `int(11)` | `dead` | No corresponding `Game.cs` field. |
| `map_name` | `varchar(30)` latin1 | `dead` | Matches `Game.MapName` (now an enum: `Original`/`Elements`). |
| `max_players` | `tinyint(4)` | `dead` | Matches `Game.MaxPlayers`. |
| `created_time` | `int(11)` unix ts | `dead` | No direct `Game.cs` equivalent found (closest is `Started`/`StartTime`). |
| `cur_players` | `tinyint(11)` | `dead` | Derivable from `Game.Players.Count` in the live model. |
| `turn` | `smallint(4)` | `dead` | Matches `Game.Turn`. |
| `prev_turn_time` | `int(11)` unix ts | `dead` | Matches `Game.PreviousTurnTime`. |
| `last_turn_time` | `int(11)` unix ts | `dead` | Matches `Game.LastTurnTime`. |
| `turn_length` | `smallint(5)` | `dead` | Matches `Game.TurnLength`. |
| `passkey` | `int(11)` | `dead` | No corresponding `Game.cs` field found. |
| `fogged` | `enum('True','False')` | `dead` | Matches `Game.IsFogged` (bool in the live model — confirms the §2.3 boolean call would've been right had this table been live). |
| `min_armies` | `tinyint(4)` | `dead` | Matches `Game.MinimumArmies`. |
| `min_ranking` | `smallint(6)` | `dead` | No corresponding `Game.cs` field found. |
| `attack_order` | `enum('Largest','Smallest')` | `dead` | Matches `Game.ReverseAttackOrder` (bool) — see §2.3's boolean mapping call. |
| `realtime` | `enum('True','False')` | `dead` | No corresponding `Game.cs` field found — this one may have been dead even before the blob model, not just superseded. |
| `tourney_id` | `mediumint(8)` | `dead` | Matches `Game.TourneyId`. |
| `config_string` | `varchar(255)` latin1 | `dead` | No corresponding `Game.cs` field found. |

### 3.6 `globalcombat.ledger` (7 columns) — dead, zero code references

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `mediumint(8) unsigned` PK AUTO_INCREMENT | `dead — no `.cs` file references this table` | AUTO_INCREMENT=7189. |
| `account` | `mediumint(8) unsigned` | `dead` | Would-be FK to `account.id`. |
| `status` | `enum(4 values)` | `dead` | §2.3 table has the mapping recorded in case this is ever revived. |
| `type` | `enum(6 values)` | `dead` | §2.3 table. |
| `item_id` | `mediumint(8) unsigned` | `dead` | |
| `time` | `int(11)` unix ts | `dead` | |
| `amount` | `int(11)` | `dead` | Same dead payment subsystem as `account.cc_info` (§2.6) — enlistment/tourney/game fees, deposits, withdrawals. |

### 3.7 `globalcombat.message` (7 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `int(11)` PK AUTO_INCREMENT | `:id` | AUTO_INCREMENT=14292785. |
| `to_id` | `int(11)` | `:integer` | Not a strict FK to `account.id` — game-broadcast messages use `-game.Id` as a sentinel recipient (`GameServer.OnMessage`: `SendMessage(db, -game.Id, ...)`), and account id `1` is the reserved System account per the seed comment in the DDL. Both conventions must be preserved verbatim; a real FK constraint would break the negative-id broadcast convention. |
| `from_id` | `int(11)` | `:integer` | Same negative-id convention as `to_id`. |
| `time` | `int(11)` unix ts | `:utc_datetime` | §2.2 — live, used both for `order by id desc`-style recency and the `CanSend` spam-guard window check. |
| `text` | `text` latin1 | `:string`, utf8mb4 (needs byte-validation pass) | Free-form chat/mail text — the column most likely to actually contain the smart-quote/prime characters `AddSlashes` escapes (§2.1). |
| `readflag` | `enum('True','False')` | `:boolean` | §2.3. |
| `deleted` | `tinyint(1)` | `:boolean` | Type already boolean-shaped, unlike the enum columns. **Unread anywhere in the reviewed code** — `HomeController.cs` has the only related logic (`DeleteMessage`/`DeleteAll`) entirely commented out, suggesting a soft-delete feature that was scaffolded (this column) but never finished before being ripped back out. Carry the column forward as `:boolean` since the type is unambiguous, but note it's presently inert. |

### 3.8 `gc_games.game` (4 columns) — live (see §1.1 for why this is the canonical `game` table)

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `int(11)` PK AUTO_INCREMENT | `:id` | AUTO_INCREMENT=751207 — **this** is the counter `/Game-{id}/` URLs depend on; preserve on import (§1.1). |
| `status` | `int(11)` | `:integer` | Read via `select Id from game where status = 0 and private = 0` (open-games list) and `status = 1` (admin active-game count) — small closed set of integer states used as filters; kept `:integer` rather than `Ecto.Enum` since the DDL gives no named value list to map against (unlike the `enum(...)` columns elsewhere) and inventing names here would be a guess, not a decision grounded in evidence. |
| `serialized` | `longblob` | out of scope (GIF-25), possibly `:binary` or omitted entirely | §2.5. |
| `private` | `int(11)` | `:boolean` | §2.6 — written only as 0/1 (`(game.TourneyId != 0 \|\| game.IsPrivate ? 1 : 0)`). |

### 3.9 `gc_games.player` (3 columns) — live (see §1.1)

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `game_id` | `int(11)`, part of composite PK | `:integer`, FK to `games.id` | |
| `account_id` | `int(11)`, part of composite PK | `:integer`, FK to `account.id` | |
| `isInvite` | `tinyint(1)` | `:boolean` | Already boolean-shaped in the DDL; distinguishes an accepted seat (`isInvite=0`, inserted by `PlayerJoined`) from a pending invite (`isInvite=1`, inserted by `PlayerInvited`, cleared by `PlayerUnjoined`/`GameStart`'s bulk delete). |

### 3.10 `globalcombat.player` (15 columns) — dead, superseded by the blob (§1.1)

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `game_id` | `mediumint(8) unsigned`, part of composite PK | `dead — no code references outside `GlobalCombat.Core/Player.cs`'s in-memory shape` | |
| `id` | `int(8)` | `dead` | Semantics ambiguous from the DDL alone (default `0`, not auto-increment, separate from both `account_id` and `player_num`) — no live code exists to disambiguate it either; recorded as unresolved rather than guessed. |
| `name` | `char(30)` latin1 | `dead` | Matches `Player.Name`. |
| `player_num` | `tinyint(8) unsigned`, part of composite PK | `dead` | Matches `Player.Number`. |
| `prev_move` | `smallint(8) unsigned` NULL | `dead` | No corresponding `Player.cs` field found. |
| `last_move` | `smallint(8) unsigned` NULL | `dead` | No corresponding `Player.cs` field found. |
| `done` | `tinyint(4)` | `dead` | Matches `Player.Done` (bool in the live model). |
| `new_armies` | `int(11)` | `dead` | Matches `Player.UnassignedArmies`. |
| `armies` | `int(11)` | `dead` | Matches `Player.Armies`. |
| `areas` | `tinyint(8) unsigned` | `dead` | Matches `Player.Areas`. |
| `status` | `tinyint(4)` | `dead` | No corresponding `Player.cs` field found (closest concept is `Place`/`IsEliminated`). |
| `score_expected` | `float(7,5)` | `dead` | Matches `Player.ScoreExpected` (a `double` in the live model). |
| `score` | `float(7,5)` | `dead` | Matches `Player.Score`. |
| `rating` | `smallint(11) unsigned` | `dead` | Matches `Player.Rating`. |
| `rating_change` | `smallint(4)` | `dead` | Matches `Player.RatingChange`. |

### 3.11 `globalcombat.tourney` (18 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `id` | `mediumint(8)` PK AUTO_INCREMENT | `:id` | AUTO_INCREMENT=4978. |
| `name` | `varchar(255)` latin1 | `:string`, utf8mb4 | |
| `description` | `text` latin1 | `:string`, utf8mb4 (needs byte-validation pass) | Free text, same §2.1 risk as `message.text`. |
| `status` | `enum(3 values)` | `Ecto.Enum` | §2.3 table. |
| `players` | `smallint(5)` | `:integer` | Target player count. |
| `curplayers` | `smallint(5)` | `:integer` | Current signed-up count. |
| `create_time` | `int(10)` unix ts | `:utc_datetime` | §2.2 — live, loaded via `Tourney.Load` into a `DateTime`. |
| `start_time` | `int(10)` unix ts | `:utc_datetime` | §2.2 — same. |
| `end_time` | `int(10)` unix ts | `:utc_datetime` | §2.2 — same. |
| `gamesize` | `tinyint(3)` | `:integer` | Players per bracket game. |
| `winners` | `tinyint(3)` | `:integer` | Winners advancing per game. |
| `doubleelim` | `enum('True','False')` | `:boolean` | §2.3. |
| `kitty` | `smallint(5)` | `:integer` | Prize pool — tied to the same dead payment subsystem as `ledger`/`cc_info`, but the column itself is written on tourney creation, so it's live *data*, just feeding a feature (payouts) with no other live code path found. |
| `cost` | `smallint(6)` | `:integer` | Entry fee — same caveat as `kitty`. |
| `Options` | `varchar(255)` latin1 | `:string`, utf8mb4 | Freeform config string, opaque to the schema. |
| `AutoStart` | `enum('True','False')` | `:boolean` | §2.3. |
| `Recurring` | `enum('True','False')` | `:boolean` | §2.3. |
| `OptionGameId` | `int(11)` | `:integer` | |

### 3.12 `globalcombat.tourneygame` (7 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `tourney_id` | `int(11)` | `:integer`, FK to `tourney.id` | |
| `game_id` | `int(11)` PK | `:integer`, FK to `games.id` | Note: FK target is the **live** `games` table (`gc_games.game`), not the dead `globalcombat.game` — this is the clearest concrete example of the §1.1 collision mattering for a real relationship, not just naming. |
| `game_num` | `int(11)` | `:integer` | Position within the bracket. |
| `round` | `int(11)` | `:integer` | Bracket round number. |
| `winners` | `int(11)` | `:integer` | Per-game winner count (default 2 — double-elimination default). |
| `winner_round` | `int(11)` | `:integer` | Bracket-advancement pointer. |
| `loser_round` | `int(11)` | `:integer` | Bracket-advancement pointer (loser's bracket). |

### 3.13 `globalcombat.tourneyplayer` (2 columns) — live

| Column | MySQL type | Decision | Notes |
|---|---|---|---|
| `tourney_id` | `mediumint(8)`, part of composite PK | `:integer`, FK to `tourney.id` | |
| `account_id` | `mediumint(8)`, part of composite PK | `:integer`, FK to `account.id` | |

---

## 4. Column-count reconciliation

```
$ grep -c '^  `' "globalcombat MySql Schema.sql"
119
$ grep -c '^  `' "gc_games MySql Schema.sql"
7
```

119 + 7 = **126**, matching this document's per-table rows: 23 (account) + 5 (account_login) + 3 (cheat) +
9 (area) + 23 (game) + 7 (ledger) + 7 (message) + 15 (player) + 18 (tourney) + 7 (tourneygame) +
2 (tourneyplayer) = 119, plus 4 (gc_games.game) + 3 (gc_games.player) = 7. Total 126.
