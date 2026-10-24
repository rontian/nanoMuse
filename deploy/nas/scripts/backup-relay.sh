#!/usr/bin/env bash
# Consistent SQLite backup + secrets. The archive is sensitive: encrypt offsite.
set -Eeuo pipefail
umask 077
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$here/.env" && -f "$here/relay.env" ]] || {
  echo 'Missing deploy/nas/.env or relay.env' >&2
  exit 1
}
backup_dir="${NANOMUSE_BACKUP_DIR:-$here/backups}"
mkdir -p "$backup_dir"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
cp -- "$here/relay.env" "$stage/relay.env"

docker compose --env-file "$here/.env" -f "$here/compose.yaml" exec -T relay python - > "$stage/cloud.db" <<'PY'
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
[[ -s "$stage/cloud.db" ]] || { echo 'Empty database backup' >&2; exit 1; }
archive="$backup_dir/nanomuse-relay-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
tar -czf "$archive" -C "$stage" cloud.db relay.env
chmod 600 "$archive"
echo "Created owner-only backup: $archive"
echo "WARNING: archive contains credentials; encrypt before offsite backup."
