#!/usr/bin/env bash
#
# docker-prune.sh — periodic Docker cleanup (run every 3 days by a LaunchAgent).
#
# Reclaims space from stopped containers, dangling images, and the build cache.
# Deliberately does NOT touch volumes — those hold data; prune them by hand.
#
# Triggered by com.nbrandizzi.docker-prune (StartInterval). If the Docker daemon
# isn't running it logs and exits 0, so launchd doesn't treat it as a failure;
# it just tries again on the next interval.

set -euo pipefail

LOG_FILE="${LOG_FILE:-${HOME}/Library/Logs/docker-prune/docker-prune.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

# Find the docker CLI (launchd has a minimal PATH).
DOCKER=""
for p in /usr/local/bin/docker /opt/homebrew/bin/docker \
         /Applications/Docker.app/Contents/Resources/bin/docker; do
    [ -x "$p" ] && DOCKER="$p" && break
done
[ -z "$DOCKER" ] && DOCKER="$(command -v docker || true)"
[ -z "$DOCKER" ] && { log "docker CLI not found — skipping."; exit 0; }

# Bail quietly if the daemon is down (Docker Desktop not started).
if ! "$DOCKER" info >/dev/null 2>&1; then
    log "Docker daemon not reachable — skipping this run."
    exit 0
fi

log "=== docker prune start ==="
log "before: $("$DOCKER" system df --format '{{.Type}} {{.Reclaimable}}' 2>/dev/null | tr '\n' '|')"

# -f to skip the interactive confirmation. Each line tee'd to the log.
"$DOCKER" container prune -f 2>&1 | tee -a "$LOG_FILE" || log "container prune failed"
"$DOCKER" image     prune -f 2>&1 | tee -a "$LOG_FILE" || log "image prune failed"
"$DOCKER" builder   prune -f 2>&1 | tee -a "$LOG_FILE" || log "builder prune failed"

log "after:  $("$DOCKER" system df --format '{{.Type}} {{.Reclaimable}}' 2>/dev/null | tr '\n' '|')"
log "=== docker prune done ==="
