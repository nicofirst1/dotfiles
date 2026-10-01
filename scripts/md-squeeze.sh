#!/bin/sh
# md-squeeze: normalize .md files to the house style ("no new lines"):
#   - soft-wrapped prose paragraphs are joined into one line per paragraph
#   - runs of blank lines collapse to a single blank line
#   - file ends with exactly one newline
# Kept on their own lines: headings, list items (their continuation lines
# join into the item line), table rows, blockquote lines, fenced code blocks,
# YAML front matter, and capitalized `Key: value` metadata lines (Date:,
# Status:) that directly follow a heading or another metadata line.
# Usage: md-squeeze [dir] [--dry-run]
set -eu
dir=.
dry=0
for a in "$@"; do
  case "$a" in
    -n|--dry-run) dry=1 ;;
    *) dir=$a ;;
  esac
done
AWKPROG='
function flush() { if (buf != "") { print buf; buf = "" } }
BEGIN { buf = ""; blanks = 0; infence = 0; fm = 0; prevhead = 0; prevmeta = 0 }
NR == 1 && $0 ~ /^---[ \t\r]*$/ { fm = 1; print; next }
fm { sub(/\r$/, ""); print; if ($0 ~ /^---[ \t\r]*$/) fm = 0; next }
{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*(```|~~~)/) { flush(); if (blanks) { print ""; blanks = 0 }; infence = !infence; print line; prevhead = 0; prevmeta = 0; next }
  if (infence) { print line; next }
  sub(/[ \t]+$/, "", line)
  if (line !~ /[^ \t]/) { flush(); blanks++; next }
  if (blanks) { print ""; blanks = 0 }
  if (line ~ /^#+[ \t]/) { flush(); print line; prevhead = 1; prevmeta = 0; next }
  s = line; gsub(/[ \t]/, "", s)
  if (s !~ /[^-__=*]/ && length(s) >= 3) { flush(); print line; prevhead = 0; prevmeta = 0; next }
  if (line ~ /^[ \t]*[|]/) { flush(); print line; prevhead = 0; prevmeta = 0; next }
  if (line ~ /^[ \t]*>/) { flush(); print line; prevhead = 0; prevmeta = 0; next }
  if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) { flush(); buf = line; inlist = 1; prevhead = 0; prevmeta = 0; next }
  if (line ~ /^[A-Z][A-Za-z0-9_-]*:[ \t]/ && (prevhead || prevmeta)) { flush(); print line; prevmeta = 1; prevhead = 0; next }
  prevhead = 0; prevmeta = 0
  t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
  if (buf == "") { buf = t; inlist = 0; next }
  if (inlist || line !~ /^[ \t]/) { buf = buf " " t; next }
  flush(); buf = t; inlist = 0
}
END { flush() }
'
list=$(mktemp "${TMPDIR:-/tmp}/md-squeeze.XXXXXX") || exit 1
tmp=$(mktemp "${TMPDIR:-/tmp}/md-squeeze.XXXXXX") || exit 1
trap 'rm -f "$list" "$tmp"' EXIT INT TERM
find -H "$dir" -name '*.md' -type f \
  -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.git/*' -print > "$list"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  awk "$AWKPROG" "$f" > "$tmp" || exit 1
  cmp -s "$tmp" "$f" && continue
  printf '%s\n' "$f"
  if [ "$dry" -eq 0 ]; then cat "$tmp" > "$f"; fi
done < "$list"
