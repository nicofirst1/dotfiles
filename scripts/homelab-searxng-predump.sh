#!/usr/bin/env bash
set -euo pipefail
STAGING="${SEARXNG_BACKUP_STAGING:-/srv/backups/staging/searxng}"
mkdir -p "$STAGING"
chmod 700 /srv/backups /srv/backups/staging "$STAGING" 2>/dev/null || true
if ! docker inspect -f "{{.State.Running}}" searxng 2>/dev/null | grep -q true; then
  echo "homelab-searxng-predump: searxng container is not running" >&2
  exit 1
fi
sudo install -o nico -g nico -m 600 /srv/data/searxng/searxng/settings.yml "$STAGING/settings.yml"
{
  printf "created_at=%s\n" "$(date -Is)"
  docker inspect searxng --format "container={{.Name}} status={{.State.Status}}"
  stat -c "settings_size=%s settings_mode=%a settings_owner=%U:%G" "$STAGING/settings.yml"
} > "$STAGING/manifest.txt"
chmod 600 "$STAGING/manifest.txt"
printf "staged=%s\n" "$STAGING"
stat -c "%a %U:%G %s %n" "$STAGING/settings.yml" "$STAGING/manifest.txt"
