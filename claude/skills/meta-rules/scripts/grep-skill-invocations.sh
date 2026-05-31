#!/usr/bin/env bash
# grep-skill-invocations.sh — grep the Claude Code transcript archive for
# slash-command invocations and emit per-invocation NDJSON.
#
# Pairs with grep-citations.sh (rule-citation grep) — same archive, same
# rg-based scanning pattern, different signal axis. Citations measure
# CLAUDE.md rule activation; invocations measure skill/command usage.
#
# Does the skill-usage extraction deterministically in one rg + python pass,
# so consumers (e.g. /meta-retro) can compute week-over-week usage deltas
# without expensive LLM-side transcript reading.
#
# Consumes:
#   --since <Nd|Nh|Nw|date>  default 90d
#   --root <path>            transcript archive root (default $HOME/.claude/projects)
#   --include-builtins       include /clear, /rename, /help, /compact, /exit, /cost,
#                            /init, /login, /logout, /model, /config, /memory,
#                            /status, /review, /approve[d], /fast, /slow,
#                            /loadenv, /terminal-setup, /tos, /version, /export,
#                            /continue, /resume, /sandbox, /plugin, /hook,
#                            /effort, /mcp
#                            (default: excluded — they're built-ins, not skills)
#   -h | --help
#
# Emits NDJSON to stdout, one record per invocation:
#   {"skill":"<name>","session":"<id>","ts":"<iso8601>","file":"<path>"}
#
# Aggregation (counts, last-invoked, distinct-sessions) is the consumer's
# job — kept upstream so callers can group by their preferred axis.
#
# Exit codes:
#   0  at least one match
#   1  no matches (clean run)
#   2  arg error / missing dependency

set -euo pipefail

SINCE="90d"
ROOT="${TRANSCRIPT_ROOT:-$HOME/.claude/projects}"
INCLUDE_BUILTINS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --since=*) SINCE="${1#*=}"; shift ;;
    --root) ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#*=}"; shift ;;
    --include-builtins) INCLUDE_BUILTINS=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "grep-skill-invocations: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "grep-skill-invocations: transcript root not found: $ROOT" >&2; exit 2; }

command -v rg >/dev/null || { echo "grep-skill-invocations: rg required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "grep-skill-invocations: python3 required" >&2; exit 2; }

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
  echo "grep-skill-invocations: --since must be Nd/Nh/Nw or YYYY-MM-DD[Thh:mm:ssZ] (got: $SINCE)" >&2
  exit 2
fi

# ─── rg pass + python extraction ───────────────────────────────────────
# rg -uu        bypass gitignore (transcripts are typically gitignored)
# -F            fixed-string match for the literal anchor (fastest mode)
# --no-line-number  one-line-per-match output: <path>:<matched-line>
#
# Python takes each matched line, extracts the skill name from the
# <command-name>/<name></command-name> marker, applies builtin filter and
# --since cutoff, emits NDJSON.

EXTRACT_PY=$(cat <<'PYEOF'
import re, json, sys, os

cutoff = sys.argv[1]
include_builtins = sys.argv[2] == "1"

# Built-in Claude Code commands that surface via <command-name> but are
# NOT skills/plugins/user/project commands. Excluded by default from the
# "skill invocation" count.
builtin_re = re.compile(r'^(clear|rename|help|compact|exit|cost|init|login|logout|model|config|memory|status|review|approve[d]?|fast|slow|loadenv|terminal-setup|tos|version|export|continue|resume|sandbox|plugin|hook|effort|mcp)$')

cmd_re = re.compile(r'<command-name>/([\w:-]+)</command-name>')
ts_re = re.compile(r'"timestamp":"([^"]+)"')

emitted = 0
for line in sys.stdin:
    # rg --no-line-number output: <path>:<text>
    # Split on FIRST ':' — JSON content downstream may contain ':' freely.
    try:
        path, rest = line.split(':', 1)
    except ValueError:
        continue
    m = cmd_re.search(rest)
    if not m:
        continue
    skill = m.group(1)
    if not include_builtins and builtin_re.match(skill):
        continue
    ts_m = ts_re.search(rest)
    ts = ts_m.group(1) if ts_m else ""
    if ts and ts < cutoff:
        continue
    base = os.path.basename(path)
    session = base[:-6] if base.endswith(".jsonl") else base
    sys.stdout.write(json.dumps({"skill": skill, "session": session, "ts": ts, "file": path}) + "\n")
    emitted += 1

sys.exit(0 if emitted else 1)
PYEOF
)

if rg -uu -F '<command-name>/' --no-line-number "$ROOT" 2>/dev/null \
  | python3 -c "$EXTRACT_PY" "$CUTOFF" "$INCLUDE_BUILTINS"; then
  exit 0
else
  rc=$?
  # python exit 1 = no records emitted; bubble that up as our exit 1
  exit "$rc"
fi
