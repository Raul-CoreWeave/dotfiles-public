#!/usr/bin/env bash
# find-collisions.sh — group rules by canonical header form and surface
# groups with multiple occurrences (cross-scope collisions).
#
# Consumes (stdin):
#   newline-delimited JSON, one rule per line, in the shape produced by
#   /meta-rules/scripts/extract-rules.sh:
#     {"scope":"...","file":"...","header":"...","level":N,"line":N,"body_preview":"..."}
#
# Args:
#   --threshold N        minimum occurrence count for a collision to surface (default 2)
#   --include-similar    also group by Levenshtein-similarity ≤ 2 on canonical headers
#   -h | --help
#
# Emits (stdout):
#   one JSON object per collision group:
#     {"canonical":"...","occurrences":N,"scopes":[...],"entries":[...]}
#
# Exit codes:
#   0  at least one collision surfaced
#   1  no collisions (clean run)
#   2  arg error / dependency missing

set -uo pipefail

THRESHOLD=2
INCLUDE_SIMILAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --threshold=*) THRESHOLD="${1#*=}"; shift ;;
    --include-similar) INCLUDE_SIMILAR=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "find-collisions: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "find-collisions: jq required" >&2; exit 2; }

# ─── Canonicalize headers ──────────────────────────────────────────────
# Strategy: lowercase, strip punctuation, collapse whitespace, sort words.
# This catches "Memory Hygiene" ≡ "memory hygiene" ≡ "Hygiene, Memory" etc.

INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
  echo "find-collisions: no input on stdin" >&2
  exit 2
fi

# Add a `canonical` field to each rule. We do this in jq for portability.
WITH_CANONICAL=$(echo "$INPUT" | jq -c '
  . + {
    canonical: (
      .header
      | ascii_downcase
      | gsub("[^a-z0-9 ]"; " ")
      | gsub("[[:space:]]+"; " ")
      | sub("^ +"; "")
      | sub(" +$"; "")
      | split(" ")
      | sort
      | join(" ")
    )
  }
')

# ─── Group by canonical form, filter by threshold ──────────────────────
GROUPED=$(echo "$WITH_CANONICAL" | jq -s --argjson threshold "$THRESHOLD" '
  group_by(.canonical)
  | map(select(length >= $threshold))
  | map({
      canonical: .[0].canonical,
      occurrences: length,
      scopes: (map(.scope) | unique),
      entries: map({scope, header, file, line, body_preview, level})
    })
  | sort_by(-(.occurrences))
')

# Emit one per line for streaming downstream consumption
EMITTED=$(echo "$GROUPED" | jq -c '.[]?')

if [[ -z "$EMITTED" ]]; then
  exit 1
fi

echo "$EMITTED"

# ─── Fuzzy matching (optional) ─────────────────────────────────────────
# v0: --include-similar is a placeholder. Implementing Levenshtein in
# bash/jq is non-trivial; defer to v1 where we'd use python3 with the
# stdlib `difflib.get_close_matches` or a small helper script.
if [[ "$INCLUDE_SIMILAR" == "1" ]]; then
  echo "find-collisions: --include-similar is v1; v0 surfaces exact-canonical matches only" >&2
fi

exit 0
