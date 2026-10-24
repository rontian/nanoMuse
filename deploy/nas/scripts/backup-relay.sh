#!/usr/bin/env bash
# Consistent online SQLite backup of NAS Relay + CLOUD_SECRET in private config.
# CAUTION: resulting tar.gz includes secrets; encrypt for offsite storage.
set -Eeuo pipefail
umask 077

compose_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_env="${NANOMUSE_DEPLOY_ENV_FILE:-/volume1/docker/nanoMuse/config/.env}"
[[ -f "$deploy_env" ]] || {
  echo "Missing private Compose env file: $deploy_env" >&2
  exit 1
}
# Owned by the operator; this file contains only trusted Compose variables.
set -a
# shellcheck disable=SC1090
source "$deploy_env"
set +a
: "${NANOMUSE_CONFIG_ROOT:?Missing NANOMUSE_CONFIG_ROOT}"
: "${NANOMUSE_DATA_ROOT:?Missing NANOMUSE_DATA_ROOT}"
backup_dir="${NANOMUSE_BACKUP_DIR:-/volume1/docker/nanoMuse/backups/relay}"
[[ -f "$NANOMUSE_CONFIG_ROOT/relay.env" ]] || {
  echo "Missing private Relay config: $NANOMUSE_CONFIG_ROOT/relay.env" >&2
  exit 1
}

mkdir -p "$backup_dir"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
cp -- "$NANOMUSE_CONFIG_ROOT/relay.env" "$stage/relay.env"

docker compose --env-file "$deploy_env" -f "$compose_dir/compose.yaml" exec -T relay python - > "$stage/cloud.db" <<'PY'
import os
import shutil
import sqlite3
import sys
import tempfile

path = "/srv/nanomuse-cloud/data/cloud.db"
if not os.path.isfile(path):
    raise SystemExit("Relay database not found")
with tempfile.TemporaryDirectory() as tmp:
    dest = os.path.join(tmp, "cloud.db")
    source = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        target = sqlite3.connect(dest)
        try:
            source.backup(target)
        finally:
            target.close()
    finally:
        source.close()
    with open(dest, "rb") as saved:
        shutil.copyfileobj(saved, sys.stdout.buffer)
PY

[[ -s "$stage/cloud.db" ]] || {
  echo "Empty database backup, refusing to archive" >&2
  exit 1
}
archive="$backup_dir/nanomuse-relay-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
tar -czf "$archive" -C "$stage" cloud.db relay.env
chmod 600 "$archive"
echo "Backup created: $archive"
echo "WARNING: contains CLOUD_SECRET and model credentials; encrypt before offsite backup."
