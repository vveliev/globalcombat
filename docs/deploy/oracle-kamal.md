# Deploying to Oracle Cloud with Kamal

How to run the decision in [ADR-0004](../adr/0004-hosting-oracle-kamal.md).

```
internet ──443──> kamal-proxy (TLS) ──> web (Phoenix :4000) ──> globalcombat-postgres
you ──Tailscale SSH──> VM   (kamal deploy; image builds on the VM)
```

## You need

- An Oracle Cloud account upgraded to **Pay-As-You-Go**, with a $1 budget alert (Billing →
  Budgets) and MFA on the console login. Pick the home region carefully: it can't be changed,
  and A1 capacity is often short ("Out of host capacity").
- A domain you can point at the VM.
- On your machine: Docker, Kamal 2.12+ (`gem install kamal`), Tailscale, and a GitHub classic
  token with `write:packages`.

## 1. Network

Create a VCN with the "VCN with Internet Connectivity" wizard. Delete the subnet security
list's `SSH 0.0.0.0/0` rule, and attach a Network Security Group with:

| Source | Port | For |
| --- | --- | --- |
| 0.0.0.0/0 | TCP 80, 443 | the site and Let's Encrypt |
| the VCN CIDR, e.g. 10.0.0.0/16 | TCP 22 | OCI Bastion, first login only |

## 2. VM

- **Image and shape:** Ubuntu 24.04 (aarch64) on VM.Standard.A1.Flex, 4 OCPU / 24 GB, with a
  100 GB boot volume.
- **SSH key:** add your public key.
- **Cloud-init:** under Advanced options → Management, paste
  [`deploy/oci/cloud-init.yaml`](../../deploy/oci/cloud-init.yaml). It installs Docker,
  Tailscale, SSH hardening, fail2ban, unattended upgrades and the backup timer.
- **NSG:** attach the one from step 1.
- **Public IP:** reserve it under Networking → Reserved public IPs. Then point your domain's
  `A` record at it.

## 3. Tailscale (once)

Create an OCI Bastion in the VCN and open a **port-forwarding session** to the VM's private IP
on port 22. Connect through it with the SSH command the console shows, then run:

```bash
sudo cloud-init status --wait && sudo tailscale up
```

From then on, use the VM's Tailscale name, for example `ssh ubuntu@gc-vm`. Use plain
`tailscale up`, not `--ssh`: Tailscale SSH can ask for browser re-approval, which Kamal can't
answer. You can delete the Bastion and the port 22 NSG rule afterwards.

## 4. Secrets

[`.kamal/secrets`](../../.kamal/secrets) only references environment variables, so values
never go into git. Export these before running Kamal, or swap the lines for
`kamal secrets fetch` from your password manager:

| Variable | Value |
| --- | --- |
| `KAMAL_HOST` | the VM's Tailscale name, e.g. `gc-vm` |
| `PHX_HOST` | your domain |
| `KAMAL_REGISTRY_PASSWORD` | the GitHub token |
| `POSTGRES_USER` | e.g. `globalcombat` |
| `POSTGRES_PASSWORD` | `openssl rand -base64 32 \| tr -d '/+='` |
| `DATABASE_URL` | `ecto://USER:PASSWORD@globalcombat-postgres/global_combat_prod` |
| `SECRET_KEY_BASE` | `openssl rand -base64 64 \| tr -d '\n'` |
| `MAILGUN_API_KEY` | optional; without it, emails only go to the log |

Kamal copies the app secrets to the VM (`~/.kamal/apps/globalcombat/env`, mode 600), and the
VM's Docker login stores the GitHub token. Keep the originals in a password manager: losing
`SECRET_KEY_BASE` logs everyone out, and losing the Postgres password locks you out of backups.

## 5. Deploy

From a clean checkout of `main`, since Kamal builds `liveview/` as it is on disk:

```bash
kamal setup
```

The first time, this starts kamal-proxy and Postgres. Then it builds the image on the VM,
pushes it to GHCR, runs migrations in the new container and switches traffic once `/up`
passes. After that, use:

| Task | Command |
| --- | --- |
| Deploy | `kamal deploy` |
| Roll back | `kamal app containers`, then `kamal rollback <version>` |
| Logs | `kamal app logs -f` |
| Remote IEx | `kamal app exec -i --reuse "/app/bin/global_combat remote"` |

Migrations run before each new container starts serving, while the old one is still live. Keep
them backward-compatible with the running version.

## 6. Backups

[`backup.sh`](../../deploy/oci/backup.sh) runs nightly at 03:15 UTC and keeps 14 days of
`pg_dump` files in `/var/backups/globalcombat`. Those are on the same disk as the database, so
set up off-VM copies before launch:

1. Create a private bucket, `globalcombat-backups`, with versioning on.
2. Create a dynamic group matching the VM and this policy:
   `Allow dynamic-group gc-vm to manage objects in compartment <name> where target.bucket.name='globalcombat-backups'`
3. Install the OCI CLI on the VM with Oracle's installer, then add
   `OCI_BACKUP_BUCKET=globalcombat-backups` to `/etc/globalcombat/backup.env`.

Check it with `sudo systemctl start globalcombat-backup`, then
`journalctl -u globalcombat-backup`. The restore command is at the top of `backup.sh`, and it's
worth running once before launch. The VM's copy of the script is in `/opt/globalcombat`;
`sudo git -C /opt/globalcombat pull` picks up changes.

## Before launch

- [ ] NSG allows only 80 and 443 publicly.
- [ ] `docker ps` on the VM shows published ports only on `kamal-proxy`.
- [ ] The GHCR package is private.
- [ ] An off-VM backup exists, and a restore has been tested.
- [ ] The budget alert and console MFA are on.
