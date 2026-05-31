#!/usr/bin/env bash
# grep-sentinels.sh — extract WTF / GEM / LANDMINE / EUREKA sentinels from the
# Claude Code transcript archive.
#
# Consumes:
#   --since <date|Nd>     ISO-8601 date or relative duration (default: 90d)
#   --sentinel <type>     wtf|gem|landmine|eureka|all (default: wtf)
#   --topic-filter <sub>  substring match on the topic= field
#   --root <path>         transcript archive root (default: $HOME/.claude/projects)
#   -h | --help           print usage and exit
#
# Emits:
#   One JSON object per match to stdout, newline-delimited:
#     {"file":"...","session":"...","ts":"...","topic":"...","classified":"...","claim":"..."}
#   Parse failures emit:
#     {"file":"...","parse_error":"...","raw":"..."}
#
# Exit codes:
#   0  at least one match
#   1  no matches (clean run, no sentinels found in scope)
#   2  arg error / missing dependency / transcript root not found

set -euo pipefail

SINCE="90d"
SENTINEL="wtf"
TOPIC_FILTER=""
ROOT="${TRANSCRIPT_ROOT:-$HOME/.claude/projects}"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)         SINCE="$2"; shift 2 ;;
    --since=*)       SINCE="${1#*=}"; shift ;;
    --sentinel)      SENTINEL="$2"; shift 2 ;;
    --sentinel=*)    SENTINEL="${1#*=}"; shift ;;
    --topic-filter)  TOPIC_FILTER="$2"; shift 2 ;;
    --topic-filter=*) TOPIC_FILTER="${1#*=}"; shift ;;
    --root)          ROOT="$2"; shift 2 ;;
    --root=*)        ROOT="${1#*=}"; shift ;;
    -h|--help)       usage ;;
    *) echo "grep-sentinels: unknown arg: $1" >&2; usage ;;
  esac
done

# ─── Dependencies ───────────────────────────────────────────────────────
command -v rg >/dev/null || { echo "grep-sentinels: rg required" >&2; exit 2; }
command -v jq >/dev/null || { echo "grep-sentinels: jq required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "grep-sentinels: python3 required" >&2; exit 2; }

[[ -d "$ROOT" ]] || { echo "grep-sentinels: transcript root not found: $ROOT" >&2; exit 2; }

# ─── Compute --since cutoff ─────────────────────────────────────────────
# Accept either ISO-8601 (2026-04-01 or 2026-04-01T00:00:00Z) or Nd / Nh / Nw.
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
  # Treat bare date as start of day UTC
  if [[ "$SINCE" == *T* ]]; then
    CUTOFF="$SINCE"
  else
    CUTOFF="${SINCE}T00:00:00Z"
  fi
else
  echo "grep-sentinels: --since must be Nd/Nh/Nw or YYYY-MM-DD[Thh:mm:ssZ] (got: $SINCE)" >&2
  exit 2
fi

# ─── Build sentinel pattern ─────────────────────────────────────────────
case "$SENTINEL" in
  wtf)      PATTERN='META-WTF '       ;;
  gem)      PATTERN='META-GEM '       ;;
  landmine) PATTERN='META-LANDMINE '  ;;
  eureka)   PATTERN='META-EUREKA '    ;;
  all)      PATTERN='META-(WTF|GEM|LANDMINE|EUREKA) ' ;;
  *) echo "grep-sentinels: --sentinel must be one of wtf|gem|landmine|eureka|all (got: $SENTINEL)" >&2; exit 2 ;;
esac

# ─── Grep transcripts ──────────────────────────────────────────────────
# rg with -uu to bypass gitignore (transcript archives are typically excluded).
# Output one match per line including filename; we'll parse the sentinel
# attributes from the surrounding context per-line.
MATCHES=$(rg -uu --no-line-number --no-heading -e "$PATTERN" "$ROOT" 2>/dev/null || true)

if [[ -z "$MATCHES" ]]; then
  exit 1
fi

# ─── Parse and emit ────────────────────────────────────────────────────
# Sentinel format:
#   <!-- META-WTF v=1 t=2026-05-20T14:35:00Z topic=cli-flag-misnamed classified=skill-bug claim="..." -->
# Attributes can survive in raw form ("...") or JSON-escaped form (\"...\")
# inside the transcript JSONL string fields. The marker tag (META-WTF) is
# delimiter-free so it greps cleanly either way.

EMITTED_ANY=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # file:rawmatch — rg with --no-heading prepends "filepath:" on each line
  file="${line%%:*}"
  rest="${line#*:}"

  # Find the sentinel substring. Handle both raw and JSON-escaped quotes by
  # extracting fields with permissive regexes that accept either form.
  #
  # We extract by named field with awk-ish bash regex; on failure emit a
  # parse_error record but keep going.

  # Extract sentinel body: text between "META-XXX" and the closing "-->"
  if [[ "$rest" =~ META-(WTF|GEM|LANDMINE|EUREKA)[[:space:]](.*)--\> ]]; then
    KIND="${BASH_REMATCH[1]}"
    BODY="${BASH_REMATCH[2]}"
  else
    jq -nc --arg file "$file" --arg raw "$rest" '{file: $file, parse_error: "no sentinel body matched", raw: $raw}'
    continue
  fi

  # Extract per-field (tolerate \" or "):
  TS=$(echo "$BODY" | grep -oE 't=[^[:space:]]+' | head -1 | sed 's/^t=//; s/\\"//g; s/"//g')
  TOPIC=$(echo "$BODY" | grep -oE 'topic=[^[:space:]]+' | head -1 | sed 's/^topic=//; s/\\"//g; s/"//g')
  CLASS=$(echo "$BODY" | grep -oE 'classified=[a-z-]+' | head -1 | sed 's/^classified=//')
  # claim= may contain spaces inside quotes; extract greedily up to closing
  # quote followed by a space-then-attr or trailing space:
  CLAIM=$(echo "$BODY" | sed -nE 's/.*claim=\\?"([^"\\]*)\\?".*/\1/p')

  # ─── Apply --since cutoff ──────────────────────────────────────────────
  if [[ -n "$TS" && "$TS" < "$CUTOFF" ]]; then
    continue
  fi

  # ─── Apply --topic-filter ──────────────────────────────────────────────
  if [[ -n "$TOPIC_FILTER" && "$TOPIC" != *"$TOPIC_FILTER"* ]]; then
    continue
  fi

  # ─── Derive session id from filename ──────────────────────────────────
  SESSION=$(basename "$file" .jsonl)

  # ─── Emit JSON ────────────────────────────────────────────────────────
  jq -nc \
    --arg file "$file" \
    --arg session "$SESSION" \
    --arg kind "$KIND" \
    --arg ts "$TS" \
    --arg topic "$TOPIC" \
    --arg classified "$CLASS" \
    --arg claim "$CLAIM" \
    '{file: $file, session: $session, kind: $kind, ts: $ts, topic: $topic, classified: $classified, claim: $claim}'

  EMITTED_ANY=1
done <<< "$MATCHES"

[[ "$EMITTED_ANY" == "1" ]] && exit 0 || exit 1
