#!/usr/bin/env bash
# Homelab-owned Home Assistant warehouse export.
# Writes the canonical homelab warehouse under /srv/data/ha-warehouse.
set -euo pipefail

export HA_REPO="${HA_REPO:-/home/nico/repos/personal/home_automation}"
export UV_BIN="${UV_BIN:-/home/nico/.local/bin/uv}"
export HA_WAREHOUSE_DIR="${HA_WAREHOUSE_DIR:-/srv/data/ha-warehouse}"
export HA_EXPORT_MAX_WINDOW_HOURS="${HA_EXPORT_MAX_WINDOW_HOURS:-6}"
export LOG_DIR="${HA_WAREHOUSE_LOG_DIR:-/var/log/homelab-jobs}"
export LOG_FILE="${LOG_FILE:-${LOG_DIR}/home_automation_export.log}"

if [[ -r /etc/homelab-home-automation-export.env ]]; then
  # shellcheck disable=SC1091
  source /etc/homelab-home-automation-export.env
fi

mkdir -p "$LOG_DIR" "$HA_WAREHOUSE_DIR"

push_kuma() {
  local status="$1"
  local msg="$2"
  local ping="${3:-}"
  if [[ -n "${KUMA_PUSH_URL:-}" ]]; then
    curl -fsS -m 10 -o /dev/null "${KUMA_PUSH_URL}?status=${status}&msg=${msg}&ping=${ping}" \
      || printf '%s WARN: kuma push failed status=%s msg=%s\n' "$(date -Is)" "$status" "$msg" >>"$LOG_FILE"
  fi
}

fail() {
  local msg="$1"
  printf '%s ERROR: %s\n' "$(date -Is)" "$msg" >>"$LOG_FILE"
  push_kuma down "$msg" ""
  echo "$msg"
  exit 2
}

[[ -x "$UV_BIN" ]] || fail "ha-export-homelab: uv missing at $UV_BIN"
[[ -d "$HA_REPO" ]] || fail "ha-export-homelab: HA_REPO missing at $HA_REPO"

cd "$HA_REPO"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi
[[ -n "${HA_TOKEN:-}" ]] || fail "ha-export-homelab: HA_TOKEN missing in ${HA_REPO}/.env or environment"

printf '%s running ha-export --base-dir %s --max-window-hours %s\n' \
  "$(date -Is)" "$HA_WAREHOUSE_DIR" "$HA_EXPORT_MAX_WINDOW_HOURS" >>"$LOG_FILE"

started_ns=$(date +%s%N)
set +e
output=$("$UV_BIN" run --quiet ha-export \
  --base-dir "$HA_WAREHOUSE_DIR" \
  --max-window-hours "$HA_EXPORT_MAX_WINDOW_HOURS" \
  --json 2>&1)
status=$?
set -e
elapsed_ms=$(( ($(date +%s%N) - started_ns) / 1000000 ))
printf '%s ha-export-homelab status=%s elapsed_ms=%s\n%s\n' "$(date -Is)" "$status" "$elapsed_ms" "$output" >>"$LOG_FILE"
if [[ $status -ne 0 ]]; then
  push_kuma down "ha-export failed status=${status}" "$elapsed_ms"
  echo "$output"
  exit "$status"
fi

push_kuma up OK "$elapsed_ms"
exit 0
