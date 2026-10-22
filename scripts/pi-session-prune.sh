#!/usr/bin/env bash
#
# pi-session-prune.sh — delete pi session files older than N days.
#
# pi (the coding agent) stores every session as JSONL under
# ~/.pi/agent/sessions/<munged-cwd>/, one file per session plus subagent
# artifacts, and has no built-in bulk pruning (the session picker deletes one
# at a time). A big tree here slows pi's cold start: 19k files cost seconds of
# cold metadata reads before the first prompt.
#
# DRY-RUN BY DEFAULT: it only prints what would go. Nothing is deleted unless
# you pass --delete. Archive first if the sessions matter (2026-10-22's archive
# was made with: tar --zstd -cf ~/.pi/sessions-archive-$(date +%F).tar.zst
# -C ~/.pi/agent sessions).
#
# Usage:
#   pi-session-prune.sh                 # dry-run, 7-day cutoff
#   pi-session-prune.sh --days 14      # dry-run, different cutoff
#   pi-session-prune.sh --delete       # actually delete (>7 days old)
#
# Resumed sessions rewrite their file on use, so "last modified" is the right
# recency signal: anything touched in the cutoff window survives.

set -uo pipefail

days=7
delete=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --days)
            days="$2"
            shift 2
            ;;
        --delete)
            delete=1
            shift
            ;;
        *)
            echo "usage: pi-session-prune.sh [--days N] [--delete]" >&2
            exit 2
            ;;
    esac
done

sessions="${PI_CODING_AGENT_SESSION_DIR:-$HOME/.pi/agent/sessions}"
if [[ ! -d "$sessions" ]]; then
    echo "no sessions dir: $sessions" >&2
    exit 1
fi

# find -mmin +N means "not modified in the last N minutes" (mmin, not mtime:
# mtime +7 rounds up to 8 days).
mmin=$((days * 24 * 60))

before_files=$(find "$sessions" -type f | wc -l | tr -d ' ')
before_kb=$(du -sk "$sessions" | cut -f1)

# Paths inside sessions/ start with "--", so cd in and use "./" to keep
# find/du/xargs from parsing them as options.
cd "$sessions"

# shellcheck disable=SC2012  # find -print0 | xargs du -ck: last line is the total
prune_files=$(find . -type f -mmin +"$mmin" | wc -l | tr -d ' ')
prune_kb=$(find . -type f -mmin +"$mmin" -print0 |
    xargs -0 du -ck 2>/dev/null | tail -1 | cut -f1)

echo "pi sessions: $before_files files, $((before_kb / 1024)) MB"
echo "cutoff: ${days} days"
if [[ $delete -eq 1 ]]; then
    find . -type f -mmin +"$mmin" -delete
    find . -mindepth 1 -type d -empty -delete
    after_files=$(find . -type f | wc -l | tr -d ' ')
    after_kb=$(du -sk . | cut -f1)
    echo "pruned: $prune_files files, $((prune_kb / 1024)) MB"
    echo "left: $after_files files, $((after_kb / 1024)) MB"
else
    echo "would prune: $prune_files files, $((prune_kb / 1024)) MB (dry-run)"
    echo "pass --delete to remove them"
fi
