#!/usr/bin/env bash
# Nightly MySQL dump for the OCI deployment (run by globalcombat-backup.timer,
# see cloud-init.yaml). Keeps the last KEEP_DAYS dumps on the VM and, when
# OCI_BACKUP_BUCKET is set in .env, also copies each dump to Object Storage
# using the instance's own identity (instance principal) — no API key on disk.
#
# Restore (stops nothing; import into the running mysql container):
#   gunzip -c /var/backups/globalcombat/<file>.sql.gz | \
#     docker compose -f docker-compose.prod.yml -f deploy/oci/docker-compose.oci.yml \
#       exec -T mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/globalcombat}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/globalcombat}"
KEEP_DAYS="${KEEP_DAYS:-14}"

cd "$REPO_DIR"

# Read only the one optional key we need from .env; compose reads the rest.
OCI_BACKUP_BUCKET="$(grep -E '^OCI_BACKUP_BUCKET=' .env | cut -d= -f2- || true)"

compose() {
  docker compose -f docker-compose.prod.yml -f deploy/oci/docker-compose.oci.yml "$@"
}

install -d -m 0700 "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/global_combat-$stamp.sql.gz"

# Credentials are expanded inside the container from its own environment, so
# they never appear in this host's process list.
compose exec -T mysql sh -c \
  'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers --databases "$MYSQL_DATABASE"' \
  | gzip -9 > "$out.partial"
mv "$out.partial" "$out"
chmod 0600 "$out"

find "$BACKUP_DIR" -name 'global_combat-*.sql.gz' -mtime +"$KEEP_DAYS" -delete

if [[ -n "$OCI_BACKUP_BUCKET" ]]; then
  if command -v oci >/dev/null 2>&1; then
    oci os object put --auth instance_principal \
      --bucket-name "$OCI_BACKUP_BUCKET" \
      --file "$out" --name "mysql/$(basename "$out")" --no-overwrite
  else
    echo "OCI_BACKUP_BUCKET is set but the oci CLI is not installed; kept local copy only" >&2
    exit 1
  fi
fi

echo "backup ok: $out"
