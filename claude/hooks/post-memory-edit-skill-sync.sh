#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write on a memory file (under
# ~/.claude/projects/*/memory/*.md), check whether the touched file
# references any skill SKILL.md content. If yes, nudge a skill-doc-sync
# in the next turn's context so the engineer remembers to check the
# referenced skill for documentation drift caused by the memory edit.
#
# Reference pattern: the memory file mentions a skill via either
#   1. A path containing `.claude/skills/` (project-scoped or user-scoped)
#   2. A slash command `/<skill-name>` (must match an installed skill —
#      not detected here for cost; the path match is the cheap reliable
#      proxy, and any /<name> mention typically appears alongside)
set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
case "$tool_name" in
  Edit|Write) : ;;
  *) exit 0 ;;
esac

file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")
# Match only memory files under ~/.claude/projects/*/memory/*.md
case "$file_path" in
  "$HOME/.claude/projects/"*"/memory/"*.md) : ;;
  *) exit 0 ;;
esac

# MEMORY.md is the index, not an entry. Skip — index churn doesn't
# meaningfully touch skill references.
case "$file_path" in
  *"/MEMORY.md") exit 0 ;;
esac

# Only fire on successful writes.
exit_code=$(jq -r '.tool_response.exit_code // 0' <<<"$input")
[[ "$exit_code" == "0" ]] || exit 0

# Read the post-write file and grep for skill references. Patterns:
#   - `.claude/skills*/.../SKILL.md` full path (covers `skills/`,
#     `skills-base/`, and any other skill-bearing dir prefixed `skills`)
#   - `/sync-skill-docs` slash command (explicit sync intent in the entry)
# A single combined grep on the file body.
#
# Hardened against substring-match false positives: the prior regex
# included bare `SKILL.md` as an alternative, which fired on any memory
# entry that mentioned the filename in narrative prose (past-failure
# example, reference doc paths, etc.). The hardened pattern requires
# `SKILL.md` to appear at the end of a `.claude/skills*/...` path —
# i.e., a real skill reference, not an incidental filename mention.
[[ -r "$file_path" ]] || exit 0
matches=$(grep -E -o '\.claude/skills[a-zA-Z0-9_./-]*SKILL\.md|/sync-skill-docs' "$file_path" 2>/dev/null | sort -u | head -5 || true)
[[ -n "$matches" ]] || exit 0

# Build a compact list for the additionalContext payload.
matches_oneline=$(echo "$matches" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')

jq -n --arg file "$file_path" --arg matches "$matches_oneline" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("Memory file just edited references skill content: " + $file + " (matched: " + $matches + "). If the edit changed a memory entry that pertains to a specific skill (e.g., usage gotcha, new flag pattern, output-voice clarification), run /sync-skill-docs <skill-name> to check whether the affected skill SKILL.md, reference/*.md, or KB index needs a corresponding update. Skip if the edit was unrelated to the matched references (e.g., a passing mention in cross-refs).")
  }
}'
