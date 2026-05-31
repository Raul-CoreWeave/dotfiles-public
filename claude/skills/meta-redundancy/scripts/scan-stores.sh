#!/usr/bin/env bash
# scan-stores.sh — deterministic pre-filter for /meta-redundancy.
#
# Scans the action/reference persistence stores (todos, memory) and emits a
# JSON envelope of (a) deterministic misfile candidates the script CAN judge
# alone, and (b) pointers to the content the LLM must read to judge the
# *semantic* edges (shape classification).
#
# This is the narrowing half of the scripts-first pattern, INVERTED: the
# script does the cheap deterministic detection + structural bookkeeping; the
# LLM does the semantic shape-classification over the pointed-at files.
#
# DOES NOT scan CLAUDE.md scopes — memory↔CLAUDE.md is /meta-memory-audit's
# lane, CLAUDE.md↔CLAUDE.md is /meta-conflicts'. This sensor covers the OTHER
# stores on the content-SHAPE axis.
#
# Args:
#   --memory-slug=<slug>  project-memory dir slug under ~/.claude/projects/
#                         (default: derived from the launch CWD)
#   --stores=<csv>        limit scan to a subset of: todos,memory
#                         (default: both)
#   -h | --help
#
# Emits (stdout): a single JSON object (see "## Output contract" in SKILL.md).
#
# Exit codes:
#   0  scan completed (candidates may or may not be present)
#   2  arg error / dependency missing

set -uo pipefail

# Derive the default memory slug from the launch CWD (matches the
# /meta-memory-audit slug convention: /a/b/c -> -a-b-c).
default_slug() {
  pwd | sed 's#^/##; s#/#-#g; s#^#-#'
}

MEMORY_SLUG="$(default_slug)"
STORES="todos,memory"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --memory-slug=*)   MEMORY_SLUG="${1#*=}"; shift ;;
    --stores=*)        STORES="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "scan-stores: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq      >/dev/null || { echo "scan-stores: jq required" >&2; exit 2; }
command -v rg      >/dev/null || { echo "scan-stores: rg required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "scan-stores: python3 required (date math)" >&2; exit 2; }

TODO_DIR="$HOME/.claude/todos"
MEM_DIR="$HOME/.claude/projects/$MEMORY_SLUG/memory"

want() { [[ ",$STORES," == *",$1,"* ]]; }

# Accumulators (JSONL strings, joined into arrays at the end).
DET_CANDIDATES=""   # deterministic misfile candidates
SEMANTIC_TARGETS="" # pointers to files the LLM must read per edge

emit_det() { DET_CANDIDATES+="$1"$'\n'; }
emit_sem() { SEMANTIC_TARGETS+="$1"$'\n'; }

# ─── memory: volatile-state markers (edge memory→delete, defect expiry) ──
# CLAUDE.md § Memory Hygiene "No volatile state in memory": commit SHAs as
# state, "N commits ahead", "PR is open/merged", dated "as of <date>" snapshots.
# Precision over recall: only flag the canonical volatile phrasings, not bare
# SHAs (reference entries legitimately cite anchor SHAs as pointers). Confidence
# starts "review" — the LLM distinguishes volatile-state from legit-pointer.
if want memory && [[ -d "$MEM_DIR" ]]; then
  VOLATILE_RE='(commits? (ahead|behind)|ahead of (main|master)|\bPR (is )?(open|merged|closed)\b|[Aa]s of [0-9]{4}-[0-9]{2}-[0-9]{2})'
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; text="${rest#*:}"
    emit_det "$(jq -cn --arg f "$(basename "$file")" --argjson l "$line" --arg t "$text" \
      '{edge:"memory→delete",defect:"expiry",confidence:"review",store:"memory",
        file:$f,line:$l,signal:"volatile-marker",match:($t|ltrimstr(" ")|.[0:200]),
        route:"verify volatile-vs-pointer; if volatile → delete memory file (re-query, do not store)"}')"
  done < <(rg -n --no-heading -e "$VOLATILE_RE" "$MEM_DIR" 2>/dev/null || true)

  # Pointer for semantic edges over memory (memory→todo, memory→KB, memory⇄KB).
  emit_sem "$(jq -cn --arg d "$MEM_DIR" \
    '{store:"memory",dir:$d,
      edges:["memory→todo","memory→KB","memory⇄KB"],
      instruction:"read each *.md body; flag (a) imperative+future lines with no Why/How-to-apply scaffold → todo-shaped; (b) universal facts with no first-person, grep-target under a repo docs/ → KB-shaped; (c) a fact duplicated in a KB file → dup (KB wins)"}')"
fi

# ─── todos: semantic pointer for todo→KB (playbook-shaped bodies) ────────
if want todos && [[ -d "$TODO_DIR" ]]; then
  TODO_FILES=$(printf '%s\n' "$TODO_DIR"/*.md | jq -R . | jq -cs 'map(select(test("/.*\\.md$")))')
  emit_sem "$(jq -cn --argjson files "${TODO_FILES:-[]}" \
    '{store:"todos",files:$files,
      edges:["todo→KB"],
      instruction:"flag todo bodies that are numbered procedures / \"the canonical way to X is\" prose → playbook-shaped (belongs in a repo docs/), not an action item"}')"
fi

# ─── envelope ────────────────────────────────────────────────────────────
DET_ARR=$(printf '%s' "$DET_CANDIDATES" | jq -cs '.' 2>/dev/null || echo "[]")
SEM_ARR=$(printf '%s' "$SEMANTIC_TARGETS" | jq -cs '.' 2>/dev/null || echo "[]")

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg stores "$STORES" \
  --argjson det "${DET_ARR:-[]}" \
  --argjson sem "${SEM_ARR:-[]}" \
  '{
    scanned_at: $ts,
    stores_scanned: ($stores | split(",")),
    deterministic_candidates: $det,
    semantic_scan_targets: $sem,
    summary: {
      deterministic_count: ($det | length),
      semantic_target_count: ($sem | length),
      by_defect: ($det | group_by(.defect) | map({(.[0].defect): length}) | add // {})
    }
  }'

exit 0
