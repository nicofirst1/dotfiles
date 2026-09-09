#!/usr/bin/env bash
# Stage consistent homelab service state before restic.
set -uo pipefail
STAGING="${BACKUP_STAGING:-/srv/backups/staging}"
rc=0
log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
warn(){ log "WARN: $*"; rc=1; }
mkdir -p "$STAGING"/{grafana,frigate,uptime-kuma,mosquitto,searxng,firewall} || exit 2
chmod 700 /srv/backups "$STAGING" 2>/dev/null || true

stage_sqlite(){
  local name="$1" src="$2"
  local dir="$STAGING/$name"
  local dst="$dir/${name}.db"
  local tmp="$dst.tmp"
  mkdir -p "$dir"
  rm -f "$tmp"
  if [[ ! -f "$src" ]]; then warn "$name: missing $src"; [[ -f "$dst" ]] || return; return; fi
  if sqlite3 "$src" ".backup '$tmp'" 2>/dev/null || sudo -n sqlite3 "$src" ".backup '$tmp'" 2>/dev/null; then
    sudo -n chown nico:nico "$tmp" 2>/dev/null || true
    chmod 600 "$tmp" 2>/dev/null || true
    if [[ -s "$tmp" ]] && [[ "$(sqlite3 "$tmp" 'PRAGMA integrity_check;' 2>/dev/null | head -1)" == ok ]]; then
      mv -f "$tmp" "$dst"
      log "$name: sqlite staged $(stat -c%s "$dst") bytes"
    else
      rm -f "$tmp"; warn "$name: sqlite backup invalid"
    fi
  else
    rm -f "$tmp"; warn "$name: sqlite backup failed"
  fi
}

stage_sqlite grafana /srv/data/grafana/grafana.db
stage_sqlite frigate /srv/data/frigate/config/frigate.db
stage_sqlite uptime-kuma /srv/data/uptime-kuma/data/kuma.db
stage_sqlite hermes /home/nico/.hermes/state.db
stage_sqlite hermes-prbot /home/nico/.hermes/profiles/prbot/state.db
stage_sqlite hermes-cron /home/nico/.hermes/cron/executions.db
stage_sqlite hermes-prbot-cron /home/nico/.hermes/profiles/prbot/cron/executions.db
stage_sqlite hermes-kanban /home/nico/.hermes/kanban.db
stage_sqlite open-webui /home/nico/.hermes/data/open-webui/webui.db

if [[ -x /usr/local/sbin/homelab-mosquitto-predump ]]; then
  /usr/local/sbin/homelab-mosquitto-predump || warn 'mosquitto predump failed'
else
  warn 'mosquitto predump missing'
fi
if [[ -x /usr/local/sbin/homelab-searxng-predump ]]; then
  /usr/local/sbin/homelab-searxng-predump || warn 'searxng predump failed'
else
  warn 'searxng predump missing'
fi

# /etc/ufw is root-only, so stage a readable dump instead of backing up the tree.
mkdir -p "$STAGING/firewall"
if sudo -n ufw status numbered > "$STAGING/firewall/ufw-status.txt" 2>/dev/null; then
  chmod 600 "$STAGING/firewall/ufw-status.txt"
  log "firewall: ufw rules staged"
else
  warn "firewall: could not stage ufw status"
fi
if sudo -n iptables -S DOCKER-USER > "$STAGING/firewall/docker-user-rules.txt" 2>/dev/null; then
  chmod 600 "$STAGING/firewall/docker-user-rules.txt"
  log "firewall: DOCKER-USER rules staged"
else
  warn "firewall: could not stage DOCKER-USER rules"
fi

if [[ -f /etc/caddy/caddy.env ]]; then
  mkdir -p "$STAGING/caddy"
  if sudo -n install -o nico -g nico -m 600 /etc/caddy/caddy.env "$STAGING/caddy/caddy.env"; then
    log "caddy: caddy.env staged $(stat -c%s "$STAGING/caddy/caddy.env") bytes"
  else
    warn "caddy: could not stage /etc/caddy/caddy.env"
  fi
else
  warn "caddy: /etc/caddy/caddy.env missing"
fi

# Hermes venv package list, so the venv can be rebuilt (uv sync alone prunes needed packages).
mkdir -p "$STAGING/hermes"
if /home/nico/.local/bin/uv pip freeze --python /home/nico/.hermes/hermes-agent/.venv/bin/python > "$STAGING/hermes/venv-freeze.txt" 2>/dev/null; then
  chmod 600 "$STAGING/hermes/venv-freeze.txt"; log "hermes: venv freeze staged $(wc -l < "$STAGING/hermes/venv-freeze.txt") lines"
else
  warn "hermes: venv freeze failed"
fi

{
  echo "created_at=$(date -Is)"
  find "$STAGING" -maxdepth 2 -type f -printf '%P %s %TY-%Tm-%TdT%TH:%TM\n' | sort
} > "$STAGING/.manifest"
chmod 600 "$STAGING/.manifest"
log "homelab predump finished rc=$rc"
exit "$rc"
