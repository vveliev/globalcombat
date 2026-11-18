# Deploying to Oracle Cloud Always Free

Runs the production stack from `docker-compose.prod.yml` (the Phoenix/LiveView app, the .NET
gRPC engine host and MySQL) on one free Ampere A1 VM, with Caddy in front for HTTPS. It's a
concrete host for the "where it runs" question in `docs/launch.md` §2.1.

```
internet ──443──> Caddy ──gc-proxy──> web (Phoenix :4000) ──gc-internal──> grpc-host (:5251)
                                                          └─gc-internal──> mysql (:3306)
```

Only Caddy publishes ports. MySQL, gRPC (plaintext h2c) and Phoenix are reachable only on
the private Docker networks.

## What the free tier gives you

| Resource | Free limit | Used here |
| --- | --- | --- |
| Ampere A1 compute | 4 OCPU, 24 GB RAM total | 1 VM: 2–4 OCPU, 12–24 GB |
| Block storage | 200 GB total | 50–100 GB boot volume |
| Object Storage | 20 GB | nightly MySQL dumps (optional) |
| Outbound data | 10 TB/month | plenty |

All images (Elixir/OTP on Debian, .NET 10, MySQL 8.0, Caddy) publish arm64 builds, and the
images are built on the VM itself, so nothing needs cross-compiling.

## Before you start

- **Choose the home region carefully.** You can't change it later, and A1 capacity is often
  exhausted in popular regions ("Out of host capacity"). Retry later or try another
  availability domain.
- **Upgrade the account to Pay-As-You-Go.** Oracle reclaims *idle* Always Free VMs on
  free-only accounts. PAYG stops that and still bills $0 within the free limits. Then set a
  budget with a $1 alert (Billing → Budgets) so any accidental paid resource is caught at once.
- **A domain name.** Point an `A` record at the VM's public IP before step 6, since Let's
  Encrypt has to reach it.

## 1. Network (VCN)

Create a VCN with the "VCN with Internet Connectivity" wizard. Then, in a **Network Security
Group** attached to the VM:

| Direction | Source | Port | Why |
| --- | --- | --- | --- |
| Ingress | 0.0.0.0/0 | TCP 80 | ACME challenge + redirect to HTTPS |
| Ingress | 0.0.0.0/0 | TCP 443 | the site |
| Ingress | 0.0.0.0/0 | UDP 443 | HTTP/3 (optional) |

Remove the default **SSH 0.0.0.0/0** rule from the subnet's security list. Get admin access
through one of the options in step 3 instead.

## 2. Create the VM

- Image: **Canonical Ubuntu 24.04** (aarch64). Shape: **VM.Standard.A1.Flex**, 4 OCPU / 24 GB
  (or 2 / 12 if you want headroom for another free VM).
- Boot volume: 100 GB.
- Add your SSH public key.
- Advanced options → Management → paste [`cloud-init.yaml`](cloud-init.yaml).
- Attach the NSG from step 1. Reserve the public IP (Networking → Reserved public IPs) so it
  survives a stop/start.

## 3. Admin access without an open SSH port

Pick one:

- **OCI Bastion** (free): enable the Bastion plugin in the instance's Oracle Cloud Agent tab,
  create a Bastion in the VCN, then open a *Managed SSH session*. The session allows only your
  IP and expires after a few hours.
- **Tailscale**: `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --ssh`,
  then SSH over the tailnet.

Cloud-init has already disabled password and root login, and fail2ban is running.

## 4. Wait for cloud-init

```bash
sudo cloud-init status --wait
```

You should now have Docker, the repo at `/opt/globalcombat`, the `gc-proxy` network and the
backup timer.

## 5. Secrets (`.env`)

```bash
cd /opt/globalcombat
cp .env.production.example .env
cat deploy/oci/env.oci.example >> .env
chmod 600 .env
```

Fill in:

- `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`: generate each with `openssl rand -base64 32 | tr -d '/+='`.
- `DATABASE_URL`: `ecto://MYSQL_USER:MYSQL_PASSWORD@mysql/global_combat_prod`.
- `SECRET_KEY_BASE`: `openssl rand -base64 64 | tr -d '\n'`.
- `PHX_HOST`: your domain. `ACME_EMAIL`: your contact address. `PROXY_NETWORK=gc-proxy`.

Keep a copy in a password manager. Losing `SECRET_KEY_BASE` logs everyone out, and losing
the MySQL passwords locks you out of your own backups.

## 6. First deploy

```bash
cd /opt/globalcombat
alias gc='docker compose -f docker-compose.prod.yml -f deploy/oci/docker-compose.oci.yml'
gc build
gc run --rm migrate
gc up -d
gc logs -f caddy web
```

Caddy logs `certificate obtained successfully` once DNS resolves, and then
`https://$PHX_HOST` serves the game. The first build takes about 10 minutes on 4 OCPU.

## Updating

```bash
cd /opt/globalcombat
git pull --ff-only
gc build
gc run --rm migrate
gc up -d
```

## Backups

`globalcombat-backup.timer` runs [`backup.sh`](backup.sh) nightly. It writes gzipped dumps to
`/var/backups/globalcombat` and keeps 14 days. To store copies off the VM as well:

1. Create a private bucket, for example `globalcombat-backups`, and enable versioning and a
   retention rule.
2. Create a dynamic group that matches the instance, plus this policy:
   `Allow dynamic-group gc-vm to manage objects in compartment <name> where target.bucket.name='globalcombat-backups'`
3. Install the OCI CLI on the VM (`sudo apt-get install -y python3-pip && pip install oci-cli`,
   or Oracle's installer). Then set `OCI_BACKUP_BUCKET=globalcombat-backups` in `.env`.

Run a backup by hand with `sudo systemctl start globalcombat-backup` and check the result
with `journalctl -u globalcombat-backup`. The restore command is in the header of
`backup.sh`. Test a restore once before launch.

## Security checklist

- [ ] Only 80/443 open in the NSG, and no public SSH rule.
- [ ] Account on PAYG with a $1 budget alert. MFA on the OCI console login.
- [ ] `.env` is mode 600 and stored in a password manager. Nothing in git.
- [ ] Unattended upgrades are on (cloud-init). Reboots happen automatically at 04:30 UTC when needed.
- [ ] MySQL is never published: `gc ps` shows ports only on `caddy`.
- [ ] A restore from backup has been tested.
- [ ] Images are rebuilt monthly (`gc build --pull`) to pick up base-image security fixes.
