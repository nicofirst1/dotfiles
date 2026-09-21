#!/usr/bin/env bash
# Homelab encrypted restic backup to local /srv/restic and Drive rclone:gdrive:.
set -uo pipefail
WHICH="${1:-both}" # local | drive | both
case "$WHICH" in local|drive|both) ;; *) echo "usage: $0 [local|drive|both]" >&2; exit 2;; esac
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/home/nico/.config/restic/homelab-local-password}"
LOCAL_REPO="${RESTIC_REPO_LOCAL:-/srv/restic}"
DRIVE_REPO="${RESTIC_REPO_DRIVE:-rclone:gdrive:}"
PREDUMP="${PREDUMP:-/usr/local/sbin/homelab-backup-predump}"
TAG="homelab-system"
rc=0
say(){ printf '%s == %s\n' "$(date -Is)" "$*"; }
die(){ printf 'homelab-backup: %s\n' "$*" >&2; exit 2; }
command -v restic >/dev/null || die 'restic missing'
[[ -f "$RESTIC_PASSWORD_FILE" ]] || die "password file missing: $RESTIC_PASSWORD_FILE"
[[ -x "$PREDUMP" ]] || die "predump missing: $PREDUMP"

say pre-dump
if ! "$PREDUMP"; then
  echo 'homelab-backup: WARNING predump reported failures' >&2
  rc=1
fi

TARGETS=(
  /srv/compose
  /srv/data
  /srv/backups/staging
  /home/nico/repos/personal/home_automation
  /home/nico/.hermes
  /home/nico/repos/personal/claude_memory
  /home/nico/repos/personal/visibility-ops
  /home/nico/repos/personal/premura
  /home/nico/repos/personal/nicofirst1.github.io
  /home/nico/.local/share/premura
  /home/nico/memory-os
  /home/nico/.ssh
  /etc/systemd/system/open-webui-hermes.service.d
  /etc/systemd/system/backrest.service
  /etc/systemd/system/homelab-backup.timer.d
  /etc/docker/daemon.json
  /etc/fstab
  /etc/sudoers.d
  /home/nico/.config/systemd/user
  /etc/systemd/system/hermes-dashboard.service
  /etc/systemd/system/open-webui-hermes.service
  /home/nico/repos/dotfiles/scripts
  /home/nico/.config/rclone
  /home/nico/.config/restic
  /home/nico/.config/gh
  /etc/caddy
  /etc/systemd/system/home-automation-export.service
  /etc/systemd/system/home-automation-export.timer
  /etc/systemd/system/homelab-cat-toilet-visits-grafana.service
  /etc/systemd/system/homelab-cat-toilet-visits-grafana.timer
  /etc/systemd/system/homelab-cat-movement-grafana.service
  /etc/systemd/system/homelab-cat-movement-grafana.timer
  /etc/systemd/system/homelab-cat-night-activity-report.service
  /etc/systemd/system/homelab-cat-night-activity-report.timer
  /etc/systemd/system/homelab-backup.service
  /etc/systemd/system/homelab-backup.timer
  /etc/systemd/system/homelab-staging-healthcheck.service
  /etc/systemd/system/homelab-staging-healthcheck.timer
  /etc/systemd/system/mqtt-docker-user-rules.service
  /etc/homelab-home-automation-export.env
  /etc/homelab-staging-healthcheck.env
  /etc/homelab-cat-night-report.env
  /usr/local/sbin
)
EXCLUDES=(
  --exclude-caches
  --exclude /srv/data/mosquitto/config/passwd
  --exclude /srv/data/mosquitto/data/mosquitto.db
  --exclude /srv/data/searxng/searxng/settings.yml
  --exclude /srv/data/uptime-kuma/data/kuma.db
  --exclude /srv/data/grafana/grafana.db
  --exclude /srv/data/frigate/config/frigate.db
  --exclude /etc/caddy/caddy.env
  --exclude /etc/sudoers.d
  --exclude /home/nico/.hermes/state.db
  --exclude /home/nico/.hermes/state.db-wal
  --exclude /home/nico/.hermes/state.db-shm
  --exclude '/home/nico/.hermes/profiles/prbot/state.db*'
  --exclude '/home/nico/.hermes/data/open-webui/webui.db*'
  --exclude /home/nico/.hermes/data/open-webui/cache
  --exclude /home/nico/.hermes/hermes-agent/.venv
  --exclude /home/nico/.hermes/hermes-agent/venv
  --exclude /home/nico/.hermes/hermes-agent/node_modules
  --exclude /home/nico/.hermes/hermes-agent/.hermes-runtime
  --exclude /home/nico/.hermes/node
  --exclude /home/nico/.hermes/bin
  --exclude /home/nico/.hermes/lsp
  --exclude /home/nico/.hermes/venvs
  --exclude /home/nico/.hermes/.venv-google
  --exclude /home/nico/.hermes/cache
  --exclude /home/nico/.hermes/logs
  --exclude /home/nico/.hermes/tmp
  --exclude /home/nico/.hermes/backups
  --exclude /home/nico/.hermes/models_dev_cache.json
  --exclude '/srv/backups/staging/uptime-kuma/kuma.pre-*.db'
  --exclude '**/.git'
  --exclude '**/.venv'
  --exclude '**/node_modules'
  --exclude '**/__pycache__'
  --exclude '**/*.pyc'
  --exclude '**/.pytest_cache'
  --exclude '**/.mypy_cache'
  --exclude '**/.ruff_cache'
)
for t in "${TARGETS[@]}"; do [[ -e "$t" ]] || die "backup target missing: $t"; done

run_repo(){
  local label="$1" repo="$2"; shift 2
  say "$label backup -> $repo"
  RESTIC_REPOSITORY="$repo" restic backup "${TARGETS[@]}" --tag "$TAG" --tag "$label" "$@" "${EXCLUDES[@]}"
  local brc=$?
  if [[ $brc -ne 0 && $brc -ne 3 ]]; then echo "homelab-backup: $label backup failed rc=$brc" >&2; return "$brc"; fi
  [[ $brc -eq 3 ]] && echo "homelab-backup: $label had unreadable files rc=3, snapshot may exist" >&2
  say "$label forget/prune"
  RESTIC_REPOSITORY="$repo" restic forget --tag "$TAG" --tag "$label" --keep-daily 14 --keep-weekly 8 --keep-monthly 24 --prune >/dev/null || return 1
  RESTIC_REPOSITORY="$repo" restic snapshots --tag "$TAG" --tag "$label" --latest 1
}

if [[ "$WHICH" == local || "$WHICH" == both ]]; then run_repo local "$LOCAL_REPO" || rc=1; fi
if [[ "$WHICH" == drive || "$WHICH" == both ]]; then run_repo drive "$DRIVE_REPO" --pack-size 128 -o rclone.connections=2 || rc=1; fi
say "done rc=$rc"
exit "$rc"
