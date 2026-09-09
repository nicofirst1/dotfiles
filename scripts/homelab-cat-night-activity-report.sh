#!/usr/bin/env bash
# Homelab-owned monthly cat night activity report.
set -euo pipefail
export PATH="/home/nico/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HA_REPO="${HA_REPO:-/home/nico/repos/personal/home_automation}"
export HERMES_HOME="${HERMES_HOME:-/home/nico/.hermes}"
export HA_WAREHOUSE_LOG_DIR="${HA_WAREHOUSE_LOG_DIR:-/var/log/homelab-jobs}"
export HA_WAREHOUSE_DIR="${HA_WAREHOUSE_DIR:-/srv/data/ha-warehouse}"
if [[ -r /etc/homelab-cat-night-report.env ]]; then
  # shellcheck disable=SC1091
  source /etc/homelab-cat-night-report.env
fi
exec "$HA_REPO/scripts/cat_night_activity_cron.sh" "$@"
