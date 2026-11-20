#!/usr/bin/env bash
# Nightly Postgres dump for the OCI deployment (run by globalcombat-backup.timer,
# see cloud-init.yaml). Dumps the Kamal Postgres accessory, keeps the last
# KEEP_DAYS dumps on the VM and, when OCI_BACKUP_BUCKET is set in
# /etc/globalcombat/backup.env, also copies each dump to Object Storage using the
# instance's own identity (instance principal), so no API key is stored on disk.
#
# Dumps use pg_dump's custom format (-Fc: compressed, restorable per table).
# Restore into the running accessory (drops and recreates objects):
#   docker exec -i globalcombat-postgres sh -c \
#     'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
#     < /var/backups/globalcombat/<file>.dump
set -euo pipefail

PG_CONTAINER="${PG_CONTAINER:-globalcombat-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/globalcombat}"
KEEP_DAYS="${KEEP_DAYS:-14}"
CONFIG_FILE="${CONFIG_FILE:-/etc/globalcombat/backup.env}"

OCI_BACKUP_BUCKET=""
if [[ -f "$CONFIG_FILE" ]]; then
  OCI_BACKUP_BUCKET="$(grep -E '^OCI_BACKUP_BUCKET=' "$CONFIG_FILE" | cut -d= -f2- || true)"
fi

install -d -m 0700 "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/global_combat-$stamp.dump"

# Runs as POSTGRES_USER over the container's local socket (trusted by the
# official image), so no password is passed on any command line.
docker exec "$PG_CONTAINER" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$out.partial"
mv "$out.partial" "$out"
chmod 0600 "$out"

find "$BACKUP_DIR" -name 'global_combat-*.dump' -mtime +"$KEEP_DAYS" -delete

if [[ -n "$OCI_BACKUP_BUCKET" ]]; then
  if command -v oci >/dev/null 2>&1; then
    oci os object put --auth instance_principal \
      --bucket-name "$OCI_BACKUP_BUCKET" \
      --file "$out" --name "postgres/$(basename "$out")" --no-overwrite
  else
    echo "OCI_BACKUP_BUCKET is set but the oci CLI is not installed; kept local copy only" >&2
    exit 1
  fi
fi

echo "backup ok: $out"
