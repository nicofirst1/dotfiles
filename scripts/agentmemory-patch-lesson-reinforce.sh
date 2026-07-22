#!/usr/bin/env bash
# Re-apply the local "reinforce lessons on recall" patch to the agentmemory bundle.
# Upstream: github.com/rohitg00/agentmemory#1065 - lesson confidence only ever decays because
# mem::lesson-recall is read-only and never calls reinforceLesson(). This patch makes recall
# reinforce the lessons it returns, so retrieval-and-use counteracts decay.
#
# node_modules is overwritten on every `npm i -g @agentmemory/agentmemory` update, so re-run this
# after any agentmemory upgrade, then restart the worker (see agentmemory-operations-runbook).
# Idempotent: skips if the patch marker is already present.
set -euo pipefail

BUNDLE="${1:-/opt/homebrew/lib/node_modules/@agentmemory/agentmemory/dist/src-CzgoepGU.mjs}"

if [[ ! -f "$BUNDLE" ]]; then
	echo "bundle not found: $BUNDLE" >&2
	echo "(path changes across versions - pass it as arg 1)" >&2
	exit 1
fi

if grep -q 'ponytail-local-patch(#1065)' "$BUNDLE"; then
	echo "already patched: $BUNDLE"
	exit 0
fi

python3 - "$BUNDLE" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="surrogateescape").read()
old = (
    "\t\treturn {\n"
    "\t\t\tsuccess: true,\n"
    "\t\t\tlessons: scored.slice(0, limit).map((s) => ({\n"
    "\t\t\t\t...s.lesson,\n"
    "\t\t\t\tscore: Math.round(s.score * 1e3) / 1e3\n"
    "\t\t\t}))\n"
    "\t\t};"
)
new = (
    "\t\tconst returned = scored.slice(0, limit);\n"
    "\t\t// ponytail-local-patch(#1065): reinforce recalled lessons so retrieval-and-use counteracts decay.\n"
    "\t\t// ceiling: boosts every top-`limit` query match, not only \"applied\" ones; query-match used as the usage proxy. Re-apply after npm update.\n"
    "\t\tawait Promise.all(returned.map((s) => {\n"
    "\t\t\treinforceLesson(s.lesson);\n"
    "\t\t\treturn kv.set(KV.lessons, s.lesson.id, s.lesson);\n"
    "\t\t}));\n"
    "\t\treturn {\n"
    "\t\t\tsuccess: true,\n"
    "\t\t\tlessons: returned.map((s) => ({\n"
    "\t\t\t\t...s.lesson,\n"
    "\t\t\t\tscore: Math.round(s.score * 1e3) / 1e3\n"
    "\t\t\t}))\n"
    "\t\t};"
)
if old not in s:
    print("anchor not found - bundle layout changed; patch by hand", file=sys.stderr)
    sys.exit(2)
if s.count(old) != 1:
    print("anchor not unique (%d matches) - refuse to patch" % s.count(old), file=sys.stderr)
    sys.exit(3)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new))
print("patched: %s" % p)
PY

echo "done - restart the agentmemory worker to load it:"
echo "  launchctl kickstart -k gui/\$(id -u)/com.nbrandizzi.agentmemory"
