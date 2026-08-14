#!/usr/bin/env bash
#
# openobserve-import-history.sh  —  one-shot backfill of historical Claude Code
#                                    conversation transcripts into OpenObserve.
#
# Claude Code only started live-exporting OTEL telemetry today (see
# openobserve-run.sh); every session before that exists solely as local JSONL
# transcripts under CLAUDE_CONFIG_DIR/projects/<project>/<session>.jsonl. This
# reads those, flattens each user/assistant turn to one doc, and bulk-ingests
# them into a SEPARATE stream ("claude_code_history") so this backfill's fixed
# schema never collides with the live "default" stream's evolving OTEL schema.
#
# Rerun-safe: a small state file records each transcript's path + line count
# already imported, so a rerun only sends newly-appended lines.
#
# Root creds: same sourcing pattern as openobserve-run.sh (~/.openobserve-creds,
# mode 600, gitignored, never echoed).
#
# Usage: openobserve-import-history.sh [--dry-run] [--file PATH]
#   --dry-run    parse + report counts, skip ingestion (still fine to run live,
#                a rerun after a real ingest just imports the delta)
#   --file PATH  import only this one transcript (for the one-file smoke test)

set -euo pipefail

CREDS_FILE="${OO_CREDS_FILE:-$HOME/.openobserve-creds}"
BASE_URL="${OO_BASE_URL:-http://127.0.0.1:5080}"
ORG="default"
STREAM="claude_code_history"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"
STATE_FILE="${OO_IMPORT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/openobserve-history-import/imported.json}"

DRY_RUN=0
ONLY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --file) ONLY_FILE="$2"; shift 2 ;;
    *) echo "openobserve-import-history: unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$CREDS_FILE" ]] || { echo "openobserve-import-history: creds file not found: $CREDS_FILE" >&2; exit 1; }
[[ -d "$PROJECTS_DIR" ]] || { echo "openobserve-import-history: no transcripts dir at $PROJECTS_DIR" >&2; exit 1; }
command -v python3 >/dev/null || { echo "openobserve-import-history: python3 required" >&2; exit 1; }

set -a; . "$CREDS_FILE"; set +a
: "${ZO_ROOT_USER_EMAIL:?ZO_ROOT_USER_EMAIL missing in $CREDS_FILE}"
: "${ZO_ROOT_USER_PASSWORD:?ZO_ROOT_USER_PASSWORD missing in $CREDS_FILE}"

mkdir -p "$(dirname "$STATE_FILE")"

args=(
  --base-url "$BASE_URL"
  --org "$ORG"
  --stream "$STREAM"
  --projects-dir "$PROJECTS_DIR"
  --state-file "$STATE_FILE"
  --user "$ZO_ROOT_USER_EMAIL"
  --password "$ZO_ROOT_USER_PASSWORD"
)
[[ "$DRY_RUN" -eq 1 ]] && args+=(--dry-run)
[[ -n "$ONLY_FILE" ]] && args+=(--file "$ONLY_FILE")

# The parse/batch/ingest logic is stdlib-only Python (urllib) — this repo has
# no HTTP-request dependency installed and the transform (JSONL -> flattened
# docs, resumable-by-line-count state) is more than jq can reasonably do.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/openobserve-import-history.py" "${args[@]}"
