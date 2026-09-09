#!/usr/bin/env bash
# Homelab-owned hourly refresh for the Grafana cat toilet visit dataset.
set -euo pipefail
export PATH="/home/nico/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HA_REPO="${HA_REPO:-/home/nico/repos/personal/home_automation}"
export HERMES_HOME="${HERMES_HOME:-/home/nico/.hermes}"
export HA_WAREHOUSE_LOG_DIR="${HA_WAREHOUSE_LOG_DIR:-/var/log/homelab-jobs}"
export CAT_TOILET_VISITS_DATASET="${CAT_TOILET_VISITS_DATASET:-/srv/data/ha-warehouse/cat_toilet_visits.parquet}"
export FRIGATE_DB="${FRIGATE_DB:-/srv/data/frigate/config/frigate.db}"
exec "$HA_REPO/scripts/cat_toilet_visits_grafana_cron.sh" "$@"
