#!/usr/bin/env bash
# measure-context.sh — measure bytes / lines / estimated tokens for every
# surface that loads into a Claude Code session at startup.
#
# Usage:
#   measure-context.sh [--scope global|all] [--project-claude-md <path>]
#
# Defaults:
#   --scope all
#   --project-claude-md  auto-detected: nearest CLAUDE.md in CWD ancestor chain
#
# Emits to stdout (newline-delimited JSON):
#   {"category":"<name>","path":"<path>","bytes":N,"lines":N,"est_tokens":N,"note":"<optional>"}
#
# Categories: claude-md | claude-md-import | memory | skill-catalog
#             | agent-catalog | mcp-instructions
#
# Token estimate: bytes / 4 (English-prose heuristic). v0 accepts this; v1
# could integrate a real tokenizer.

# Note: NOT using `set -e` because the recursive walk_claude_md_imports
# pipeline propagates inner non-zero exits (rg returning 1 on files without
# @-imports) which would abort the script mid-walk. Explicit `[[ -f ... ]]`
# checks and `|| true` guards cover real error cases.
set -uo pipefail

SCOPE="all"
PROJECT_CLAUDE_MD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --scope=*) SCOPE="${1#*=}"; shift ;;
    --project-claude-md) PROJECT_CLAUDE_MD="$2"; shift 2 ;;
    --project-claude-md=*) PROJECT_CLAUDE_MD="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "measure-context: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "measure-context: jq required" >&2; exit 2; }
command -v wc >/dev/null || { echo "measure-context: wc required" >&2; exit 2; }

# ─── Resolve a writable tmpdir ──────────────────────────────────────────
# macOS sets TMPDIR to /var/folders/<...> for every user session, but a
# sandboxed Claude Code session may block writes there. Try $TMPDIR first
# (the sandbox sets this to the writable path when in sandbox mode); fall
# back to /tmp/claude (commonly sandbox-allowed) or /tmp; bail if none work.
# Without this, mktemp -t silently writes to /var/folders/..., the resulting
# tmpfile is never created, downstream dedup check `grep -qFx` always
# fails-open, and walk_claude_md_imports recurses forever on the first
# @-import.
META_CONTEXT_TMPDIR=""
for candidate in "${TMPDIR:-}" "/tmp/claude" "/tmp"; do
  [[ -z "$candidate" ]] && continue
  mkdir -p "$candidate" 2>/dev/null
  if [[ -d "$candidate" ]] && touch "$candidate/.meta-context-write-test.$$" 2>/dev/null; then
    rm -f "$candidate/.meta-context-write-test.$$"
    META_CONTEXT_TMPDIR="$candidate"
    break
  fi
done
if [[ -z "$META_CONTEXT_TMPDIR" ]]; then
  echo "measure-context: no writable tmpdir found (\$TMPDIR=${TMPDIR:-unset}, /tmp/claude, /tmp all failed)" >&2
  exit 1
fi

# ─── Auto-detect project CLAUDE.md ──────────────────────────────────────
if [[ -z "$PROJECT_CLAUDE_MD" && "$SCOPE" == "all" ]]; then
  dir=$(pwd)
  while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      PROJECT_CLAUDE_MD="$dir/CLAUDE.md"
      break
    fi
    dir=$(dirname "$dir")
  done
fi

# ─── Helper: emit one record ────────────────────────────────────────────
emit_record() {
  local category="$1" path="$2" note="${3:-}"
  [[ -f "$path" || -L "$path" ]] || return 0
  # Resolve symlink for accurate measurement
  local resolved
  resolved=$(readlink -f "$path" 2>/dev/null || echo "$path")
  [[ -f "$resolved" ]] || return 0

  local bytes lines est_tokens
  bytes=$(wc -c < "$resolved" | tr -d ' ')
  lines=$(wc -l < "$resolved" | tr -d ' ')
  est_tokens=$((bytes / 4))

  jq -nc \
    --arg category "$category" \
    --arg path "$path" \
    --argjson bytes "$bytes" \
    --argjson lines "$lines" \
    --argjson est_tokens "$est_tokens" \
    --arg note "$note" \
    '{category: $category, path: $path, bytes: $bytes, lines: $lines, est_tokens: $est_tokens, note: $note}'
}

# ─── Walk CLAUDE.md scope tree (recursive @-imports) ────────────────────
walk_claude_md_imports() {
  local file="$1" category="${2:-claude-md}"
  [[ -f "$file" ]] || return 0
  emit_record "$category" "$file"

  # Find @-imports inside the file. Patterns supported:
  #   @./CLAUDE.<scope>.md              (relative to file dir)
  #   @~/path/to/file.md                (home-relative)
  #   @../something.md                  (parent-relative)
  #   @/absolute/path.md                (absolute)
  # Match anywhere in the line — Claude Code's import resolution is not
  # restricted to start-of-line (e.g., `- Pointer: @./docs/foo.md`).
  local file_dir
  file_dir=$(dirname "$file")
  # Extract @-import paths. Patterns end at whitespace, end of line, or
  # markdown punctuation. We use rg's PCRE2 mode if available, but BSD grep
  # also handles the basic ERE form. Filter out backtick-wrapped (`@foo`)
  # and handle-style (`@username`) false positives by requiring the path
  # to contain a `.md` extension or start with `./`, `~/`, or `/`.
  rg -oN '@(\./|\~/|/)[^[:space:]\`]+\.md' "$file" 2>/dev/null | \
    sort -u | \
    while read -r import_match; do
    local import_path="${import_match#@}"
    local resolved_path
    # Resolve relative paths. Use string-prefix tests via substring rather
    # than `[[ == pattern ]]` because tilde-expansion semantics in case/
    # `[[ ]]` patterns are inconsistent across bash versions.
    local prefix2="${import_path:0:2}"
    if [[ "$prefix2" == "~/" ]]; then
      resolved_path="${HOME}/${import_path:2}"
    elif [[ "${import_path:0:1}" == "/" ]]; then
      resolved_path="$import_path"
    else
      resolved_path="$file_dir/$import_path"
    fi
    # Canonicalize
    resolved_path=$(readlink -f "$resolved_path" 2>/dev/null || echo "$resolved_path")
    [[ -f "$resolved_path" ]] || continue
    # Avoid infinite loop on circular imports
    if ! grep -qFx "$resolved_path" "$SEEN_IMPORTS" 2>/dev/null; then
      echo "$resolved_path" >> "$SEEN_IMPORTS"
      walk_claude_md_imports "$resolved_path" "claude-md-import"
    fi
  done
}

SEEN_IMPORTS=$(mktemp "$META_CONTEXT_TMPDIR/meta-context-seen.XXXXXX") \
  || { echo "measure-context: mktemp failed in $META_CONTEXT_TMPDIR" >&2; exit 1; }
trap 'rm -f "$SEEN_IMPORTS"' EXIT

# ─── Phase 1: global CLAUDE.md scope tree ──────────────────────────────
if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
  walk_claude_md_imports "$HOME/.claude/CLAUDE.md" "claude-md"
fi

# ─── Phase 2: project CLAUDE.md scope tree ─────────────────────────────
# walk_claude_md_imports follows symlinks transparently — bytes/lines are
# read from the resolved target, and @-import resolution greps through the
# symlink (which dereferences by default on macOS + Linux).
if [[ "$SCOPE" == "all" && -n "$PROJECT_CLAUDE_MD" && -f "$PROJECT_CLAUDE_MD" ]]; then
  walk_claude_md_imports "$PROJECT_CLAUDE_MD" "claude-md"
fi

# ─── Phase 3: MEMORY.md auto-load ──────────────────────────────────────
# Per global CLAUDE.md, auto-memory lives at:
#   ~/.claude/projects/<slug>/memory/MEMORY.md
# The slug is per-project; find candidates by globbing.
#
# IMPORTANT: use `find -L` to follow symlinks. The `memory/` subdir under
# each project is sometimes a SYMLINK pointing into a versioned dotfiles
# tree (so memory persists in the user's dotfiles repo, not the ephemeral
# .claude/projects/ tree). Without -L, find stops at the symlink and never
# discovers MEMORY.md — leading to a measurement gap of ~5-15K tokens per
# active project.
if [[ -d "$HOME/.claude/projects" ]]; then
  while IFS= read -r memfile; do
    [[ -f "$memfile" ]] && emit_record "memory" "$memfile"
  done < <(find -L "$HOME/.claude/projects" -maxdepth 3 -name 'MEMORY.md' 2>/dev/null)
fi

# ─── Phase 4: skill catalog (sum of description: frontmatter) ──────────
# User-level + project-level + plugin skills. We emit ONE aggregate record
# for the catalog rather than per-skill, since the catalog is loaded as a
# single system-reminder block.
SKILL_DIRS=(
  "$HOME/.claude/skills"
  "$HOME/.claude/plugins/marketplaces"
)
# Also include project-local skills if PROJECT_CLAUDE_MD points to a repo
if [[ -n "$PROJECT_CLAUDE_MD" ]]; then
  proj_root=$(dirname "$PROJECT_CLAUDE_MD")
  if [[ -d "$proj_root/.claude/skills-base" ]]; then
    SKILL_DIRS+=("$proj_root/.claude/skills-base")
  fi
  if [[ -d "$proj_root/.claude/skills" ]]; then
    SKILL_DIRS+=("$proj_root/.claude/skills")
  fi
fi

CATALOG_TMP=$(mktemp "$META_CONTEXT_TMPDIR/meta-context-catalog.XXXXXX") \
  || { echo "measure-context: mktemp failed in $META_CONTEXT_TMPDIR" >&2; exit 1; }
trap 'rm -f "$SEEN_IMPORTS" "$CATALOG_TMP"' EXIT

skill_count=0
for sd in "${SKILL_DIRS[@]}"; do
  [[ -d "$sd" ]] || continue
  while IFS= read -r skill_md; do
    # Extract `description:` value from frontmatter — single-line YAML
    desc=$(awk '/^---$/{f++; next} f==1 && /^description:/{sub(/^description: */,""); print; exit}' "$skill_md" 2>/dev/null)
    if [[ -n "$desc" ]]; then
      # Each catalog entry is approximately: "- <name>: <description>\n"
      # We approximate "name" as basename of parent dir.
      name=$(basename "$(dirname "$skill_md")")
      printf -- '- %s: %s\n' "$name" "$desc" >> "$CATALOG_TMP"
      skill_count=$((skill_count + 1))
    fi
  done < <(find "$sd" -name SKILL.md 2>/dev/null)
done

if [[ "$skill_count" -gt 0 ]]; then
  bytes=$(wc -c < "$CATALOG_TMP" | tr -d ' ')
  lines=$(wc -l < "$CATALOG_TMP" | tr -d ' ')
  est_tokens=$((bytes / 4))
  jq -nc \
    --arg category "skill-catalog" \
    --arg path "(aggregated from $skill_count SKILL.md files)" \
    --argjson bytes "$bytes" \
    --argjson lines "$lines" \
    --argjson est_tokens "$est_tokens" \
    --arg note "$skill_count skills" \
    '{category: $category, path: $path, bytes: $bytes, lines: $lines, est_tokens: $est_tokens, note: $note}'
fi

# ─── Phase 5: agent catalog ─────────────────────────────────────────────
AGENT_DIRS=("$HOME/.claude/agents")
if [[ -n "$PROJECT_CLAUDE_MD" ]]; then
  proj_root=$(dirname "$PROJECT_CLAUDE_MD")
  [[ -d "$proj_root/.claude/agents" ]] && AGENT_DIRS+=("$proj_root/.claude/agents")
fi

AGENT_TMP=$(mktemp "$META_CONTEXT_TMPDIR/meta-context-agents.XXXXXX") \
  || { echo "measure-context: mktemp failed in $META_CONTEXT_TMPDIR" >&2; exit 1; }
trap 'rm -f "$SEEN_IMPORTS" "$CATALOG_TMP" "$AGENT_TMP"' EXIT
agent_count=0
for ad in "${AGENT_DIRS[@]}"; do
  [[ -d "$ad" ]] || continue
  while IFS= read -r agent_md; do
    desc=$(awk '/^---$/{f++; next} f==1 && /^description:/{sub(/^description: */,""); print; exit}' "$agent_md" 2>/dev/null)
    if [[ -n "$desc" ]]; then
      name=$(basename "$agent_md" .md)
      printf -- '- %s: %s\n' "$name" "$desc" >> "$AGENT_TMP"
      agent_count=$((agent_count + 1))
    fi
  done < <(find "$ad" -maxdepth 2 -name '*.md' 2>/dev/null)
done

if [[ "$agent_count" -gt 0 ]]; then
  bytes=$(wc -c < "$AGENT_TMP" | tr -d ' ')
  lines=$(wc -l < "$AGENT_TMP" | tr -d ' ')
  est_tokens=$((bytes / 4))
  jq -nc \
    --arg category "agent-catalog" \
    --arg path "(aggregated from $agent_count agent .md files)" \
    --argjson bytes "$bytes" \
    --argjson lines "$lines" \
    --argjson est_tokens "$est_tokens" \
    --arg note "$agent_count agents" \
    '{category: $category, path: $path, bytes: $bytes, lines: $lines, est_tokens: $est_tokens, note: $note}'
fi

# ─── Phase 6: MCP server enumeration ───────────────────────────────────
# MCP server instruction blocks come from server initialization, not from
# static files. We enumerate configured servers across the two known config
# locations (~/.claude.json for user-level, project .mcp.json for
# project-level), and emit one aggregate record with the server count and
# the names. Actual instruction-block bytes are not measurable from outside
# a live session — they're returned by the server at initialize-time and
# injected into context as system reminders.
#
# This record exists so the report shows the number of MCP servers
# contributing instruction blocks, even though the size isn't statically
# computable. Engineer's view: "13 MCP servers configured" is more useful
# than silently omitting the category.
MCP_CONFIGS=(
  "$HOME/.claude.json"
)
if [[ -n "$PROJECT_CLAUDE_MD" ]]; then
  proj_root=$(dirname "$PROJECT_CLAUDE_MD")
  [[ -f "$proj_root/.mcp.json" ]] && MCP_CONFIGS+=("$proj_root/.mcp.json")
fi

mcp_names=()
for cfg in "${MCP_CONFIGS[@]}"; do
  [[ -f "$cfg" ]] || continue
  while IFS= read -r name; do
    [[ -n "$name" ]] && mcp_names+=("$name")
  done < <(jq -r 'if has("mcpServers") then .mcpServers | keys[] else empty end' "$cfg" 2>/dev/null)
done

mcp_count=${#mcp_names[@]}
if [[ "$mcp_count" -gt 0 ]]; then
  # Dedupe (global + project-level may declare the same server).
  mcp_unique=$(printf '%s\n' "${mcp_names[@]}" | sort -u)
  unique_count=$(printf '%s\n' "$mcp_unique" | wc -l | tr -d ' ')
  joined=$(printf '%s\n' "$mcp_unique" | paste -sd ',' -)
  jq -nc \
    --arg category "mcp-instructions" \
    --arg path "(enumerated from ${#MCP_CONFIGS[@]} mcp config file(s))" \
    --argjson bytes 0 \
    --argjson lines 0 \
    --argjson est_tokens 0 \
    --arg note "${unique_count} MCP server(s): ${joined}; instructions injected at runtime — not statically measurable" \
    '{category: $category, path: $path, bytes: $bytes, lines: $lines, est_tokens: $est_tokens, note: $note}'
fi

exit 0
