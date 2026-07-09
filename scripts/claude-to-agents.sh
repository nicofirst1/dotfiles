#!/bin/bash
#
# Migrate CLAUDE.md -> AGENTS.md across $HOME, making AGENTS.md the single
# source of truth and leaving CLAUDE.md behind as a symlink to it. Any tool
# that reads either name keeps working; you only ever edit AGENTS.md.
#
# Agent-oriented: it ALWAYS prints a full plan first (one tagged line per file)
# and does nothing until you pass --apply. Read the plan, eyeball the WARN/
# CONFLICT lines, then re-run with --apply.
#
# Per directory containing a CLAUDE.md:
#   [MIGRATE]  no AGENTS.md yet -> mv CLAUDE.md AGENTS.md; ln -s AGENTS.md CLAUDE.md
#   [APPEND]   AGENTS.md exists -> append CLAUDE.md into it, then symlink (only with --append)
#   [CONFLICT] AGENTS.md exists -> skipped; re-run with --append to merge
#   [DONE]     CLAUDE.md is already a symlink to AGENTS.md
#   [WARN]     something unexpected (symlink elsewhere, AGENTS.md is a symlink) -> skipped
#
# Safe to re-run: DONE files are skipped, nothing is hard-deleted destructively
# (CLAUDE.md content only ever moves into AGENTS.md, never lost).
set -euo pipefail

ROOT="$HOME"
APPLY=0
APPEND=0
INCLUDE_HIDDEN=0

usage() {
    cat <<'EOF'
Usage: claude-to-agents.sh [--apply] [--append] [--include-hidden] [ROOT]

  (no flags)         Dry run: print the plan, change nothing. Default.
  --apply            Actually perform the MIGRATE (and APPEND, if set) actions.
  --append           Resolve CONFLICTs by appending CLAUDE.md into the existing AGENTS.md.
  --include-hidden   Also scan hidden dirs (.cache, .cargo, ~/.claude, ...). Slow; off by default.
  ROOT               Directory to scan (default: $HOME).
EOF
}

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --append) APPEND=1 ;;
        --include-hidden) INCLUDE_HIDDEN=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
        *) ROOT="$arg" ;;
    esac
done

tilde() { printf '%s' "${1/#$HOME/~}"; }

# Pruning hidden dirs is the big speedup (5x on a real $HOME): it collapses
# .cache/.cargo/.npm/.git/... into one rule and excludes ~/.claude for free.
# node_modules and Library aren't hidden, so name them explicitly.
prune_expr=(-name node_modules -o -name Library)
[ "$INCLUDE_HIDDEN" -eq 0 ] && prune_expr+=(-o -name '.*')

n_migrate=0 n_append=0 n_conflict=0 n_done=0 n_warn=0

# find both regular files and symlinks named CLAUDE.md
while IFS= read -r -d '' c; do
    dir="$(dirname "$c")"
    a="$dir/AGENTS.md"

    if [ -L "$c" ]; then
        tgt="$(readlink "$c")"
        if [ "$(basename "$tgt")" = "AGENTS.md" ]; then
            echo "[DONE]     $(tilde "$c") -> $tgt"; n_done=$((n_done + 1))
        else
            echo "[WARN]     $(tilde "$c") is a symlink -> $tgt (not AGENTS.md); skipped"; n_warn=$((n_warn + 1))
        fi
        continue
    fi

    if [ -e "$a" ] || [ -L "$a" ]; then
        if [ -L "$a" ]; then
            echo "[WARN]     $(tilde "$a") is itself a symlink; skipped"; n_warn=$((n_warn + 1))
            continue
        fi
        if [ "$APPEND" -eq 1 ]; then
            echo "[APPEND]   $(tilde "$c") -> append into existing $(tilde "$a"), then symlink"
            n_append=$((n_append + 1))
            if [ "$APPLY" -eq 1 ]; then
                { printf '\n\n---\n# (merged from CLAUDE.md)\n\n'; cat "$c"; } >> "$a"
                rm "$c"
                ln -s AGENTS.md "$c"
            fi
        else
            echo "[CONFLICT] $(tilde "$a") exists; skipped (re-run with --append to merge)"
            n_conflict=$((n_conflict + 1))
        fi
        continue
    fi

    echo "[MIGRATE]  $(tilde "$c") -> $(tilde "$a") + symlink back"
    n_migrate=$((n_migrate + 1))
    if [ "$APPLY" -eq 1 ]; then
        mv "$c" "$a"
        ln -s AGENTS.md "$c"
    fi
done < <(
    find "$ROOT" \
        \( -type d \( "${prune_expr[@]}" \) -prune \) -o \
        \( -type f -o -type l \) -name CLAUDE.md -print0
)

echo
echo "plan: $n_migrate migrate, $n_append append, $n_conflict conflict, $n_done done, $n_warn warn"
if [ "$APPLY" -eq 0 ]; then
    echo "dry run — nothing changed. Re-run with --apply to execute."
    [ "$n_conflict" -gt 0 ] && echo "  ($n_conflict conflicts need --append to resolve.)"
fi
