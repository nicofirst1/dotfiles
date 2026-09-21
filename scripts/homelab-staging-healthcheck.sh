#!/usr/bin/env bash
set -u
FAILED=0
FAILURES=
ok(){ printf 'OK %s\n' "$*"; }
warn(){ printf 'WARN %s\n' "$*"; }
fail(){ printf 'FAIL %s\n' "$*"; FAILED=1; FAILURES="${FAILURES:+${FAILURES}; }$*"; }

printf '== homelab staging healthcheck %s ==\n' "$(date -Is)"

# Under sudo, rclone would look in /root and report a false missing Drive snapshot.
if [ "$(id -u)" -eq 0 ] && [ -z "${RCLONE_CONFIG:-}" ] && [ -r /home/nico/.config/rclone/rclone.conf ]; then
  export RCLONE_CONFIG=/home/nico/.config/rclone/rclone.conf
fi

# System baseline.
if systemctl --failed --no-pager | grep -q '^0 loaded units listed'; then ok 'systemd_failed_units=0'; else fail 'systemd_failed_units_nonzero'; systemctl --failed --no-pager; fi
if [ -f /var/run/reboot-required ]; then warn 'reboot_required=yes'; else ok 'reboot_required=no'; fi
if systemctl is-active --quiet caddy; then ok 'caddy_active'; else fail 'caddy_not_active'; fi
if sudo /usr/local/bin/caddy validate --config /etc/caddy/Caddyfile >/tmp/homelab-health-caddy-validate.out 2>&1; then ok 'caddy_config_valid'; else fail 'caddy_config_invalid'; sed -n '1,40p' /tmp/homelab-health-caddy-validate.out; fi

# Containers.
for c in grafana mosquitto frigate uptime-kuma searxng open-webui-hermes; do
  state=$(docker inspect "$c" --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}' 2>/dev/null || true)
  case "$c:$state" in
    grafana:'running healthy'|mosquitto:'running healthy'|frigate:'running healthy'|uptime-kuma:'running healthy'|searxng:'running no-health'|open-webui-hermes:'running healthy') ok "container_${c}=${state}" ;;
    *) fail "container_${c}=${state:-missing}" ;;
  esac
done

# HTTP probes.
probe_code(){ name=$1; url=$2; expect=$3; code=$(curl -skS -o /tmp/homelab-health-${name}.out -w '%{http_code}' --max-time 15 "$url" || true); if [ "$code" = "$expect" ]; then ok "${name}_http=${code}"; else fail "${name}_http=${code}_expected_${expect}"; sed -n '1,3p' /tmp/homelab-health-${name}.out 2>/dev/null || true; fi; }
probe_code grafana http://127.0.0.1:3002/api/health 200
probe_code kuma http://127.0.0.1:3001/ 302
probe_code frigate http://127.0.0.1:5000/api/version 200
probe_code searxng http://127.0.0.1:8888/ 200
# Hermes gateways + dashboard + Open WebUI (Phase 08, moved from Ublion 2026-09-08).
probe_code hermes_default http://127.0.0.1:8643/health 200
probe_code hermes_prbot http://127.0.0.1:8642/health 200
probe_code hermes_default_noauth http://127.0.0.1:8643/v1/models 401
probe_code hermes_prbot_noauth http://127.0.0.1:8642/v1/models 401
probe_code hermes_dashboard http://192.168.178.46:9119/ 302
probe_code openwebui http://127.0.0.1:3000/health 200

# Caddy production-capable HTTPS routes. Use --resolve so this works before DNS cutover.
for pair in \
  'grafana:grafana.home.nicolobrandizzi.com:/api/health:200' \
  'frigate:frigate.home.nicolobrandizzi.com:/:200' \
  'kuma:status.home.nicolobrandizzi.com:/:302' \
  'searxng:searxng.home.nicolobrandizzi.com:/search?q=hermes&format=json:200' \
  'homelab:homelab.home.nicolobrandizzi.com:/:200' \
  'openwebui:openwebui.home.nicolobrandizzi.com:/:200' \
  'hermes:hermes.home.nicolobrandizzi.com:/:302' \
  'backrest:backrest.home.nicolobrandizzi.com:/:200' \
  'ha:ha.home.nicolobrandizzi.com:/:200'; do
  IFS=: read -r name host path expect <<< "$pair"
  code=$(curl -sS -o /tmp/homelab-health-caddy-${name}.out -w '%{http_code}' --max-time 25 --resolve "$host:443:127.0.0.1" "https://$host$path" || true)
  if [ "$code" = "$expect" ]; then ok "caddy_${name}_https=${code}"; else fail "caddy_${name}_https=${code}_expected_${expect}"; fi
done

# Grafana datasource/dashboard check.
if [ -f /srv/compose/grafana/.env ]; then
  set -a; . /srv/compose/grafana/.env; set +a
  PASS="${GF_SECURITY_ADMIN_PASSWORD:-${GRAFANA_ADMIN_PASSWORD:-}}"
  if [ -n "$PASS" ]; then
    ds=$(curl -fsS -u "admin:$PASS" http://127.0.0.1:3002/api/datasources 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))' 2>/dev/null || echo 0)
    db=$(curl -fsS -u "admin:$PASS" 'http://127.0.0.1:3002/api/search?type=dash-db' 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d))' 2>/dev/null || echo 0)
    [ "$ds" -ge 1 ] && ok "grafana_datasources=$ds" || fail "grafana_datasources=$ds"
    [ "$db" -ge 3 ] && ok "grafana_dashboards=$db" || fail "grafana_dashboards=$db"
  else
    fail 'grafana_password_env_missing'
  fi
fi

# Mosquitto auth/exposure.
if docker exec mosquitto sh -c 'mosquitto_pub -h 127.0.0.1 -p 1883 -u healthcheck -P "$HEALTHCHECK_PASSWORD" -t hermes/healthcheck -m ok' >/dev/null 2>&1; then ok 'mosquitto_auth_publish'; else fail 'mosquitto_auth_publish'; fi
if docker exec mosquitto sh -c 'mosquitto_pub -h 127.0.0.1 -p 1883 -t hermes/healthcheck/anon -m no >/tmp/anon.out 2>&1' 2>/dev/null; then fail 'mosquitto_anonymous_publish_unexpected'; else ok 'mosquitto_anonymous_refused'; fi
if sudo iptables -S DOCKER-USER | grep -q 'homelab-mqtt-allow-ha' && sudo iptables -S DOCKER-USER | grep -q 'homelab-mqtt-deny-non-ha'; then ok 'mosquitto_docker_user_rules_present'; else fail 'mosquitto_docker_user_rules_missing'; fi

# Frigate camera expectations.
python3 - <<'PY' >/tmp/homelab-health-frigate.out 2>/tmp/homelab-health-frigate.err
import json, urllib.request
print(urllib.request.urlopen('http://127.0.0.1:5000/api/version', timeout=5).read().decode().strip())
data=json.load(urllib.request.urlopen('http://127.0.0.1:5000/api/config', timeout=5))
for name,cfg in sorted(data.get('cameras',{}).items()): print(f'{name}={cfg.get("enabled")}')
PY
if grep -q 'cat_toilet=True' /tmp/homelab-health-frigate.out && grep -q 'living_room=True' /tmp/homelab-health-frigate.out; then ok 'frigate_camera_state_expected'; else fail 'frigate_camera_state_unexpected'; cat /tmp/homelab-health-frigate.out; fi

# SearXNG JSON for Hermes.
if curl -fsS --max-time 25 'http://127.0.0.1:8888/search?q=hermes&format=json' -o /tmp/homelab-health-searxng.json && python3 - <<'PY'
import json
with open('/tmp/homelab-health-searxng.json') as f: d=json.load(f)
assert isinstance(d.get('results', []), list)
assert len(d.get('results', [])) > 0
PY
then ok 'searxng_json_results'; else fail 'searxng_json_results'; fi

# HA warehouse export ownership/freshness.
if systemctl is-enabled --quiet home-automation-export.timer && systemctl is-active --quiet home-automation-export.timer; then
  ok 'ha_export_timer_active'
else
  fail 'ha_export_timer_not_active'
fi
svc_result=$(systemctl show home-automation-export.service -p Result --value 2>/dev/null || true)
svc_status=$(systemctl show home-automation-export.service -p ExecMainStatus --value 2>/dev/null || true)
if [ "$svc_result" = success ] && [ "$svc_status" = 0 ]; then
  ok 'ha_export_service_last_success'
else
  fail "ha_export_service_last_result=${svc_result:-unknown}_${svc_status:-unknown}"
fi
current_month="/srv/data/ha-warehouse/$(date +%Y-%m).parquet"
watermark='/srv/data/ha-warehouse/.watermark.json'
now=$(date +%s)
for item in "$current_month" "$watermark"; do
  if [ ! -s "$item" ]; then
    fail "ha_warehouse_missing_${item##*/}"
    continue
  fi
  mtime=$(stat -c %Y "$item")
  age=$((now - mtime))
  if [ "$age" -le 14400 ]; then
    ok "ha_warehouse_fresh_${item##*/}_age=${age}s"
  else
    fail "ha_warehouse_stale_${item##*/}_age=${age}s"
  fi
done

# Cat Grafana dataset job ownership/freshness.
cat_timer_ok=1
for timer in homelab-cat-toilet-visits-grafana.timer homelab-cat-movement-grafana.timer; do
  if systemctl is-enabled --quiet "$timer" && systemctl is-active --quiet "$timer"; then
    ok "cat_dataset_timer_active_${timer}"
  else
    fail "cat_dataset_timer_not_active_${timer}"
    cat_timer_ok=0
  fi
done
[ "$cat_timer_ok" -eq 1 ] && ok 'cat_dataset_timers_active'
for svc in homelab-cat-toilet-visits-grafana.service homelab-cat-movement-grafana.service; do
  svc_result=$(systemctl show "$svc" -p Result --value 2>/dev/null || true)
  svc_status=$(systemctl show "$svc" -p ExecMainStatus --value 2>/dev/null || true)
  if [ "$svc_result" = success ] && [ "$svc_status" = 0 ]; then
    ok "cat_dataset_service_last_success_${svc}"
  else
    fail "cat_dataset_service_last_result_${svc}=${svc_result:-unknown}_${svc_status:-unknown}"
  fi
done
now=$(date +%s)
for item in /srv/data/ha-warehouse/cat_toilet_visits.parquet /srv/data/ha-warehouse/cat_movement_events.parquet /srv/data/ha-warehouse/cat_movement_windows.parquet; do
  if [ ! -s "$item" ]; then
    fail "cat_dataset_missing_${item##*/}"
    continue
  fi
  mtime=$(stat -c %Y "$item")
  age=$((now - mtime))
  if [ "$age" -le 7200 ]; then
    ok "cat_dataset_fresh_${item##*/}_age=${age}s"
  else
    fail "cat_dataset_stale_${item##*/}_age=${age}s"
  fi
done

# Cat night report timer ownership.
if systemctl is-enabled --quiet homelab-cat-night-activity-report.timer && systemctl is-active --quiet homelab-cat-night-activity-report.timer; then
  ok 'cat_night_report_timer_active'
else
  fail 'cat_night_report_timer_not_active'
fi

# Backrest owns the backup schedule since 2026-09-09 (plans homelab-local 04:30, homelab-drive 05:15); homelab-backup.timer is disabled, kept as fallback.
if systemctl is-enabled --quiet backrest.service && systemctl is-active --quiet backrest.service; then
  ok 'backrest_scheduler_active'
else
  fail 'backrest_scheduler_not_active'
fi
export RESTIC_PASSWORD_FILE=/home/nico/.config/restic/homelab-local-password
check_restic_tag_fresh() {
  local label="$1" repo="$2" tag2="$3" max_age="${4:-129600}"
  local out err rc detail latest ts now age
  CRTF_FAIL=0
  CRTF_SUMMARY=""
  err="$(mktemp)"
  # </dev/null so a bad password file fails instead of blocking on a prompt;
  # timeout so a wedged remote cannot hang the whole healthcheck.
  out="$(RESTIC_REPOSITORY="$repo" timeout 120 restic snapshots --json --tag homelab-system --tag "$tag2" 2>"$err" </dev/null)"
  rc=$?
  detail="$(cat "$err" 2>/dev/null; printf '%s' "$out")"
  rm -f "$err"
  if [ "$rc" -ne 0 ] || printf '%s' "$out" | grep -q '"message_type":"exit_error"'; then
    detail="$(printf '%s' "$detail" | python3 -c 'import json,sys
raw = sys.stdin.read()
msg = ""
for line in raw.splitlines():
    line = line.strip()
    if line.startswith("{"):
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get("message_type") == "exit_error":
            msg = o.get("message", "")
            break
print(" ".join((msg or raw).split())[:180])' 2>/dev/null)"
    [ -n "$detail" ] || detail="restic exit ${rc}"
    [ "$rc" -eq 124 ] && detail="timed out after 120s: ${detail}"
    CRTF_FAIL=1; CRTF_SUMMARY="repo_error rc=${rc}"
    fail "restic_${label}_repo_error rc=${rc} ${detail:-unknown}"
    return
  fi
  latest="$(printf '%s' "$out" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = []
if not isinstance(d, list):
    d = []
print(max([x.get("time", "") for x in d], default=""))' 2>/dev/null || true)"
  if [ -z "$latest" ]; then CRTF_FAIL=1; CRTF_SUMMARY="snapshot_missing"; fail "restic_${label}_homelab_system_snapshot_missing"; return; fi
  ts=$(date -d "$latest" +%s 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$((now - ts))
  if [ "$age" -le "$max_age" ]; then CRTF_FAIL=0; CRTF_SUMMARY="fresh_age=${age}s"; ok "restic_${label}_homelab_system_fresh_age=${age}s"; else CRTF_FAIL=1; CRTF_SUMMARY="stale_age=${age}s"; fail "restic_${label}_homelab_system_stale_age=${age}s"; fi
}
check_restic_tag_fresh local /srv/restic local 129600
BACKUP_LOCAL_FAIL=$CRTF_FAIL; BACKUP_LOCAL_SUM=$CRTF_SUMMARY
check_restic_tag_fresh drive rclone:gdrive: drive 129600
BACKUP_DRIVE_FAIL=$CRTF_FAIL; BACKUP_DRIVE_SUM=$CRTF_SUMMARY

# Backup snapshot recency by tag.
export RESTIC_REPOSITORY=/srv/restic
export RESTIC_PASSWORD_FILE=/home/nico/.config/restic/homelab-local-password
for tag in homelab-grafana-stage homelab-mosquitto-stage homelab-frigate-stage homelab-uptime-kuma-stage homelab-searxng-stage; do
  if restic snapshots --json --tag "$tag" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if d else 1)'; then ok "restic_snapshot_${tag}_present"; else fail "restic_snapshot_${tag}_missing"; fi
done

# Predump scripts.
for p in /usr/local/sbin/homelab-mosquitto-predump /usr/local/sbin/homelab-searxng-predump /usr/local/sbin/homelab-sudoers-predump; do
  [ -x "$p" ] && ok "predump_present_${p##*/}" || fail "predump_missing_${p##*/}"
done

# Sudoers staging: /etc/sudoers.d is root-only, so backrest backs up staged copies.
if [ -f /srv/backups/staging/sudoers/.staged ]; then
  sud_age=$(( $(date +%s) - $(stat -c %Y /srv/backups/staging/sudoers/.staged 2>/dev/null || echo 0) ))
  sud_n=$(find /srv/backups/staging/sudoers -maxdepth 1 -type f ! -name '.staged' 2>/dev/null | wc -l)
  if [ "$sud_age" -le 172800 ] && [ "$sud_n" -gt 0 ]; then
    ok "sudoers_staged_n=${sud_n}_age=${sud_age}s"
  else
    fail "sudoers_staged_stale_or_empty_n=${sud_n}_age=${sud_age}s"
  fi
else
  fail 'sudoers_staged_missing'
fi

if [ "$FAILED" -eq 0 ]; then
  RESULT_STATUS=up
  RESULT_MSG=HEALTHCHECK_PASS
else
  RESULT_STATUS=down
  # A forwarded alert should already say where to look. Runbook paths are
  # relative to the claude_memory repo.
  RESULT_MSG="HEALTHCHECK_FAIL: $(printf '%s' "$FAILURES" | cut -c1-200)
where: journalctl -u homelab-staging-healthcheck -n 80
script: /usr/local/sbin/homelab-staging-healthcheck (+ /etc/homelab-staging-healthcheck.env)
runbook: claude_memory/wiki/projects/self-hosting/homelab-healthcheck-blind-spots.md"
fi

# Dedicated backup-health push (Kuma monitor "Backup health"). Carries only
# restic repo reachability and snapshot ages, so it separates "repo
# unreachable" from "snapshot stale" without the composite check's noise.
if [ -r /etc/homelab-staging-healthcheck.env ]; then
  # shellcheck disable=SC1091
  . /etc/homelab-staging-healthcheck.env
  if [ -n "${KUMA_PUSH_BACKUP_URL:-}" ]; then
    if [ "${BACKUP_LOCAL_FAIL:-1}" -eq 0 ] && [ "${BACKUP_DRIVE_FAIL:-1}" -eq 0 ]; then
      BACKUP_STATUS=up
    else
      BACKUP_STATUS=down
    fi
    if [ "$BACKUP_STATUS" = up ]; then
      BACKUP_MSG="local:${BACKUP_LOCAL_SUM:-not_run}; drive:${BACKUP_DRIVE_SUM:-not_run}"
    else
      BACKUP_MSG="local:${BACKUP_LOCAL_SUM:-not_run}; drive:${BACKUP_DRIVE_SUM:-not_run}
where: journalctl -u homelab-staging-healthcheck -n 80
repos: /srv/restic (local) + rclone:gdrive: (offsite, encrypted)
known: drive=repo_error is usually the WEEKLY rclone OAuth expiry -> rclone config reconnect gdrive: (headless: ssh -L 53682:127.0.0.1:53682)
runbook: claude_memory/wiki/projects/self-hosting/restic-backrest-backup.md"
    fi
    if curl -fsS --max-time 10 -G "${KUMA_PUSH_BACKUP_URL}" \
         --data-urlencode "status=${BACKUP_STATUS}" \
         --data-urlencode "msg=${BACKUP_MSG}" \
         --data-urlencode "ping=" >/dev/null 2>&1; then
      ok "kuma_push_backup_${BACKUP_STATUS}"
    else
      warn "kuma_push_backup_failed"
    fi
  fi
fi

if [ -r /etc/homelab-staging-healthcheck.env ]; then
  # shellcheck disable=SC1091
  . /etc/homelab-staging-healthcheck.env
  if [ -n "${KUMA_PUSH_URL:-}" ]; then
    if curl -fsS --max-time 10 -G "${KUMA_PUSH_URL}" \
         --data-urlencode "status=${RESULT_STATUS}" \
         --data-urlencode "msg=${RESULT_MSG}" \
         --data-urlencode "ping=" >/dev/null 2>&1; then
      ok "kuma_push_${RESULT_STATUS}"
    else
      warn "kuma_push_failed"
    fi
  fi
fi

echo "$RESULT_MSG"
exit "$FAILED"
