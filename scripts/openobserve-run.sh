#!/usr/bin/env bash
#
# openobserve-run.sh  —  launcher for the OpenObserve LaunchAgent
#
# Runs OpenObserve (single-binary OTLP store) in Docker, attached, so launchd's
# KeepAlive owns the process lifecycle. Claude Code exports OTEL metrics/logs/
# traces straight here over OTLP/HTTP at http://127.0.0.1:5080/api/default/v1/*
# (see ~/.config/claude/settings.json). No separate OTel Collector — OpenObserve
# ingests OTLP directly.
#
# Root creds live in ~/.openobserve-creds (mode 600, gitignored, NOT in the plist
# nor this public repo), same secret-hygiene pattern as litellm-router-run.sh.
# They apply only on the container's first run against an empty data dir.
#
# Bound to 127.0.0.1 on purpose: this is local telemetry, not a network service.
#
# Overridable via env (defaults in brackets):
#   OO_CREDS_FILE  [~/.openobserve-creds]           ZO_ROOT_USER_EMAIL / _PASSWORD
#   OO_DATA_DIR    [~/.local/share/openobserve]      persistent stream storage
#   OO_PORT        [5080]                             UI + OTLP/HTTP ingestion
#   OO_IMAGE       [public.ecr.aws/zinclabs/openobserve:latest]

set -euo pipefail

CREDS_FILE="${OO_CREDS_FILE:-$HOME/.openobserve-creds}"
DATA_DIR="${OO_DATA_DIR:-$HOME/.local/share/openobserve}"
PORT="${OO_PORT:-5080}"
IMAGE="${OO_IMAGE:-public.ecr.aws/zinclabs/openobserve:latest}"
NAME="openobserve"

[[ -f "$CREDS_FILE" ]] || { echo "openobserve: creds file not found: $CREDS_FILE" >&2; exit 1; }
command -v docker >/dev/null || { echo "openobserve: docker not on PATH" >&2; exit 1; }

set -a; . "$CREDS_FILE"; set +a
: "${ZO_ROOT_USER_EMAIL:?ZO_ROOT_USER_EMAIL missing in $CREDS_FILE}"
: "${ZO_ROOT_USER_PASSWORD:?ZO_ROOT_USER_PASSWORD missing in $CREDS_FILE}"

mkdir -p "$DATA_DIR"

# Clear any container left over from a hard kill so --name is free on restart.
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Attached (no -d) so launchd sees a long-running process and KeepAlive restarts
# it; --rm cleans up on exit so the next start is conflict-free.
exec docker run --rm --name "$NAME" \
  -p "127.0.0.1:${PORT}:5080" \
  -v "${DATA_DIR}:/data" \
  -e ZO_DATA_DIR="/data" \
  -e ZO_ROOT_USER_EMAIL="$ZO_ROOT_USER_EMAIL" \
  -e ZO_ROOT_USER_PASSWORD="$ZO_ROOT_USER_PASSWORD" \
  "$IMAGE"
