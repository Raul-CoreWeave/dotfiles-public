#!/usr/bin/env bash
# find-layer-candidates.sh — deterministic pre-filter for /meta-layering.
#
# Scans skill prose (SKILL.md + reference/*.md) for Class-A smells: deterministic
# glue described for the LLM to hand-execute that a script should own instead.
# Emits a JSON envelope of (a) per-line candidates the regex caught, and (b)
# per-skill semantic_scan_targets pointing the LLM at the prose + the skill's
# existing scripts/ so it can judge "fold into a script" vs "genuinely LLM work".
#
# The narrowing half of the scripts-first pattern, INVERTED (same shape as
# /meta-redundancy's scan-stores.sh): the script does cheap deterministic
# detection; the LLM does the semantic deterministic-vs-judgment classification.
#
# SCOPE v1: Class A only (within-skill under-scripted glue). Class B
# (CLAUDE.md/SKILL.md procedure-prose that should be extracted to a
# skill/reference) is deferred — see SKILL.md "Out of scope (v1+)".
#
# Does NOT scan a skill's own scripts/ dir — scripts are already the right
# layer. Does NOT scan its own (meta-layering) home — it documents these very
# smells and would self-match.
#
# Args:
#   --skill-roots=<csv>  dirs to search for skill homes (dirs containing
#                        SKILL.md). Default: ~/.claude/skills plus
#                        $PWD/.claude/skills-base and $PWD/.claude/skills when
#                        they exist and aren't the same as the first.
#   -h | --help
#
# Emits (stdout): a single JSON object (see "## Output contract" in SKILL.md).
#
# Exit codes:
#   0  scan completed (candidates may or may not be present)
#   2  arg error / dependency missing

set -uo pipefail

SKILL_ROOTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-roots=*) SKILL_ROOTS="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "find-layer-candidates: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "find-layer-candidates: jq required" >&2; exit 2; }
command -v rg >/dev/null || { echo "find-layer-candidates: rg required" >&2; exit 2; }

# Default roots: user-level skills + the project's skill homes when present.
if [[ -z "$SKILL_ROOTS" ]]; then
  roots=("$HOME/.claude/skills")
  for d in "$PWD/.claude/skills-base" "$PWD/.claude/skills"; do
    # realpath-compare so we don't double-scan when ~/.claude/skills is a
    # symlink that resolves to the same place as a project dir.
    [[ -d "$d" ]] || continue
    rp_d=$(cd "$d" 2>/dev/null && pwd -P)
    dup=""
    for r in "${roots[@]}"; do
      rp_r=$(cd "$r" 2>/dev/null && pwd -P)
      [[ "$rp_d" == "$rp_r" ]] && { dup=1; break; }
    done
    [[ -z "$dup" ]] && roots+=("$d")
  done
  SKILL_ROOTS=$(IFS=,; echo "${roots[*]}")
fi

# ── Class-A smell regexes ─────────────────────────────────────────────────
# Precision over recall (same posture as scan-stores.sh): catch the canonical
# phrasings, tag confidence, let the LLM finish. False positives expected —
# the LLM classifies deterministic-vs-judgment in Phase 1.
#
# 1. Subject-is-the-LLM + a determinism verb. Highest signal: prose telling the
#    LLM to do mechanical data-shaping. Excludes "the script <verb>" (that's
#    describing a script, not instructing the LLM) by anchoring on the subject.
LLM_DET_RE='(the LLM|LLM-side|LLM coordinator|the model)[^.]{0,48}(construct|reshap|re-?shap|normaliz|recompute|comput|deriv|stamp|wrap|hand-?build|hand-?built|massage|assemble)'
# 2. Inline jq reshape primitives appearing in prose (an LLM-built transform,
#    vs a script the skill already ships). Lower signal — also appears in legit
#    script-invocation docs; the LLM checks context.
INLINE_JQ_RE='jq -c?n |--slurpfile|--argjson |jq -n '
# 3. Mechanical time/staleness math prescribed for the LLM to run by hand.
MANUAL_MECH_RE='strftime|todateiso8601|date \+%s|stat -f %m|stat -c %Y'

CANDIDATES=""
SEM_TARGETS=""
SKILLS_SEEN=""
emit_cand() { CANDIDATES+="$1"$'\n'; }
emit_sem()  { SEM_TARGETS+="$1"$'\n'; }

scan_file() {  # $1 = file, $2 = skill_name, $3 = skill_home
  local file="$1" skill="$2" home="$3" rel; rel="${file#$home/}"
  local smell re
  for smell in llm-determinism inline-jq manual-mech; do
    case "$smell" in
      llm-determinism) re="$LLM_DET_RE" ;;
      inline-jq)       re="$INLINE_JQ_RE" ;;
      manual-mech)     re="$MANUAL_MECH_RE" ;;
    esac
    local conf; case "$smell" in
      llm-determinism) conf="review" ;;   # subject-is-LLM → strong
      inline-jq)       conf="low" ;;       # context-dependent
      manual-mech)     conf="low" ;;
    esac
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      local line text; line="${hit%%:*}"; text="${hit#*:}"
      emit_cand "$(jq -cn \
        --arg sk "$skill" --arg f "$rel" --argjson l "$line" \
        --arg sm "$smell" --arg c "$conf" --arg t "$text" \
        '{class:"A", skill:$sk, file:$f, line:$l, smell:$sm, confidence:$c,
          match:($t|ltrimstr(" ")|.[0:200]),
          route:"if deterministic (no inference) → fold into a scripts/*.sh of this skill (extend an existing one or add); if genuine judgment → keep (dismiss)"}')"
    done < <(rg -n --no-heading -i -e "$re" "$file" 2>/dev/null || true)
  done
}

IFS=',' read -ra ROOT_ARR <<< "$SKILL_ROOTS"
for root in "${ROOT_ARR[@]}"; do
  [[ -d "$root" ]] || continue
  # Each skill home = a dir directly containing SKILL.md.
  while IFS= read -r skillmd; do
    [[ -z "$skillmd" ]] && continue
    home="$(dirname "$skillmd")"
    skill="$(basename "$home")"
    # Skip our own home (documents these smells → self-match noise).
    [[ "$skill" == "meta-layering" ]] && continue

    # Files to scan: SKILL.md + reference/*.md. NOT scripts/ (right layer already).
    hits_before="$CANDIDATES"
    scan_file "$skillmd" "$skill" "$home"
    if [[ -d "$home/reference" ]]; then
      while IFS= read -r rf; do
        [[ -z "$rf" ]] && continue
        scan_file "$rf" "$skill" "$home"
      done < <(find "$home/reference" -type f -name '*.md' 2>/dev/null)
    fi

    # If this skill produced any candidate, emit a semantic target with the
    # scripts it already ships (fold-into targets) so the LLM knows where the
    # deterministic logic should land.
    if [[ "$CANDIDATES" != "$hits_before" ]]; then
      case ",$SKILLS_SEEN," in *",$skill,"*) : ;; *)
        SKILLS_SEEN+="$skill,"
        # Robust array build (the xargs|jq chain emitted invalid-JSON on empty
        # input — exactly the dirty-stdout class this sensor exists to catch).
        scripts_json='[]'
        _sj=$(find "$home/scripts" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; 2>/dev/null \
          | jq -R . | jq -cs '.' 2>/dev/null)
        [[ -n "$_sj" ]] && scripts_json="$_sj"
        emit_sem "$(jq -cn --arg sk "$skill" --arg h "$home" --argjson sp "$scripts_json" \
          '{skill:$sk, home:$h, scripts_present:$sp,
            instruction:"read the flagged lines in context; for each, decide: is the step PURE data-shaping / mechanical transform (no inference, no judgment)? → fold into one of scripts_present (or a new scripts/*.sh) and reduce the prose to an invocation. Is it genuine LLM judgment (symptom→file picking, RCA, scoping, NL classification)? → keep, mark false-positive. Cite the target script."}')"
      ;; esac
    fi
  done < <(find "$root" -type f -name 'SKILL.md' 2>/dev/null)
done

CAND_ARR=$(printf '%s' "$CANDIDATES" | jq -cs '.' 2>/dev/null || echo "[]")
SEM_ARR=$(printf '%s' "$SEM_TARGETS" | jq -cs '.' 2>/dev/null || echo "[]")

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg roots "$SKILL_ROOTS" \
  --argjson cand "${CAND_ARR:-[]}" \
  --argjson sem "${SEM_ARR:-[]}" \
  '{
    scanned_at: $ts,
    skill_roots: ($roots | split(",")),
    class_a_candidates: $cand,
    semantic_scan_targets: $sem,
    summary: {
      candidate_count: ($cand | length),
      skills_flagged: ($sem | length),
      by_smell: ($cand | group_by(.smell) | map({(.[0].smell): length}) | add // {})
    }
  }'

exit 0
