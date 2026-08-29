# ADR-0002: Account password storage and the migration path off it

- Status: Accepted (rehash-on-login strategy) / Proposed (admin forced-reset carve-out — needs Dev sign-off)
- Date: 2026-08-29
- Issue: GIF-29

## Context

The issue asked to establish how `account.password` is actually stored before choosing a
migration strategy, on the assumption a 25-year-old table would not hold bcrypt. It doesn't —
but it's worse than "an old hash": the column currently holds a **mix of plaintext and a
truncated legacy hash**, and the live (pre-port) code path only ever writes plaintext.

### The column itself

`account.password` is `varchar(30)` (`globalcombat MySql Schema.sql:7`). That's a hard ceiling:
bcrypt output is 60 characters, Argon2 is longer still, and even the app's own legacy hash
(below) produces an 88-character Base64 string that cannot fit. Nothing modern was ever stored
here as-is.

### Four code paths, three different behaviors

1. **Login check** (`Web/Controllers/AccountController.cs:196`):
   ```csharp
   if (password != accountRow["password"] && LT.UserPage<int>.CalculateHash(password) != accountRow["password"])
       return "Bad Password";
   ```
   Accepts a match against either the raw input **or** a hash. `CalculateHash`
   (`Web/Lib/UserPage.cs:11`) is `Base64(SHA512("s&~D$L{a8_" + input))` — a single fast round,
   one hardcoded pepper shared by every account, no per-user salt. Its 88-char output cannot
   fit in `varchar(30)`, so any row that legitimately holds a hash must have been silently
   truncated to 30 characters at insert time (consistent with a pre-strict-mode MySQL default;
   there's no dump to confirm this — see GIF-26). Truncation degrades whatever the hash was
   protecting further, though it isn't reversible on its own.

2. **Registration** (`Web/Controllers/BaseController.cs:178-187`, `CreateAccount`): inserts
   `password` **literally**, with no call to `CalculateHash` at all.

3. **Change password** (`Web/Controllers/AccountController.cs:102`, `ModifyPassword`, reached
   from Settings): overwrites the column with the new password **literally**.

4. **Forgot password** (`Web/Controllers/AccountController.cs:141`, `ResetPassword`, reached
   from LostPassword): generates an 8-character lowercase+digit password
   (`UserPage<int>.GeneratePassword`, ~41 bits of entropy, no uppercase or symbols), stores it
   **literally**, and emails it to the user in cleartext.

Only path 1 ever reads a hash; paths 2-4 — registration, change, and reset, i.e. every way a
password can enter the system today — write plaintext. So `account.password` is not "an old
hash we should upgrade," it's a column where an unknown but likely large fraction of active
rows (anyone who registered, changed, or reset since whatever earlier version of the code used
to call `CalculateHash` on write) already holds the plaintext password today, in production,
independent of any port decision. **That's worth flagging to Dev/security on its own — it's a
live exposure, not something this port introduces or can wait to fix.**

There's no production dump (per GIF-26) to size the plaintext-vs-hashed split.

### Minimum requirements enforced

5 characters, no complexity rules, in both registration and change-password. Carry this forward
as the floor unless Dev wants to raise it — raising it doesn't require touching stored rows.

## Decision

**No forced reset for the general player base.** Verify against whichever of the two legacy
shapes matches, then transparently rehash to a modern algorithm (Phoenix's own default —
`Bcrypt` or `Argon2` via `phx.gen.auth`) on that successful login:

```
stored = account.password  (varchar(30))
match =
  if stored == input                      -> plaintext row, matched
  elif stored == truncate30(CalculateHash(input)) -> legacy hashed row, matched
  else                                     -> reject
on match: rewrite `password` with Bcrypt.hash_pwd_salt(input), drop the old column's format entirely
```

Both branches funnel into the same rehash-on-success step — a plaintext match isn't treated any
differently from a legacy-hash match once verified. This keeps every existing user able to log
in with their current password on day one, same as the issue requires, and the column
self-heals to a real hash as accounts are used, with no bulk migration job needed. Ecto/Ecto's
Bcrypt.Elixir output is much longer than 30 characters, so this requires the `password` column
itself to widen (`text`, effectively) in the same migration that GIF-26 writes for `account` —
noting that here since GIF-26's schema-map is where it needs to land, not deciding it here.

**Open for Dev, not decided here:** whether to force a reset specifically for `admin` /
`SuperAdmin` status accounts (elevated blast radius if a plaintext row leaks) rather than
waiting for their next login. That's the "forced reset" the issue said was Dev's call — this
ADR does not extend that to the general player base, only surfaces the narrower admin-only
version as an option.

**Reset flow changes on the port regardless of the above:** stop emailing the new password in
cleartext. `phx.gen.auth`'s token-based reset-link flow replaces `ResetPassword`/`LostPassword`
outright — this isn't gated on the plaintext question, it's just a strict improvement available
either way.

## Adjacent findings (context for GIF-26 / GIF-33, not decided here)

- **`account_login`** is written on every successful login (`AccountController.SetSession`,
  `Web/Controllers/AccountController.cs:222`, `insert ignore` keyed on `(account_id, datetime)`)
  and read two ways: `HomeController.PlayerInfo` (per-account history, opt-in via
  `ShowLoginHistory`) and `HomeController.IpAddresses` (reverse lookup: given an IP, list every
  account that logged in from it — this is the multi-accounting/abuse-detection surface the
  issue asked about). Both need to survive the port for existing moderation to keep working.
- **`cheat`** (`account_id`, `game_id`, `datetime`) is defined in the DDL but has **zero
  references anywhere in the current `Web/` or `GlobalCombat.Core` source** — no controller,
  view, or model reads or writes it. It's either written by tooling outside this repo or dead.
  Don't drop it silently: even unused going forward, existing rows may be moderation history
  worth preserving. Flag for Dev confirmation before deciding its fate in the schema map.

## Status of the rest of GIF-29

This ADR is the part of GIF-29 that doesn't depend on anything else — it's read from the
existing C# source and DDL, not from a running Ecto schema or a landed Phoenix app. The
remaining "Done when" bar (register/log on/log off/reset working against a seeded database,
covered by tests) is blocked:

- on **GIF-26** (Map both MySQL schemas to Ecto, `todo`) for the actual `account`/`account_login`
  Ecto schemas — including the `password` column widening this ADR calls for, and the
  enum/timestamp decisions that table needs regardless of auth;
- on **GIF-27** (Scaffold the Phoenix LiveView app in the fork, `blocked`) for a landed app with
  CI to write the auth context and LiveViews against — currently blocked on repo push access,
  which traces to **GIF-47** (Agents cannot push to `vveliev/globalcombat`, 403).

No login/register/session code is written against the Phoenix app in this pass; that would be
built on schema and scaffolding that don't exist on `main` yet.
