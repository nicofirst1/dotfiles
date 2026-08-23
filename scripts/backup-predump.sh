#!/usr/bin/env bash
# Consistent-snapshot hook for the nightly restic run.
#
# restic has no filesystem snapshot facility on Linux, so anything it reads is
# read live, mid-write. SQLite's own docs are blunt about the consequence: a copy
# taken mid-transaction "might contain some old and some new content, and thus be
# corrupt". So nothing here points restic at a live database — every stateful
# service is dumped to STAGING first, and restic backs up the dumps.
#
# Risk is not uniform, which is why the order below is what it is:
#   account.sqlite  rollback-journal mode -> the genuinely corrupting case
#   webui/frigate   WAL -> degrades to losing uncheckpointed txns, not corruption
#   redis           near-immune for dump.rdb (atomic rename), still dumped
#   qdrant          least protected by design -> snapshot API is the only safe read
#
# TWO RULES EARNED THE HARD WAY, both of which this script previously got wrong:
#
#   1. Never delete a good dump before a verified new one exists. A failed
#      `sqlite3 .backup` still CREATES its destination as a 0-byte file, and
#      `PRAGMA integrity_check` on a 0-byte file returns "ok" — so a failed dump
#      used to overwrite last night's good copy with an empty database that
#      passed verification. Everything below writes to .tmp and mv's on success.
#
#   2. Every exclude in backup-ublion.sh must have a dump here. The live DB files
#      are excluded from restic, so an excluded-but-undumped database is in NO
#      backup at all, silently, with the run still reporting success. SQLITE_DBS
#      below is the single list both properties are checked against.
set -uo pipefail

STAGING="${BACKUP_STAGING:-/mnt/data/backup-staging}"
MEMOS_ENV="/home/nico/memory-os/docker/.env"
STALE_HOURS="${BACKUP_STALE_HOURS:-36}"
rc=0

log()  { printf '%s %s\n' "$(date -Is)" "$*"; }
warn() { log "WARN: $*"; rc=1; }

mountpoint -q /mnt/data || { log "FATAL: /mnt/data is not mounted"; exit 2; }
mkdir -p "$STAGING"/{sqlite,redis,qdrant,mysql} || { log "FATAL: cannot write $STAGING"; exit 2; }

# THE single source of truth for which SQLite databases exist. Discovered, not
# hand-listed: a hand-listed set is how prbot/state.db (54 MB) ended up excluded
# from restic but never dumped, and how profiles/*/cron/executions.db ended up
# being read live. backup-ublion.sh and Backrest both build their excludes from
# this function, so an exclude without a dump is impossible.
#
# SQLITE_ROOTS must stay in step with TARGETS in backup-ublion.sh: a database
# under a backed-up tree that this find never reaches is read LIVE by restic,
# which is the whole failure class this pair exists to close. The prunes mirror
# that script's excludes, so we never dump something that is not kept.
SQLITE_ROOTS=(
  /home/nico/.hermes
  /home/nico/.frigate/config
  /home/nico/.actual
  /home/nico/repos
  /home/nico/memory-os
  /home/nico/.config/claude
  /home/nico/agent
  /home/nico/skills
  /home/nico/data
  /home/nico/caddy-setup
  /home/nico/searxng
)
sqlite_sources() {
  find "${SQLITE_ROOTS[@]}" \
    \( -path '/home/nico/.hermes/hermes-agent*' \
       -o -path '/home/nico/.hermes/tmp' \
       -o -path '/home/nico/.hermes/cache' \
       -o -path '/home/nico/.hermes/venvs' \
       -o -path '/home/nico/.hermes/node' \
       -o -path '/home/nico/.hermes/lsp' \
       -o -path '/home/nico/.hermes/bin' \
       -o -path '/home/nico/.hermes/sandboxes' \
       -o -path '*/profiles/*/home/.cache' \
       -o -path '*/profiles/*/cache' \
       -o -path '*/profiles/*/lsp' \
       -o -path '*/profiles/*/bin' \
       -o -path '/home/nico/repos/personal/firefly-iii/db' \
       -o -name node_modules -o -name .venv -o -name venv -o -name .git \
       -o -name __pycache__ -o -name .mypy_cache -o -name .pytest_cache \
       -o -name .ruff_cache -o -name .next \
    \) -prune -o \
    -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print 2>/dev/null \
  | sort -u
}

# Staging name derived from the full relative path, plus a hash of that path.
# The readable part cannot be unique on its own: replacing "/" with "-" makes
# profiles/prbot/cron/executions.db and profiles/prbot-cron/executions.db the
# same name, and hermes profile directory names are user-chosen. A collision is
# silent and total -- last write wins, BOTH get manifest-claimed so no zombie or
# stale warning fires, and one database is simply absent from every backup with
# the run still green. The suffix makes that impossible.
staging_name() {
  local rel="${1#/home/nico/}"
  rel="${rel#.}"
  printf '%s.%s' "${rel//\//-}" "$(printf '%s' "$1" | sha1sum | cut -c1-8)"
}

# A pure read, used by tooling while a real run may be in flight -- answer it
# before taking the dump lock so it never blocks behind a running backup.
if [[ "${1:-}" == "--list-sources" ]]; then
  sqlite_sources
  exit 0
fi

# Serialize. Two callers can legitimately reach this at once -- Backrest runs it
# as a snapshot-start hook for BOTH plans, and backup-ublion.sh runs it too --
# and staging has no other locking, so concurrent runs race on the same .tmp
# files and truncate each other's manifest. (Observed: two overlapping runs left
# a 0-byte .manifest.new that neither finished.) Wait rather than fail: the
# second caller wants a fresh dump, and the first is producing exactly that.
exec 9>"$STAGING/.lock"
if ! flock -w "${BACKUP_LOCK_WAIT:-1800}" 9; then
  log "FATAL: another backup-predump.sh held the lock for >${BACKUP_LOCK_WAIT:-1800}s"
  exit 2
fi

# Every dump that succeeds records itself here. Anything left in STAGING that is
# not in the manifest is a zombie -- a store that was removed or renamed, whose
# last dump would otherwise be backed up as current forever.
MANIFEST_NEW="$STAGING/.manifest.new"
: > "$MANIFEST_NEW"
keep() { printf '%s\n' "$1" >> "$MANIFEST_NEW"; }

# --- SQLite ----------------------------------------------------------------
# .backup uses the online backup API: it takes a read lock per page batch and
# restarts if the source is written mid-copy, so the output is transactionally
# whole. Never `cp` these.
dump_sqlite() {
  local src="$1" name="$2"
  local dst="$STAGING/sqlite/$name" tmp="$STAGING/sqlite/$name.tmp"
  [[ -f "$src" ]] || { warn "sqlite: missing $src"; return; }
  rm -f "$tmp"

  # A read-only open cannot recover a hot journal and cannot create the -shm a
  # WAL database needs, so it is only the first attempt. The fallback is a normal
  # read-write open -- via sudo for the root-owned actual-budget files, which are
  # exactly the rollback-journal ones where a torn read actually corrupts.
  if ! sqlite3 "file:${src}?mode=ro" ".backup '${tmp}'" 2>/dev/null; then
    if [[ -w "$src" ]] && sqlite3 "$src" ".backup '${tmp}'" 2>/dev/null; then
      :
    elif sudo -n true 2>/dev/null && sudo -n sqlite3 "$src" ".backup '${tmp}'" 2>/dev/null; then
      sudo -n chown "$(id -u):$(id -g)" "$tmp" 2>/dev/null
    else
      rm -f "$tmp"
      warn "sqlite: dump FAILED for $src (keeping previous $name)"
      [[ -f "$dst" ]] && keep "sqlite/$name"   # still ours; staleness check will flag it
      return
    fi
  fi

  # A 0-byte file passes integrity_check, so size is checked FIRST and separately.
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"; warn "sqlite: EMPTY dump for $src (keeping previous $name)"
    [[ -f "$dst" ]] && keep "sqlite/$name"
    return
  fi
  local ic; ic=$(sqlite3 "$tmp" "PRAGMA integrity_check;" 2>&1 | head -1)
  if [[ "$ic" != "ok" ]]; then
    # Park it in attic/, which the sweep skips. Left beside the dumps it would
    # be an unclaimed file, so EVERY later run would warn ZOMBIE and exit 1 --
    # one transient corruption permanently poisoning the exit code, which is
    # also how a real failure stops being distinguishable from noise.
    mkdir -p "$STAGING/attic"
    mv -f "$tmp" "$STAGING/attic/$name.corrupt.$(date +%Y%m%d%H%M%S)"
    warn "sqlite: integrity_check on $name -> $ic (bad dump parked in attic/, previous $name intact)"
    [[ -f "$dst" ]] && keep "sqlite/$name"
    return
  fi
  # A 0-byte or truncated source is a *legal empty* SQLite database: .backup
  # exits 0 and yields a valid ~4 KB file that passes both the -s check and
  # integrity_check. Without this guard, one crash-truncated source replaces a
  # good 477 MB dump with a 4 KB empty one and logs "ok".
  if [[ -f "$dst" ]] && (( $(stat -c%s "$tmp") * 4 < $(stat -c%s "$dst") )); then
    mkdir -p "$STAGING/attic"
    mv -f "$tmp" "$STAGING/attic/$name.shrunk.$(date +%Y%m%d%H%M%S)"
    warn "sqlite: $name shrank >4x vs the previous dump — refusing to install it"
    keep "sqlite/$name"
    return
  fi
  mv -f "$tmp" "$dst" || { warn "sqlite: could not install $name"; return; }
  keep "sqlite/$name"
  log "sqlite: $name ($(stat -c%s "$dst") bytes, ok)"
}

# Write the live-DB exclude list where restic can consume it directly. Backrest
# runs restic itself with a STATIC plan config, so it cannot call --list-sources
# the way backup-ublion.sh does; an --exclude-file regenerated by this hook on
# every run keeps the "one list, derived twice" property intact for both callers.
EXCLUDE_FILE="$STAGING/.restic-excludes"
: > "$EXCLUDE_FILE.tmp"
while IFS= read -r src; do
  [[ -n "$src" ]] || continue
  printf '%s\n%s-wal\n%s-shm\n%s-journal\n' "$src" "$src" "$src" "$src" >> "$EXCLUDE_FILE.tmp"
  dump_sqlite "$src" "$(staging_name "$src")"
done < <(sqlite_sources)
if [[ -s "$EXCLUDE_FILE.tmp" ]]; then
  mv -f "$EXCLUDE_FILE.tmp" "$EXCLUDE_FILE"
else
  rm -f "$EXCLUDE_FILE.tmp"
  warn "no databases discovered — leaving previous exclude file in place"
fi

# --- Redis -----------------------------------------------------------------
# BGSAVE is async: LASTSAVE must actually advance before the rdb on disk is the
# one we asked for. Every value is validated as a number -- an error string or an
# empty reply compares "not equal" to the previous value and would otherwise be
# read as "the save completed", copying the PREVIOUS rdb and logging success.
if [[ -r "$MEMOS_ENV" ]]; then
  # Read the password INSIDE the container, from the env it already has. Passing
  # it as `docker exec -e REDISCLI_AUTH=...` puts the value in docker's own argv,
  # which is world-readable in `ps` for the life of the call -- the previous
  # version of this line claimed the opposite and was simply wrong.
  # Going through the container also means the instance we flush is the instance
  # we copy, rather than trusting whoever owns host port 6379.
  rcli() {
    docker exec -i docker-redis-1 sh -c \
      'REDISCLI_AUTH="$REDIS_PASSWORD" exec redis-cli "$@"' _ "$@" 2>/dev/null
  }
  lastsave() { local v; v=$(rcli LASTSAVE); [[ "$v" =~ ^[0-9]+$ ]] || return 1; printf '%s' "$v"; }

  if [[ "$(rcli PING)" == "PONG" ]]; then
    if ! before=$(lastsave); then
      warn "redis: LASTSAVE unreadable — not copying an unverified rdb"
    elif ! rcli BGSAVE >/dev/null; then
      warn "redis: BGSAVE rejected (already running, or MISCONF)"
    else
      saved=0
      for _ in $(seq 1 60); do
        sleep 1
        now=$(lastsave) || continue
        [[ "$now" != "$before" ]] && { saved=1; break; }
      done
      if (( ! saved )); then
        warn "redis: LASTSAVE never advanced — not copying a stale rdb"
      elif docker cp docker-redis-1:/data/dump.rdb "$STAGING/redis/dump.rdb.tmp" 2>/dev/null \
           && [[ -s "$STAGING/redis/dump.rdb.tmp" ]]; then
        mv -f "$STAGING/redis/dump.rdb.tmp" "$STAGING/redis/dump.rdb"
        keep "redis/dump.rdb"
        log "redis: dump.rdb ($(stat -c%s "$STAGING/redis/dump.rdb") bytes)"
      else
        rm -f "$STAGING/redis/dump.rdb.tmp"; warn "redis: docker cp failed"
      fi
    fi
  else
    warn "redis: no PONG"
  fi
else
  warn "redis: $MEMOS_ENV not readable"
fi

# --- Qdrant ----------------------------------------------------------------
# Qdrant is the one store with no crash-consistent on-disk form to copy; the
# snapshot API is the only correct read. Staged under a STABLE filename: Qdrant
# names each snapshot with a fresh timestamp, and a new name every night defeats
# restic dedup entirely -- it would store a full new copy in both repos, nightly,
# including the rate-limit-sensitive Drive one.
if [[ -r "$MEMOS_ENV" ]]; then
  QK=$(grep -m1 '^QDRANT_API_KEY=' "$MEMOS_ENV" | cut -d= -f2- | tr -d '"'"'")
  QURL="http://127.0.0.1:6333"
  mapfile -t cols < <(curl -sf -m 10 -H "api-key: $QK" "$QURL/collections" | jq -r '.result.collections[].name' 2>/dev/null)
  if (( ${#cols[@]} == 0 )); then warn "qdrant: could not list collections"; fi
  for c in "${cols[@]}"; do
    [[ -n "$c" ]] || continue
    enc=$(jq -rn --arg v "$c" '$v|@uri')
    snap=$(curl -sf -m 300 -XPOST -H "api-key: $QK" "$QURL/collections/$enc/snapshots" | jq -r '.result.name' 2>/dev/null)
    if [[ -z "$snap" || "$snap" == "null" ]]; then warn "qdrant: snapshot failed for $c"; continue; fi
    tmp="$STAGING/qdrant/$c.snapshot.tmp"
    if curl -sf -m 600 -H "api-key: $QK" -o "$tmp" \
         "$QURL/collections/$enc/snapshots/$(jq -rn --arg v "$snap" '$v|@uri')" && [[ -s "$tmp" ]]; then
      mv -f "$tmp" "$STAGING/qdrant/$c.snapshot"
      keep "qdrant/$c.snapshot"
      log "qdrant: $c ($(stat -c%s "$STAGING/qdrant/$c.snapshot") bytes)"
      # Only drop the server-side copy once ours is safely on disk.
      curl -sf -m 60 -XDELETE -H "api-key: $QK" \
        "$QURL/collections/$enc/snapshots/$(jq -rn --arg v "$snap" '$v|@uri')" >/dev/null \
        || warn "qdrant: could not delete server-side snapshot $snap"
    else
      rm -f "$tmp"
      warn "qdrant: download failed for $snap (server-side copy left in place)"
    fi
  done
else
  warn "qdrant: $MEMOS_ENV not readable"
fi

# --- MariaDB (Firefly III) -------------------------------------------------
# --single-transaction gives InnoDB a consistent read view without locking the
# app out. Without it this is the same torn-read problem as the SQLite case.
if docker inspect -f '{{.State.Running}}' firefly-iii-db 2>/dev/null | grep -q true; then
  tmp="$STAGING/mysql/firefly.sql.gz.tmp"
  if docker exec firefly-iii-db sh -c \
       'exec mariadb-dump --single-transaction --quick --routines \
          -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' 2>/dev/null \
       | gzip -c > "$tmp" && [[ -s "$tmp" ]] && gzip -t "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$STAGING/mysql/firefly.sql.gz"
    keep "mysql/firefly.sql.gz"
    log "mysql: firefly.sql.gz ($(stat -c%s "$STAGING/mysql/firefly.sql.gz") bytes)"
  else
    rm -f "$tmp"; warn "mysql: firefly dump failed (keeping previous)"
    [[ -f "$STAGING/mysql/firefly.sql.gz" ]] && keep "mysql/firefly.sql.gz"
  fi
else
  warn "mysql: firefly-iii-db not running"
  [[ -f "$STAGING/mysql/firefly.sql.gz" ]] && keep "mysql/firefly.sql.gz"
fi

# --- staleness + zombie sweep ----------------------------------------------
# Anything in STAGING that no dump claimed is a store that was removed or
# renamed; its last dump would be backed up as current forever, silently.
mv -f "$MANIFEST_NEW" "$STAGING/.manifest" \
  || warn "staging: could not install manifest (sweep below compares stale data)"
keep() { :; }
while IFS= read -r f; do
  rel="${f#"$STAGING"/}"
  case "$rel" in .manifest*|.restic-excludes*|.lock|attic/*) continue;; esac
  if ! grep -qxF "$rel" "$STAGING/.manifest"; then
    warn "staging: ZOMBIE $rel — no dump claimed it this run (store removed or renamed?)"
  elif [[ -n "$(find "$f" -mmin "+$((STALE_HOURS*60))" -print -quit)" ]]; then
    warn "staging: STALE $rel — older than ${STALE_HOURS}h, so it is not this run's data"
  fi
done < <(find "$STAGING" -type f ! -name '*.tmp')

log "pre-dump finished (rc=$rc)"
exit $rc
