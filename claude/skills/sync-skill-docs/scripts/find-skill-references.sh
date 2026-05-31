#!/usr/bin/env bash
# find-skill-references.sh — locate every reference to a skill across the
# documentation layers of a Claude Code apparatus, plus a git diff of the
# skill's home directory.
#
# Output: a single JSON manifest to stdout (or --output <path>). Layers are
# searched independently and emitted as separate arrays so the consuming LLM
# can reason about drift per-layer. The script does not interpret the
# matches — it only locates them.
#
# Usage:
#   find-skill-references.sh <skill-name> [--base=<git-ref>] [--output=<path>]
#
# Skill home resolution:
#   .claude/skills/<name>/   — the standard skill location (real dir, not a
#                              symlink; symlinks are treated as presence
#                              pointers to a canonical home elsewhere).
#
# Layers searched (the surfaces that reference a skill in a typical repo):
#   skill-home    <resolved-skill-home>/**/*       (source of truth, not drift)
#   claude-md     CLAUDE.md + CLAUDE.*.md at repo root
#   commands      .claude/commands/**/*.md
#   references    .claude/references/**/*.md
#   agents        .claude/agents/**/*.md
#   other-skills  .claude/skills/<other>/**/*.md   (cross-skill SKILL.md + prompts)
#   docs          docs/**/*.md  +  repo-root *.md  (README, CONTRIBUTING, …)
#
# Match pattern: structural references only — slash-command form, path
# segments, and file extensions. Avoids the false-positive flood that
# `\b<skill>\b` produces for skills whose names collide with common English
# words. The pattern is:
#
#   /<skill>\b           — slash-command form, table rows, prose refs
#   <skill>/             — directory segment (e.g., .claude/skills/<skill>/)
#   <skill>\.md          — file references (.../<skill>.md)
#
# This catches the references that actually matter for doc-sync (structural
# pointers, dispatch wiring, cross-skill See-alsos) and intentionally drops
# bare-prose mentions whose drift is rarely actionable. Hyphenated names work
# — `-` is non-word in regex.
#
# Exit codes:
#   0  success — manifest emitted (sections may be empty)
#   2  invalid arguments or skill-home not found
#   3  required tool missing (rg, jq, git)

set -euo pipefail

skill=""
base="HEAD"
output=""

usage() {
  cat <<EOF
Usage: $0 <skill-name> [--base=<git-ref>] [--output=<path>]

Locate every reference to a skill across documentation layers, plus a git
diff of the skill's home directory.

Options:
  --base=<ref>   Git ref to diff skill-home against. Default: HEAD (i.e.,
                 working-tree diff against the last commit). Use HEAD~N or
                 a branch name to compare against an older state.
  --output=<p>   Write JSON manifest to file instead of stdout.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base=*)   base="${1#--base=}"; shift ;;
    --output=*) output="${1#--output=}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -z "$skill" ]]; then skill="$1"
      else echo "unexpected positional: $1" >&2; usage >&2; exit 2; fi
      shift ;;
  esac
done

[[ -z "$skill" ]] && { usage >&2; exit 2; }

for tool in rg jq git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing required tool: $tool" >&2; exit 3; }
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not inside a git repo" >&2; exit 2; }
cd "$repo_root"

_resolve_skill_home() {
  # Skills live under .claude/skills/<name>/. Treat it as a real home only
  # when it's a real directory (not a symlink — those are presence pointers
  # to a canonical home elsewhere).
  local name="$1"
  local cand=".claude/skills/$name"
  if [[ -d "$cand" && ! -L "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  return 1
}

skill_home=$(_resolve_skill_home "$skill") || {
  echo "skill home not found: tried .claude/skills/$skill" >&2
  exit 2
}

pattern="(/${skill}\\b|${skill}/|${skill}\\.md)"

# search_files <layer-name> <files...> -> JSON array of {file,line,excerpt}
search_files() {
  local layer="$1"; shift
  local existing=()
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && existing+=("$f")
  done
  if [[ ${#existing[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  # rg exits 1 when there are no matches; absorb so the pipeline doesn't
  # trip set -o pipefail. jq -R -s on empty stdin produces "[]" by itself,
  # so no fallback is needed.
  { rg -n -H --no-heading --color=never "$pattern" "${existing[@]}" \
      2>/dev/null || true; } \
    | jq -R -s --arg layer "$layer" '
        split("\n")
        | map(select(length > 0))
        | map(capture("^(?<file>[^:]+):(?<line>\\d+):(?<text>.*)$"))
        | map({
            file: .file,
            line: (.line | tonumber),
            excerpt: (.text | .[0:200])
          })
      '
}

# _compute_help_drift — emit a JSON block comparing the skill's frontmatter
# `argument-hint` flag set against the flags listed in its `## Help` section.
# Catches the most common drift mode: a new flag added to the phase prose
# but missed in one of those two surfaces (which is what users read at
# runtime).
#
# Output shape:
#   {
#     has_help_section: bool,
#     argument_hint: string,
#     argument_hint_flags: [string],
#     help_section_flags: [string],
#     flags_in_hint_not_in_help: [string],
#     flags_in_help_not_in_hint: [string],
#     in_sync: bool
#   }
#
# Drift is only one heuristic — the consuming LLM still walks the phase prose
# in Phase 3 to catch deeper drift (e.g., a flag documented in prose but
# missing from BOTH hint and help). This function gives a cheap structural
# signal so the LLM doesn't have to derive it from scratch.
_compute_help_drift() {
  local skill_md="$1"
  local has_help="false"
  local hint=""
  local help_content=""

  if [[ -f "$skill_md" ]]; then
    if rg -q '^## Help[[:space:]]*$' "$skill_md"; then
      has_help="true"
      help_content="$(awk '
        /^## Help[[:space:]]*$/ { in_section = 1; next }
        in_section && /^## / { exit }
        in_section { print }
      ' "$skill_md")"
    fi
    # Frontmatter argument-hint: find the first line starting with
    # `argument-hint:` inside the leading `---...---` block.
    hint="$(awk '
      /^---$/ { n++; if (n == 2) exit; next }
      n == 1 && /^argument-hint:[[:space:]]*/ {
        sub(/^argument-hint:[[:space:]]*/, "")
        # Strip surrounding quotes if present.
        gsub(/^"/, ""); gsub(/"$/, "")
        print; exit
      }
    ' "$skill_md")"
  fi

  # Flag-token regex: short (`-h`) or long (`--no-cluster-health`).
  # Hyphens are valid mid-token; trailing `=` (option-with-value) is dropped
  # by the boundary.
  local hint_flags help_flags help_content_filtered
  hint_flags="$(printf '%s' "$hint" \
    | grep -oE -- '(^|[ 	,;()|[/])(-[a-z]|--[a-zA-Z][a-zA-Z0-9-]*)' \
    | sed -E 's/^[^A-Za-z0-9-]+//' \
    | sort -u || true)"
  # Pre-filter: drop the tail of any line after a `/<other-slash-command>`
  # invocation before flag extraction. Cross-skill references in narrative
  # prose (e.g., "Phase 5 invokes /other-skill --some-flag") would otherwise
  # be misread as this skill's own flags. Conservative — only drops the
  # portion AFTER a `/<name>` token where `<name>` is not the current skill.
  local skill_basename
  skill_basename="$(basename "$(dirname "$skill_md")")"
  help_content_filtered="$(printf '%s\n' "$help_content" \
    | awk -v self="$skill_basename" '
        {
          line = $0
          if (match(line, /\/[a-z][a-z0-9-]*[ 	]/)) {
            cmd = substr(line, RSTART + 1, RLENGTH - 2)
            if (cmd != self) {
              line = substr(line, 1, RSTART - 1)
            }
          }
          print line
        }
      ')"
  help_flags="$(printf '%s' "$help_content_filtered" \
    | grep -oE -- '(^|[ 	,;()|[/])(-[a-z]|--[a-zA-Z][a-zA-Z0-9-]*)' \
    | sed -E 's/^[^A-Za-z0-9-]+//' \
    | sort -u || true)"

  # Set diffs via comm (both inputs already sort -u).
  local in_hint_not_help in_help_not_hint
  in_hint_not_help="$(comm -23 <(printf '%s\n' "$hint_flags") \
                              <(printf '%s\n' "$help_flags") || true)"
  in_help_not_hint="$(comm -13 <(printf '%s\n' "$hint_flags") \
                              <(printf '%s\n' "$help_flags") || true)"

  local hint_arr help_arr diff_a diff_b
  hint_arr="$(printf '%s' "$hint_flags" \
    | jq -R -s 'split("\n") | map(select(length > 0))')"
  help_arr="$(printf '%s' "$help_flags" \
    | jq -R -s 'split("\n") | map(select(length > 0))')"
  diff_a="$(printf '%s' "$in_hint_not_help" \
    | jq -R -s 'split("\n") | map(select(length > 0))')"
  diff_b="$(printf '%s' "$in_help_not_hint" \
    | jq -R -s 'split("\n") | map(select(length > 0))')"

  jq -n \
    --arg has_help "$has_help" \
    --arg hint "$hint" \
    --argjson hint_flags "$hint_arr" \
    --argjson help_flags "$help_arr" \
    --argjson in_hint_not_help "$diff_a" \
    --argjson in_help_not_hint "$diff_b" \
    '{
      has_help_section: ($has_help == "true"),
      argument_hint: $hint,
      argument_hint_flags: $hint_flags,
      help_section_flags: $help_flags,
      flags_in_hint_not_in_help: $in_hint_not_help,
      flags_in_help_not_in_hint: $in_help_not_hint,
      in_sync: (
        ($has_help == "true")
        and (($in_hint_not_help | length) == 0)
        and (($in_help_not_hint | length) == 0)
      )
    }'
}

# Gather file lists per layer.
mapfile -t claude_md < <( \
  { find . -maxdepth 1 -name 'CLAUDE.md' -o -maxdepth 1 -name 'CLAUDE.*.md'; } \
    2>/dev/null | sed 's|^\./||' | sort -u)
mapfile -t commands < <(find .claude/commands -name '*.md' 2>/dev/null | sort)
mapfile -t references < <(find .claude/references -name '*.md' 2>/dev/null | sort)
mapfile -t agents < <(find .claude/agents -name '*.md' 2>/dev/null | sort)
mapfile -t docs < <( \
  { find docs -name '*.md' 2>/dev/null; \
    find . -maxdepth 1 -name '*.md' ! -name 'CLAUDE.md' ! -name 'CLAUDE.*.md' \
      2>/dev/null | sed 's|^\./||'; } | sort -u)

# Other skills' SKILL.md and prompts/, excluding the target skill itself.
# Skips symlinks (presence pointers) to avoid double-counting.
mapfile -t other_skills < <(
  if [[ -d .claude/skills ]]; then
    find .claude/skills \
      -mindepth 2 -maxdepth 2 -name 'SKILL.md' -not -type l \
      ! -path "*/$skill/*" 2>/dev/null
    find .claude/skills \
      -mindepth 3 -path "*/prompts/*" -name '*.md' -not -type l \
      ! -path "*/$skill/*" 2>/dev/null
  fi
)

# Build per-layer arrays.
home_listing=$(find "$skill_home" -type f 2>/dev/null | sort \
  | jq -R -s 'split("\n") | map(select(length > 0))')

claude_md_arr=$(search_files "claude-md" "${claude_md[@]:-/dev/null}")
commands_arr=$(search_files "commands" "${commands[@]:-/dev/null}")
references_arr=$(search_files "references" "${references[@]:-/dev/null}")
agents_arr=$(search_files "agents" "${agents[@]:-/dev/null}")
other_skills_arr=$(search_files "other-skills" "${other_skills[@]:-/dev/null}")
docs_arr=$(search_files "docs" "${docs[@]:-/dev/null}")

# Git diff of skill-home: changed file list + summary stats.
diff_files=$(git diff --name-only "$base" -- "$skill_home" 2>/dev/null \
  | jq -R -s 'split("\n") | map(select(length > 0))')
diff_stat=$(git diff --shortstat "$base" -- "$skill_home" 2>/dev/null \
  | jq -R -s 'gsub("\n+$"; "") | gsub("^\\s+"; "")')

# Working-tree (uncommitted) changes — separate from --base diff.
wt_status=$(git status --porcelain -- "$skill_home" 2>/dev/null \
  | jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map({
          status: .[0:2],
          path: .[3:]
        })
    ')

# Help-drift block: argument-hint flags vs `## Help` section flags.
help_drift_arr=$(_compute_help_drift "$skill_home/SKILL.md")

# Compose final manifest.
jq -n \
  --arg skill "$skill" \
  --arg skill_home "$skill_home" \
  --arg base "$base" \
  --argjson home_listing "$home_listing" \
  --argjson diff_files "$diff_files" \
  --argjson diff_stat "$diff_stat" \
  --argjson wt_status "$wt_status" \
  --argjson claude_md "$claude_md_arr" \
  --argjson commands "$commands_arr" \
  --argjson references "$references_arr" \
  --argjson agents "$agents_arr" \
  --argjson other_skills "$other_skills_arr" \
  --argjson docs "$docs_arr" \
  --argjson help_drift "$help_drift_arr" \
  '
  {
    skill: $skill,
    skill_home: $skill_home,
    diff_base: $base,
    home_listing: $home_listing,
    git: {
      changed_files: $diff_files,
      shortstat: $diff_stat,
      working_tree: $wt_status
    },
    layers: {
      "claude-md":    $claude_md,
      "commands":     $commands,
      "references":   $references,
      "agents":       $agents,
      "other-skills": $other_skills,
      "docs":         $docs
    },
    help_drift: $help_drift,
    summary: {
      home_files:        ($home_listing | length),
      changed_in_home:   ($diff_files | length),
      uncommitted_files: ($wt_status | length),
      total_matches:
        (($claude_md|length) + ($commands|length)
         + ($references|length) + ($agents|length)
         + ($other_skills|length) + ($docs|length)),
      layers_with_matches:
        ([$claude_md, $commands, $references,
          $agents, $other_skills, $docs]
         | map(select(length > 0)) | length),
      help_in_sync: ($help_drift.in_sync)
    }
  }
  ' | { if [[ -n "$output" ]]; then cat > "$output"; else cat; fi; }
