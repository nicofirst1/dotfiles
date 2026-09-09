#!/usr/bin/env bash
set -euo pipefail
STAGING="${MOSQUITTO_BACKUP_STAGING:-/srv/backups/staging/mosquitto}"
mkdir -p "$STAGING"
chmod 700 /srv/backups /srv/backups/staging "$STAGING" 2>/dev/null || true
if ! docker inspect -f '{{.State.Running}}' mosquitto 2>/dev/null | grep -q true; then
  echo "homelab-mosquitto-predump: mosquitto container is not running" >&2
  exit 1
fi
# Flush persistence before copying mosquitto.db.
docker kill --signal=SIGUSR1 mosquitto >/dev/null
sleep 1
copy_one() {
  local src="$1" name="$2"
  local dst="$STAGING/$name"
  local tmp="$dst.tmp"
  rm -f "$tmp"
  docker cp "mosquitto:$src" "$tmp"
  test -s "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$dst"
}
copy_one /mosquitto/config/passwd passwd
copy_one /mosquitto/data/mosquitto.db mosquitto.db
{
  printf 'created_at=%s\n' "$(date -Is)"
  docker inspect mosquitto --format 'container={{.Name}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{end}}'
  stat -c 'passwd_size=%s passwd_mode=%a passwd_owner=%U:%G' "$STAGING/passwd"
  stat -c 'db_size=%s db_mode=%a db_owner=%U:%G' "$STAGING/mosquitto.db"
} > "$STAGING/manifest.txt"
chmod 600 "$STAGING/manifest.txt"
printf 'staged=%s\n' "$STAGING"
stat -c '%a %U:%G %s %n' "$STAGING/passwd" "$STAGING/mosquitto.db" "$STAGING/manifest.txt"
