#!/usr/bin/env bash
# extract-rules.sh — parse a CLAUDE.md file, emit one JSON object per section
# header for downstream citation tracking by /meta-rules.
#
# Usage:
#   extract-rules.sh <claude-md-path> [--scope <name>]
#
# Emits to stdout (newline-delimited JSON):
#   {"scope":"<name>","file":"<path>","header":"<text>","level":N,"line":N,"body_preview":"<first ~100 chars of body>"}
#
# Headers at `##` and `###` levels are tracked. `####` and deeper are skipped
# (typically sub-points of a rule, not the rule itself). Top-level `#` (the
# file title) is also skipped.
#
# `scope` defaults to the basename of the file without extension (`CLAUDE` →
# `claude`). Override with --scope.

set -euo pipefail

FILE=""
SCOPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --scope=*) SCOPE="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [[ -z "$FILE" ]]; then FILE="$1"; shift
      else echo "extract-rules: unexpected arg: $1" >&2; exit 2
      fi
      ;;
  esac
done

[[ -n "$FILE" ]] || { echo "extract-rules: <claude-md-path> required" >&2; exit 2; }
[[ -f "$FILE" ]] || { echo "extract-rules: file not found: $FILE" >&2; exit 2; }
command -v jq >/dev/null || { echo "extract-rules: jq required" >&2; exit 2; }

# Derive scope from filename if not explicitly set
if [[ -z "$SCOPE" ]]; then
  BASE=$(basename "$FILE" .md)
  SCOPE=$(echo "$BASE" | tr '[:upper:]' '[:lower:]')
fi

# ─── Parse: find headers, capture body preview ──────────────────────────
# Strategy: walk line by line. When we hit a `##` or `###`, record header.
# Buffer the next non-empty lines (up to BODY_PREVIEW_CHARS) for the body
# preview. Emit on the next header or EOF.

BODY_PREVIEW_CHARS=120
current_header=""
current_level=0
current_line=0
current_body=""

emit() {
  [[ -z "$current_header" ]] && return 0
  # Truncate body preview
  local preview="${current_body:0:$BODY_PREVIEW_CHARS}"
  # Collapse whitespace
  preview=$(echo "$preview" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  jq -nc \
    --arg scope "$SCOPE" \
    --arg file "$FILE" \
    --arg header "$current_header" \
    --argjson level "$current_level" \
    --argjson line "$current_line" \
    --arg body_preview "$preview" \
    '{scope: $scope, file: $file, header: $header, level: $level, line: $line, body_preview: $body_preview}'
}

lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  # Match ## or ### headers (level 2 or 3 only)
  if [[ "$line" =~ ^(##+)[[:space:]]+(.+)$ ]]; then
    hashes="${BASH_REMATCH[1]}"
    header_text="${BASH_REMATCH[2]}"
    level=${#hashes}
    # Skip level 4+ (sub-points) and level 1 (file title)
    if [[ "$level" -eq 2 || "$level" -eq 3 ]]; then
      # Emit prior header
      emit
      # Start new header — strip trailing whitespace and any inline comment hash
      current_header=$(echo "$header_text" | sed 's/[[:space:]]*$//')
      current_level="$level"
      current_line="$lineno"
      current_body=""
    fi
  elif [[ -n "$current_header" && -n "$line" ]]; then
    # Buffer body until we have enough preview chars
    if [[ ${#current_body} -lt $BODY_PREVIEW_CHARS ]]; then
      if [[ -z "$current_body" ]]; then
        current_body="$line"
      else
        current_body="$current_body $line"
      fi
    fi
  fi
done < "$FILE"

# Emit final header
emit
