# Launch plan: Global Combat relaunch

- Status: Proposed
- Date: 2026-08-30 (updated 2026-11-19)

This is a fresh deployment of the Phoenix port, not a migration: no `.NET` site is running, and
there's no production database or in-flight game to preserve.

**What ships:** the Phoenix/LiveView app (`liveview/`) and one Postgres 18 database
(`docs/schema-map.md`). Turns resolve in the Elixir engine (`GlobalCombat.Engine`), so
production runs no `.NET` process. `GlobalCombat.GrpcHost` stays in the repo only as the
reference oracle for `mix game_engine.diff_harness`.

## 1. Domain

`globalcombat.com` is parked by the upstream author and isn't ours.

- **Launch domain:** start on a domain vveliev controls, or a zero-cost interim one.
- **`globalcombat.com`:** ask the upstream owner about transferring or repointing it, in
  parallel. This isn't on the critical path. If it works out later, it's a DNS change only,
  since the host comes from `PHX_HOST`.

## 2. Hosting

One Oracle Cloud Always Free VM, deployed with Kamal: [ADR-0004](adr/0004-hosting-oracle-kamal.md).
Setup steps are in [deploy/oracle-kamal.md](deploy/oracle-kamal.md).

The release image is `liveview/Dockerfile.prod`, with `bin/server` and `bin/migrate`.
`docker-compose.prod.yml` runs the same image without Kamal.

## 3. Config and secrets

`liveview/config/runtime.exs` reads all production config from environment variables and
refuses to boot without `DATABASE_URL` or `SECRET_KEY_BASE`. Kamal injects them from
`.kamal/secrets`, which only references the deployer's environment or password manager.

| Variable | Notes |
| --- | --- |
| `DATABASE_URL` | Must match the Postgres accessory's user and password |
| `SECRET_KEY_BASE` | Generate once; rotating it logs everyone out |
| `PHX_HOST` | The live domain |
| `MAILGUN_API_KEY` | Optional. Without it, the app boots with emails going to the log only. |

## 4. Database

- **Instance:** Postgres 18 on the same VM as a Kamal accessory, with a persistent volume. Its
  port is never published.
- **Credentials:** a dedicated user and password, not dev's `postgres`/`postgres`. The first
  migration runs `CREATE EXTENSION citext`; the image's `POSTGRES_USER` is allowed to.
- **Migrations:** run automatically by `bin/migrate` before each new container serves traffic.
  Seeds are dev-only.
- **Backups:** nightly `pg_dump`, plus off-VM copies in Object Storage. Both must be in place
  before launch.

## 5. Rollback

- **Bad release:** `kamal rollback <version>` switches back to the previous image without
  downtime.
- **Pull the launch entirely:** `kamal app stop`, then point DNS away from the VM. Keep the
  database volume so a second attempt resumes where it left off. Drop it only if the problem
  was bad data.
- **Automatic triggers:** anything that risks player data or account security, such as a bug in
  the ADR-0002 rehash-on-login path or a turn-resolution bug. Anything else is a judgment call.
- **Window:** 14 days of active monitoring after launch, with someone able to roll back within
  the hour.

**Owner:** vveliev, the only person with DNS and cloud-account access.

## Open items

| Item | Owner | State |
| --- | --- | --- |
| Launch domain | vveliev | Not chosen |
| Oracle account, VM and network (ADR-0004) | vveliev | Not provisioned |
| Secrets in a password manager | vveliev | Not provisioned |
| Off-VM backups and a tested restore | vveliev | Not set up |
| Mail provider account | vveliev | Mailgun is wired in code; no account or key yet. Blocks password-reset emails only. |
| Turn scheduler resolver | Engineering | `TurnScheduler` finds due games but has no resolver wired, so turns don't auto-advance yet. Needed soon after launch, not for launch. |
| Login rate limiting | Engineering | None yet; worth adding before the site is public. |
