#!/usr/bin/env bash
# grep-citations.sh — grep the Claude Code transcript archive for literal
# section-header citations.
#
# Consumes:
#   --patterns <file>     newline-separated list of literal strings to grep
#                         (typically section headers from extract-rules.sh)
#   --since <date|Nd>     ISO-8601 date or relative duration (default: 90d)
#   --root <path>         transcript archive root (default: $HOME/.claude/projects)
#   -h | --help
#
# Emits to stdout (newline-delimited JSON):
#   {"file":"<path>","session":"<id>","matched_header":"<text>","context":"<~80 chars>"}
#
# Implementation notes:
# - Uses rg -F (fixed-strings) -f patterns.txt for single-pass literal-string
#   matching. This is the fastest mode in rg.
# - Per-line dedup: if a transcript line contains multiple header matches,
#   each emits a separate JSON record. Aggregation upstream handles
#   counting.
# - Timestamp filtering uses the JSONL record's `timestamp` field where
#   available; falls back to a "found" sentinel (no ts) if missing.
#
# Exit codes:
#   0  at least one match
#   1  no matches (clean run)
#   2  arg error / missing dependency

set -euo pipefail

PATTERNS_FILE=""
SINCE="90d"
ROOT="${TRANSCRIPT_ROOT:-$HOME/.claude/projects}"
MIN_PATTERN_WORDS=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patterns) PATTERNS_FILE="$2"; shift 2 ;;
    --patterns=*) PATTERNS_FILE="${1#*=}"; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --since=*) SINCE="${1#*=}"; shift ;;
    --root) ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#*=}"; shift ;;
    --min-pattern-words) MIN_PATTERN_WORDS="$2"; shift 2 ;;
    --min-pattern-words=*) MIN_PATTERN_WORDS="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "grep-citations: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$PATTERNS_FILE" ]] || { echo "grep-citations: --patterns required" >&2; exit 2; }
[[ -f "$PATTERNS_FILE" ]] || { echo "grep-citations: patterns file not found: $PATTERNS_FILE" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "grep-citations: transcript root not found: $ROOT" >&2; exit 2; }

command -v rg >/dev/null || { echo "grep-citations: rg required" >&2; exit 2; }
command -v jq >/dev/null || { echo "grep-citations: jq required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "grep-citations: python3 required" >&2; exit 2; }

# ─── Compute --since cutoff ─────────────────────────────────────────────
if [[ "$SINCE" =~ ^[0-9]+d$ ]]; then
  DAYS="${SINCE%d}"
  CUTOFF=$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(days=$DAYS)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
elif [[ "$SINCE" =~ ^[0-9]+h$ ]]; then
  HOURS="${SINCE%h}"
  CUTOFF=$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(hours=$HOURS)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
elif [[ "$SINCE" =~ ^[0-9]+w$ ]]; then
  WEEKS="${SINCE%w}"
  CUTOFF=$(python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.now(timezone.utc) - timedelta(weeks=$WEEKS)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
elif [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
  if [[ "$SINCE" == *T* ]]; then CUTOFF="$SINCE"
  else CUTOFF="${SINCE}T00:00:00Z"
  fi
else
  echo "grep-citations: --since must be Nd/Nh/Nw or YYYY-MM-DD[Thh:mm:ssZ] (got: $SINCE)" >&2
  exit 2
fi

# ─── Filter patterns by minimum word count ──────────────────────────────
# Generic single-word headers ("Usage", "Notes", "Targets") match thousands
# of unrelated transcript occurrences (skill catalog, system reminders,
# random tool output). Default minimum is 2 words; override with
# --min-pattern-words 1 to include all.
FILTERED_PATTERNS=$(mktemp -t grep-citations-patterns.XXXXXX)
trap 'rm -f "$FILTERED_PATTERNS"' EXIT

awk -v min="$MIN_PATTERN_WORDS" 'NF >= min' "$PATTERNS_FILE" > "$FILTERED_PATTERNS"

if [[ ! -s "$FILTERED_PATTERNS" ]]; then
  echo "grep-citations: no patterns survived the --min-pattern-words=$MIN_PATTERN_WORDS filter" >&2
  exit 1
fi

# ─── rg pass over transcript archive ───────────────────────────────────
# -uu  bypass gitignore
# -F   fixed-string (literal) matching from --patterns file
# -f   read patterns from file
# --no-line-number  one-line-per-match output
# --json  structured output for downstream parsing (more robust than ad-hoc regex)
MATCHES=$(rg -uu -F -f "$FILTERED_PATTERNS" --json --no-line-number "$ROOT" 2>/dev/null || true)

if [[ -z "$MATCHES" ]]; then
  exit 1
fi

# ─── Parse rg --json output ────────────────────────────────────────────
# rg --json emits one JSON object per event (begin / match / end). We
# want the match events. For each, extract the file path, matched substring,
# and surrounding context. Then look up the timestamp from the parent
# JSONL line if recoverable.

EMITTED_ANY=0
while IFS= read -r ev; do
  [[ -z "$ev" ]] && continue
  # Only process match events
  TYPE=$(echo "$ev" | jq -r '.type // ""')
  [[ "$TYPE" != "match" ]] && continue

  FILE=$(echo "$ev" | jq -r '.data.path.text // ""')
  LINE_TEXT=$(echo "$ev" | jq -r '.data.lines.text // ""')

  # Iterate over each submatch (in case multiple patterns match one line)
  SUBMATCHES=$(echo "$ev" | jq -c '.data.submatches[]?' 2>/dev/null || true)
  while IFS= read -r sm; do
    [[ -z "$sm" ]] && continue
    MATCHED=$(echo "$sm" | jq -r '.match.text // ""')

    # Derive 80-char context: the matched substring with up to 40 chars
    # on each side (trimmed at line boundaries).
    START=$(echo "$sm" | jq -r '.start // 0')
    END=$(echo "$sm" | jq -r '.end // 0')
    CTX_START=$((START - 40 < 0 ? 0 : START - 40))
    CTX_LEN=$((END - CTX_START + 40))
    CONTEXT="${LINE_TEXT:$CTX_START:$CTX_LEN}"
    # Collapse whitespace, strip embedded newlines
    CONTEXT=$(echo "$CONTEXT" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')

    # Try to extract a timestamp from the parent JSONL line. The line text
    # contains the encoded JSON of a transcript record; look for `"timestamp":"..."` or
    # `"ts":"..."`.
    TS=$(echo "$LINE_TEXT" | grep -oE '"timestamp":"[^"]+"|"ts":"[^"]+"' | head -1 | sed 's/.*:"//; s/"$//')

    # Apply --since cutoff if we have a timestamp
    if [[ -n "$TS" && "$TS" < "$CUTOFF" ]]; then
      continue
    fi

    SESSION=$(basename "$FILE" .jsonl)

    jq -nc \
      --arg file "$FILE" \
      --arg session "$SESSION" \
      --arg matched "$MATCHED" \
      --arg context "$CONTEXT" \
      --arg ts "$TS" \
      '{file: $file, session: $session, matched_header: $matched, context: $context, ts: $ts}'
    EMITTED_ANY=1
  done <<< "$SUBMATCHES"
done <<< "$MATCHES"

[[ "$EMITTED_ANY" == "1" ]] && exit 0 || exit 1
