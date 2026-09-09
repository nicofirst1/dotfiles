#!/usr/bin/env bash
# Homelab-owned hourly refresh for Grafana cat movement datasets.
set -euo pipefail
export PATH="/home/nico/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HA_REPO="${HA_REPO:-/home/nico/repos/personal/home_automation}"
export HERMES_HOME="${HERMES_HOME:-/home/nico/.hermes}"
export HA_WAREHOUSE_LOG_DIR="${HA_WAREHOUSE_LOG_DIR:-/var/log/homelab-jobs}"
export CAT_MOVEMENT_DATASET_DIR="${CAT_MOVEMENT_DATASET_DIR:-/srv/data/ha-warehouse}"
export HA_WAREHOUSE_DIR="${HA_WAREHOUSE_DIR:-/srv/data/ha-warehouse}"
exec "$HA_REPO/scripts/cat_movement_grafana_cron.sh" "$@"
