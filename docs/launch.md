# Launch plan: globalcombat.com relaunch

- Status: Proposed
- Date: 2026-08-30
- Issue: GIF-34

This is a launch plan, not a cutover plan. There is no running `.NET` site, no production
database, and no in-flight games to preserve — see the evidence in GIF-34's description and the
two independent re-checks in its comment thread (matching `302` redirect to
`Bryan-Legend/globalcombat`, connection timeout on HTTPS, and a Namecheap-parking IP). Every
decision below is written against that reality: this is a fresh deployment of the Phoenix port,
not a migration off something live.

The app being launched: a Phoenix/LiveView web app (`liveview/`) plus a companion **`.NET` gRPC
engine host** (`GlobalCombat.GrpcHost`) that Phoenix calls for turn resolution — this two-process
shape was decided in `docs/adr/0001-game-state-transport-to-elixir.md` (ADR-0001, GIF-25) and is
not renegotiated here. A single MySQL database backs both (`docs/schema-map.md`, GIF-26): 13
tables, 126 columns, one already-scaffolded `Ecto.Repo`. As of this doc, GIF-33/28/30/32/29/31
(surfaces, engine, board, tournaments, accounts, legacy routes) are all `done` on `main`
(`c048b8c`), so there is a functionally complete app to plan hosting against. `GIF-68` (a
realtime turn scheduler) is still `backlog` — it is a gameplay-timing feature, not a deployment
blocker, and is called out in Gaps below rather than treated as launch-blocking.

## 1. Domain

**Already answered in GIF-34's description — cited here, not re-litigated:** `globalcombat.com`
is Namecheap-parked and 302s to the upstream author's GitHub repo. We do not control it. The
README on `main` (written by the original author, Bryan Legend) confirms this is intentional on
their end: the site was taken offline in 2026 and the repo open-sourced, with a note directing
hosting interest to an issue on the upstream repo, not to this fork.

**Decision: do not block launch on reacquiring `globalcombat.com`.** Two tracks, run in
parallel, owned by **vveliev** (repo/company owner — this is an external-account and possibly a
purchase action, outside any agent's authority):

1. **Primary:** vveliev contacts the upstream owner (via the GitHub issue the README already
   points to, or WHOIS/registrar contact for the domain) to ask about transferring or repointing
   `globalcombat.com` to this fork's deployment. No response-time commitment exists from a third
   party, so this cannot be the launch's critical path.
2. **Launch domain:** vveliev registers an alternate domain (e.g. a `.com`/`.gg` variant such as
   `playglobalcombat.com`, exact name is vveliev's call) or, if a zero-cost interim is preferred,
   launches on the hosting provider's default subdomain first. Either way, DNS for whichever
   domain is used points at the host chosen in §2, and TLS is issued for that name (Let's
   Encrypt/ACME via the reverse proxy — see §2).

If track 1 succeeds later, it becomes a DNS repoint, not a redeploy — nothing in §2–§4 depends on
which domain answers, since `PHX_HOST` is already an environment variable
(`liveview/config/runtime.exs:70`).

## 2. Hosting, releases, and config/secrets

### 2.1 Where it runs

**Decision: deploy to vveliev's existing self-hosted fleet, not a cloud PaaS.** Evidence for
this, not a preference: the dev stack (`docker-compose.yml`) already reserves a port block
(`11400`) against a fleet-wide port registry (`vveliev/skynet`, `registry/PORTS.md`) and picks
its Docker subnet specifically to avoid colliding with other projects on that same fleet. That
registry and the fleet it describes live in `vveliev/home-lab`, a repo this company's agents
cannot reach (see GIF-57's cross-company note) — so the actual host machine, reverse proxy, and
TLS termination are **vveliev's action item**, not something this doc or an agent can provision
directly.

**Owner: vveliev.** Action: allocate a production host (or VM/container slot) on the fleet,
reserve a production port block in `registry/PORTS.md` (do not reuse dev's `11400` — that
convention exists precisely so prod and a concurrently-running dev stack don't collide), and
front it with whatever reverse proxy the fleet already standardizes on for TLS (the fleet
predates this project; this doc does not invent a new one).

### 2.2 Releases — this is a real gap, not a paperwork step

Neither Dockerfile in the repo today is a production build:

- `liveview/Dockerfile` is explicitly commented as "Dev-mode image for the gRPC spike client
  only ... Not the production release Dockerfile," runs `MIX_ENV=dev`, and its `CMD` runs a
  one-off mix task, not the Phoenix server.
- `GlobalCombat.GrpcHost/Dockerfile` runs `dotnet run` from the full SDK image with no
  publish/multi-stage step — fine for the GIF-38 spike, not a release artifact.
- `mix.exs` has no `releases:` config and `phx.gen.release` has not been run (no `rel/`, no
  `bin/server`), and `liveview-ci.yml` builds and tests but publishes nothing.

**Decision:** before this plan can produce a running site, someone builds:

1. A production `liveview` image: `mix phx.gen.release`, multi-stage Dockerfile (build stage
   compiles + `mix assets.deploy` + `mix release`; runtime stage copies the release onto a slim
   Erlang runtime image, `MIX_ENV=prod`, `PHX_SERVER=true`).
2. A production `GlobalCombat.GrpcHost` image: multi-stage `dotnet publish` (SDK image to build,
   `mcr.microsoft.com/dotnet/aspnet:10.0` or similar to run), replacing `dotnet run`.
3. TLS between Phoenix and the gRPC host: the current `grpc-host` service is deliberately
   plaintext h2c inside the compose network, called out in `docker-compose.yml` itself as "fine
   for a spike, not a production posture." Same-host deployment (§2.1 keeps both containers on
   one fleet node behind one reverse proxy) makes this an acceptable initial posture — the gRPC
   hop never leaves a private Docker network — but it should not be assumed to stay acceptable if
   the two services are ever split across hosts.

**Owner: whoever picks up the child issue this doc creates** (see Gaps/Follow-ups). This is
scoped as new work, not folded silently into "launch."

### 2.3 Config and secrets — what replaces `Secrets.json`/`appsettings.json`

The Elixir side already reads its production config from environment variables, not a file —
`liveview/config/runtime.exs` raises at boot if `DATABASE_URL` or `SECRET_KEY_BASE` are unset,
and `GRPC_HOST`/`GRPC_PORT` are read the same way in `lib/global_combat/game_engine/client.ex`.
No new config-loading mechanism needs to be built; what's missing is *where the values come from*
and *how they reach the container*.

**Decision:** environment variables, sourced from 1Password, injected via the fleet's compose
stack (a production `docker-compose.yml`/`.env`, not committed with real values — same shape as
the dev file, different content). This is not a new pattern for this org: GIF-57 already
established 1Password as the source of truth for secrets, reconciling out-of-band Paperclip
secrets against it. The values needed:

| Variable | Consumed by | Source |
|---|---|---|
| `DATABASE_URL` | Phoenix (`runtime.exs`) | 1Password, generated at DB provisioning (§3) |
| `SECRET_KEY_BASE` | Phoenix (`runtime.exs`) | 1Password, generated once via `mix phx.gen.secret` |
| `PHX_HOST` | Phoenix (`runtime.exs`) | Whichever domain is live per §1 — not a secret, but must track DNS |
| `GRPC_HOST` / `GRPC_PORT` | Phoenix → GrpcHost (`client.ex`) | Fleet-internal service name/port, not a secret |
| `MAILGUN_API_KEY` / mailer config | Phoenix (account notifications — `accounts/notifier.ex`) | 1Password; **mailer adapter itself is still unconfigured** — `runtime.exs` only has a commented example. Needs a decision on which transactional-email provider before password-reset emails work in prod. |

**Owner: vveliev** for provisioning the 1Password items and wiring them into the fleet's
deployment mechanism (however it injects env vars today — outside this company's visibility per
the GIF-57 boundary). The mailer-provider decision is a small open sub-question; flagged in Gaps.

## 3. Database provisioning

Per GIF-34's scope: this is a **fresh database**, not a migration. No dump exists, there's no
data to import, and `docs/schema-map.md` (GIF-26) is the authoritative shape — 13 tables, one
MySQL 8/MariaDB-compatible `Ecto.Repo`, already merged as Ecto migrations on `main`
(`liveview/priv/repo/migrations/`).

**Decision: a single small MySQL instance on the same fleet host as the app** (not a managed
cloud DB service) — consistent with §2.1's fleet-hosting decision and proportionate to scale: 13
tables, no historical data, a project restarting from zero players. Sizing:

- Start at the smallest instance size the fleet's Docker host comfortably runs alongside the two
  app containers (this is a resource-allocation call for whoever provisions the host, not a fixed
  number here — the schema is tiny; there's nothing to benchmark yet against zero traffic).
- Persistent volume for `/var/lib/mysql`, same pattern as `docker-compose.yml`'s `mysql-data`
  volume, but with a real backup job — the dev compose file has none, deliberately, because dev
  data is disposable and prod data (new players' accounts, from day one) is not.
- `mysql_native_password` auth plugin, matching dev, only because MyXQL requires it — this is a
  driver constraint, not a security posture; it does not need a passwordless root user in prod
  (dev's `MYSQL_ALLOW_EMPTY_PASSWORD` does not carry over).

**Owner: vveliev** — provisioning a fleet host resource is the same cross-company boundary as
§2.1. **Migrations owner:** whoever runs the release ships `mix ecto.migrate` as a release step
or a one-shot job before the app's first boot; this is the same mechanism `mix.exs`'s
`ecto.setup` alias already uses in dev (`ecto.create`, `ecto.migrate`), minus `run
priv/repo/seeds.exs` — seeds are dev-only fixtures, not something a real launch runs.

**Backup/rotation ownership:** vveliev, as part of the same fleet-provisioning action — this is a
day-2 operational concern, not new to this launch, and this doc does not invent a new backup
tool; it uses whatever the fleet already runs for its other MySQL-backed projects, if anything
exists, or flags that as a gap (see Gaps) if it doesn't.

## 4. Rollback

There is nothing currently serving players, so — as GIF-34's description frames it — "rollback"
cannot mean failing back to a previous system. It means **pulling the new deployment back down**
cleanly, with no player-facing system left half-up.

**Decision:**

- **Mechanism:** stop the production compose stack (or fleet-equivalent) for both `web` and
  `grpc-host`, and repoint DNS for whichever domain is live (§1) away from the host — back to
  "nothing here" (a static holding page, or simply letting the domain go unresolved) rather than
  silently serving a half-configured app.
- **Data:** since this is a brand-new database with no prior state to protect, a rollback does
  not need a data-preservation plan — the DB can be stopped in place (not dropped) so a second
  launch attempt resumes from wherever it left off, or dropped and re-migrated from scratch if the
  rollback reason was data-correctness related. Which of those two applies is a judgment call at
  rollback time, not a decision this doc can make in advance.
- **Trigger conditions:** anything that would put player data or account security at risk (e.g. a
  bug in the ADR-0002 rehash-on-login path, or a gRPC-boundary correctness bug like the one
  GIF-38's evidence describes for `AsReference` reference-equality) is an automatic rollback,
  not a judgment call. Anything else (UI bugs, missing features, performance issues under real
  load) is a judgment call for whoever is on point at launch — named below.
- **Rollback window:** **14 days post-launch** of elevated readiness (someone actively monitoring
  and able to execute the rollback mechanism above within the hour, not just on-call in the
  generic sense). After 14 days with no rollback-triggering issue, the launch is considered
  stable and reverts to normal operational monitoring. This window is a starting proposal, not
  evidenced by prior launches of this project (there are none) — vveliev can shorten or extend it.

**Owner: vveliev** (sole operator of the target fleet; also the only account with DNS control per
§1).

## Owners summary

| Decision | Owner | Action |
|---|---|---|
| Domain (contact upstream / register alternate) | vveliev | Track 1 open, no fixed deadline. Track 2 decided: launch on hosting provider's default subdomain first (zero-cost interim) — see Status below |
| Fleet host + port block + reverse proxy/TLS | vveliev | Not yet provisioned — vveliev will ping when ready to hand off details |
| Production release Dockerfiles + `phx.gen.release` | **Done** — GIF-110, PR #34 (merged to `main`) | Shipped `Dockerfile.prod` for both services, `bin/server`/`bin/migrate` overlays, `docker-compose.prod.yml` |
| 1Password secrets wired into fleet deploy mechanism | vveliev | Not yet provisioned |
| Mailer provider decision | Follow-up issue (new) | Blocks password-reset emails only, not launch |
| MySQL instance sizing + backup job | vveliev | Provision alongside app host |
| Migration execution (`mix ecto.migrate`) on deploy | Release-owner (same as Dockerfiles) | `bin/migrate` shipped in PR #34, ready to run once a host exists |
| Rollback execution during the 14-day window | vveliev | On call for the window |

## Status: GIF-110 execution (2026-08-31)

Per the decisions vveliev made on GIF-110's launch-decisions interaction:

- **Domain:** launch on the hosting provider's default subdomain first (zero-cost interim per §1
  track 2), not a fresh registration. Track 1 (contacting the upstream owner about
  `globalcombat.com`) remains open with no fixed timeline.
- **Fleet host:** not yet provisioned. vveliev will ping when ready to hand off the host/port/TLS
  details from §2.1.
- **Secrets:** not yet provisioned in 1Password.
- **Go-live:** vveliev will run the actual deploy from the release artifacts in PR #34, not an
  agent — the same cross-company fleet boundary as GIF-57 (`vveliev/home-lab` is unreachable from
  this company's agents).

This closes the in-repo portion of this plan (§2.2's Dockerfiles/release scaffolding). Everything
else in the Owners summary above is an out-of-band action on vveliev's fleet; there is nothing
further an agent can provision toward a live URL until the fleet host exists.

## Gaps and follow-ups this doc surfaces but does not close

- **No production release artifacts exist yet** (§2.2) — this is real work, not a config change.
  A child issue should be filed to build both production Dockerfiles and wire
  `mix phx.gen.release`.
- **Mailer adapter is unconfigured** (§2.3) — password-reset and notification email
  (`accounts/notifier.ex`) has no prod transport selected yet.
- **GIF-68 (realtime turn scheduler)** is still `backlog`. It affects gameplay timing, not
  deployability, so it does not block this plan, but it should land before or shortly after
  launch — turns not resolving on schedule is a player-facing correctness issue once real users
  are playing.
- **Fleet backup tooling for MySQL is unconfirmed** — this doc assumes vveliev's fleet has a
  answer for this already (from other projects) but that isn't verified here.
