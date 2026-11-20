# ADR-0004: Host on an Oracle Cloud Always Free VM, deployed with Kamal

- Status: Accepted
- Date: 2026-11-19
- Supersedes: `docs/launch.md` §2.1 "deploy to the self-hosted fleet"

## Context

The launch plan assumed a slot on the self-hosted fleet. That host was never provisioned, and
the app now needs only two processes: the Phoenix release and Postgres. The .NET gRPC host is
only the reference oracle for `mix game_engine.diff_harness` in dev and CI, since turns resolve
in the Elixir engine.

Oracle Cloud's Always Free tier includes an Ampere A1 VM (4 OCPU, 24 GB RAM, 200 GB storage)
at no cost, which is more than this app needs.

## Decision

- **Host:** one Ampere A1 VM running Ubuntu 24.04, with the account on Pay-As-You-Go and a $1
  budget alert. Pay-As-You-Go stops Oracle reclaiming the VM when it's idle.
- **Deploys:** Kamal 2 (`config/deploy.yml`). kamal-proxy terminates TLS with Let's Encrypt and
  switches traffic only after `/up` passes, so deploys have no downtime and `kamal rollback`
  works. Images are built natively on the VM and stored in a private GHCR package.
- **Database:** Postgres 18 as a Kamal accessory on the same VM, never published. Nightly
  `pg_dump` with off-VM copies in Object Storage.
- **Access:** only 80 and 443 are public. Admin and Kamal SSH go over Tailscale. The first login
  goes through OCI Bastion.

Setup steps: `docs/deploy/oracle-kamal.md`.

## Alternatives considered

- **Fleet host with `docker-compose.prod.yml`:** blocked on provisioning that hasn't happened.
  The compose file stays, so the same release image can still run anywhere Docker does, but
  it's no longer the launch path.
- **Compose and Caddy on the Oracle VM:** simpler, with no registry and no deploy tool, but each
  deploy has a few seconds of downtime and there's no built-in rollback.
- **Managed PaaS (Fly, Render, Gigalixir):** less to operate, but not free for an always-on app
  plus Postgres.

## Consequences

- Deploys need the `.kamal/secrets` variables in the deployer's shell. Kamal copies the app
  secrets to the VM (`~/.kamal/apps/globalcombat/env`, mode 600), and the VM's Docker login
  stores the GHCR token.
- One VM is a single point of failure. Off-VM backups are what make it recoverable.
- The free shape is Arm, so every image has to build for arm64. The current images all do.
