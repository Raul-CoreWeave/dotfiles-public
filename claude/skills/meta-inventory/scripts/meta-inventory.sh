#!/usr/bin/env bash
# meta-inventory.sh — deterministic data gathering for the /meta-inventory skill.
#
# Emits markdown on stdout with two top-level sections:
#   § 1. Primitives currently installed
#   § 2. Persistence roots
#
# The LLM (calling skill prompt) adds § 3. Gap analysis based on this output.
#
# Configuration: set PROJECT_ROOT to the repo you work in (the one whose
# .claude/ holds project-level skills/agents/hooks). Leave empty to skip the
# project-level section. DOTFILES_ROOT is where your versioned CLAUDE.md
# sources live.
#
# Usage: meta-inventory.sh [--no-color]

set -euo pipefail

# ---------- config (edit these for your setup) ----------
PROJECT_ROOT="${META_INVENTORY_PROJECT_ROOT:-}"     # e.g. "$HOME/code/myrepo"; empty to skip
DOTFILES_ROOT="${META_INVENTORY_DOTFILES_ROOT:-$HOME/dotfiles}"

# ---------- helpers ----------

count_files() {
    # count_files <dir> [<pattern>] — follows symlinks at the start path
    local dir="$1" pattern="${2:-*}"
    [[ -e "$dir" ]] || { echo 0; return; }
    find -L "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

count_subdirs() {
    local dir="$1"
    [[ -e "$dir" ]] || { echo 0; return; }
    find -L "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

list_subdirs() {
    # list_subdirs <dir> — emit bare subdirectory names, comma-separated
    local dir="$1"
    [[ -e "$dir" ]] || return
    find -L "$dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null \
        | sort | paste -sd, - | sed 's/,/, /g'
}

file_mtime() {
    local file="$1"
    [[ -e "$file" ]] || { echo "n/a"; return; }
    # macOS BSD stat; fall back to GNU stat form
    stat -f '%Sm' -t '%Y-%m-%d' "$file" 2>/dev/null || stat -c '%y' "$file" 2>/dev/null | cut -d' ' -f1 || echo "n/a"
}

file_size_bytes() {
    local file="$1"
    [[ -f "$file" ]] || { echo 0; return; }
    stat -f '%z' "$file" 2>/dev/null || stat -c '%s' "$file" 2>/dev/null || echo 0
}

human_size() {
    local b="$1"
    if [[ "$b" -lt 1024 ]]; then
        echo "${b}B"
    elif [[ "$b" -lt 1048576 ]]; then
        awk -v b="$b" 'BEGIN { printf "%.1fK", b/1024 }'
    else
        awk -v b="$b" 'BEGIN { printf "%.1fM", b/1048576 }'
    fi
}

# ---------- § 1. Primitives ----------

emit_primitives() {
    printf '## 1. Primitives currently installed\n\n'

    # --- User-level ---
    printf '### User-level (`~/.claude/`)\n\n'

    local user_skills user_cmds user_agents user_mcp
    user_skills=$(count_subdirs "$HOME/.claude/skills")
    user_cmds=$(count_files "$HOME/.claude/commands" "*.md")
    user_agents=$(count_files "$HOME/.claude/agents" "*.md")
    user_mcp="—"
    [[ -f "$HOME/.claude/.mcp.json" ]] && user_mcp="present"

    printf '| Kind | Count | Items |\n|---|---|---|\n'
    printf '| Skills | %s | %s |\n' "$user_skills" "$(list_subdirs "$HOME/.claude/skills")"
    if [[ "$user_cmds" -gt 0 ]]; then
        local cmds
        cmds=$(find -L "$HOME/.claude/commands" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | paste -sd, - | sed 's/,/, /g')
        printf '| Slash commands | %s | %s |\n' "$user_cmds" "$cmds"
    else
        printf '| Slash commands | 0 | — |\n'
    fi
    if [[ "$user_agents" -gt 0 ]]; then
        local agents
        agents=$(find -L "$HOME/.claude/agents" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | paste -sd, - | sed 's/,/, /g')
        printf '| Agents | %s | %s |\n' "$user_agents" "$agents"
    else
        printf '| Agents | 0 | — |\n'
    fi
    printf '| User-level MCPs | %s | %s |\n' "$user_mcp" "$([[ -f $HOME/.claude/.mcp.json ]] && echo "$HOME/.claude/.mcp.json" || echo "no ~/.claude/.mcp.json")"
    printf '\n'

    # --- User-level hooks ---
    printf '### Hooks — user-level (`~/.claude/settings.json`)\n\n'
    emit_hooks_table "$HOME/.claude/settings.json"
    printf '\n'

    # --- Project-level ---
    local proj="$PROJECT_ROOT"
    if [[ -n "$proj" && -d "$proj/.claude" ]]; then
        printf '### Project-level — `%s/.claude/`\n\n' "${proj/$HOME/\~}"

        # Skills — `skills/` may be a symlink to an active-mode skill dir.
        local active_skills active_skills_target
        active_skills=$(count_subdirs "$proj/.claude/skills")
        if [[ -L "$proj/.claude/skills" ]]; then
            active_skills_target=$(readlink "$proj/.claude/skills")
        else
            active_skills_target="(not a symlink)"
        fi

        local proj_cmds proj_agents
        proj_cmds=$(count_files "$proj/.claude/commands" "*.md")
        proj_agents=$(count_files "$proj/.claude/agents" "*.md")

        # MCPs: .mcp.json
        local proj_mcp_count=0
        if [[ -f "$proj/.mcp.json" ]]; then
            proj_mcp_count=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("mcpServers", {})))' "$proj/.mcp.json" 2>/dev/null || echo "?")
        fi

        # Active mode (via CLAUDE.md symlink, if used)
        local active_mode="—"
        if [[ -L "$proj/CLAUDE.md" ]]; then
            active_mode=$(readlink "$proj/CLAUDE.md" | sed -E 's/CLAUDE\.(.*)\.md/\1/')
        fi

        printf '| Kind | Count | Notes |\n|---|---|---|\n'
        printf '| Active mode | — | `%s` (via `CLAUDE.md` symlink, if used) |\n' "$active_mode"
        printf '| Skills (active scope) | %s | `skills/` → `%s` |\n' "$active_skills" "$active_skills_target"
        if [[ "$proj_cmds" -gt 0 ]]; then
            local pcmds
            pcmds=$(find -L "$proj/.claude/commands" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | paste -sd, - | sed 's/,/, /g')
            printf '| Slash commands | %s | %s |\n' "$proj_cmds" "$pcmds"
        else
            printf '| Slash commands | 0 | — |\n'
        fi
        if [[ "$proj_agents" -gt 0 ]]; then
            local pagents
            pagents=$(find -L "$proj/.claude/agents" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null | sort | paste -sd, - | sed 's/,/, /g')
            printf '| Agents | %s | %s |\n' "$proj_agents" "$pagents"
        else
            printf '| Agents | 0 | — |\n'
        fi
        printf '| MCPs | %s | declared in `.mcp.json` |\n' "$proj_mcp_count"
        printf '\n'

        # --- Project hooks ---
        printf '### Hooks — project-level (`%s/.claude/settings.json`)\n\n' "${proj/$HOME/\~}"
        emit_hooks_table "$proj/.claude/settings.json"
        printf '\n'

        # --- Project MCPs detail ---
        if [[ -f "$proj/.mcp.json" ]]; then
            printf '### MCPs declared in `%s/.mcp.json`\n\n' "${proj/$HOME/\~}"
            python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
for name in sorted(servers.keys()):
    print(f"- `{name}`")
' "$proj/.mcp.json"
            printf '\n'
        fi
    fi

    # --- Plugins ---
    emit_plugins

    # --- Claude Code built-in slash commands (from /util) ---
    emit_builtins_from_util
}

# emit_builtins_from_util — render the body of ~/.claude/commands/util.md as
# a § 1 sub-section. /util is a hand-maintained snapshot of the harness's
# `/help` output (the built-in slash commands like /clear /compact /sandbox
# that live in the Claude Code binary, NOT on the filesystem). meta-inventory
# is otherwise filesystem-only, so without this section an "audit" reading
# of the inventory would miss the built-in commands the engineer actually
# uses. The /util file is the right source — it's already the canonical
# refresh-on-paste artifact for tracking harness-version drift. Skipped
# silently if you don't maintain a /util snapshot.
emit_builtins_from_util() {
    local util_md="$HOME/.claude/commands/util.md"
    [[ -f "$util_md" ]] || return 0

    # Extract the first code-fenced block (the actual snapshot body, skipping
    # frontmatter + the print-verbatim instruction line).
    local body
    body=$(awk '/^```/{f=!f; if(f==0) exit; next} f' "$util_md")
    [[ -z "$body" ]] && return 0

    # Snapshot date from the frontmatter description line, if present.
    local snapshot_date
    snapshot_date=$(grep -oE 'output [0-9]{4}-[0-9]{2}-[0-9]{2}' "$util_md" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

    if [[ -n "$snapshot_date" ]]; then
        printf '### Claude Code built-in slash commands (from `/util` snapshot, %s)\n\n' "$snapshot_date"
    else
        printf '### Claude Code built-in slash commands (from `/util` snapshot)\n\n'
    fi
    printf '_(Built-ins live in the Claude Code harness binary, not on the filesystem. Maintained at `~/.claude/commands/util.md`; refresh by pasting current `/help` output when a new harness version ships. Verbatim below.)_\n\n'
    printf '```\n%s\n```\n\n' "$body"
}

# emit_hooks_table <settings.json> — markdown table of installed hooks
emit_hooks_table() {
    local settings="$1"
    [[ -f "$settings" ]] || { printf '_(no settings.json at this scope)_\n'; return; }
    python3 - "$settings" <<'PYEOF'
import json, sys, os, re

path = sys.argv[1]
try:
    d = json.load(open(path))
except Exception as e:
    print(f"_(failed to parse {path}: {e})_")
    sys.exit(0)

hooks = d.get("hooks", {})
if not hooks:
    print("_(no hooks configured)_")
    sys.exit(0)

def extract_handler(cmd):
    if not cmd:
        return "(inline)"
    # Hook commands often look like: cd /path && python3 hook.py [args]
    # or: bash /path/to/hook.sh [args]
    # Find the first token ending in .py / .sh / .bash / .zsh
    m = re.search(r'(\S+\.(?:py|sh|bash|zsh))', cmd)
    if m:
        return os.path.basename(m.group(1))
    # Fallback: first token
    return os.path.basename(re.split(r'\s+', cmd.strip())[0])

print("| Event | Matcher | Handler |")
print("|---|---|---|")
for event, entries in hooks.items():
    if not isinstance(entries, list):
        continue
    for entry in entries:
        matcher = entry.get("matcher", "*")
        # Truncate very long matcher regexes for readability
        matcher_display = matcher if len(matcher) <= 60 else matcher[:57] + "..."
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            handler = extract_handler(cmd)
            print(f"| {event} | `{matcher_display}` | `{handler}` |")
PYEOF
}

# emit_plugins — markdown summary of installed plugins
emit_plugins() {
    local manifest="$HOME/.claude/plugins/installed_plugins.json"
    if [[ ! -f "$manifest" ]]; then
        printf '### Plugins\n\n_(no installed_plugins.json found)_\n\n'
        return
    fi

    printf '### Plugins\n\n'
    python3 - "$manifest" <<'PYEOF'
import json, sys, os, glob
from collections import defaultdict

m = json.load(open(sys.argv[1]))
plugins = m.get("plugins", {})

by_marketplace = defaultdict(list)
for full_name in sorted(plugins.keys()):
    if "@" in full_name:
        name, marketplace = full_name.split("@", 1)
    else:
        name, marketplace = full_name, "(no marketplace)"
    entries = plugins[full_name]
    # one entry per scope; show first
    entry = entries[0] if entries else {}
    version = entry.get("version", "?")
    install_path = entry.get("installPath", "")
    # count skills bundled in the plugin
    skill_count = 0
    if install_path and os.path.isdir(install_path):
        skill_count = len(glob.glob(os.path.join(install_path, "skills", "*", "SKILL.md")))
    by_marketplace[marketplace].append((name, version, skill_count))

print(f"Total: {len(plugins)} plugin(s) across {len(by_marketplace)} marketplace(s).")
print()
for mp in sorted(by_marketplace.keys()):
    print(f"**{mp}**")
    print()
    print("| Plugin | Version | Bundled skills |")
    print("|---|---|---|")
    for name, version, skill_count in sorted(by_marketplace[mp]):
        print(f"| `{name}` | {version} | {skill_count} |")
    print()
PYEOF
}

# ---------- § 2. Persistence roots ----------

emit_persistence() {
    printf '## 2. Persistence roots\n\n'

    # --- CLAUDE.md scopes ---
    printf '### CLAUDE.md scopes\n\n'
    printf '| Scope | Path | Size | Last modified |\n|---|---|---|---|\n'
    local f
    local scopes=(
        "$HOME/.claude/CLAUDE.md"
        "$DOTFILES_ROOT/claude/CLAUDE.md"
    )
    # Add project + any mode files if a project root is configured.
    if [[ -n "$PROJECT_ROOT" ]]; then
        scopes+=("$PROJECT_ROOT/CLAUDE.md")
        local mf
        for mf in "$PROJECT_ROOT"/CLAUDE.*.md; do
            [[ -e "$mf" ]] && scopes+=("$mf")
        done
    fi
    for f in "${scopes[@]}"; do
        if [[ -e "$f" ]]; then
            local label
            label=$(basename "$f")
            # Resolve symlinks for size measurement
            local target="$f"
            [[ -L "$f" ]] && target=$(readlink "$f")
            local size human mtime
            size=$(file_size_bytes "$target")
            human=$(human_size "$size")
            mtime=$(file_mtime "$target")
            local marker=""
            [[ -L "$f" ]] && marker=" → $(readlink "$f")"
            printf '| `%s` | `%s%s` | %s | %s |\n' "$label" "${f/$HOME/\~}" "$marker" "$human" "$mtime"
        fi
    done
    printf '\n'

    # --- Memory directories ---
    printf '### Memory directories (`~/.claude/projects/<slug>/memory/`)\n\n'
    printf '| Project slug | File count | Last activity |\n|---|---|---|\n'
    local memdir
    for memdir in "$HOME"/.claude/projects/*/memory; do
        [[ -e "$memdir" ]] || continue
        local slug
        slug=$(basename "$(dirname "$memdir")")
        local count
        count=$(count_files "$memdir" "*.md")
        local latest
        latest=$(find -L "$memdir" -maxdepth 1 -type f -name '*.md' -exec stat -f '%m %N' {} \; 2>/dev/null \
            | sort -rn | head -1 | awk '{print $1}')
        local latest_human="n/a"
        if [[ -n "$latest" ]]; then
            latest_human=$(date -r "$latest" '+%Y-%m-%d' 2>/dev/null || echo "n/a")
        fi
        printf '| `%s` | %s | %s |\n' "$slug" "$count" "$latest_human"
    done
    printf '\n'

    # --- KB domains (project docs/knowledge, if present) ---
    if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT/docs/knowledge" ]]; then
        local kbdir="$PROJECT_ROOT/docs/knowledge"
        printf '### KB domains (`%s/`)\n\n' "${kbdir/$HOME/\~}"
        printf '| Domain | File count |\n|---|---|\n'
        local d
        for d in "$kbdir"/*/; do
            [[ -d "$d" ]] || continue
            local dom count
            dom=$(basename "$d")
            count=$(find "$d" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
            printf '| `%s` | %s |\n' "$dom" "$count"
        done
        printf '\n'
    fi

    # --- Todos ---
    printf '### Todos (`~/.claude/todos/`)\n\n'
    if [[ -d "$HOME/.claude/todos" ]]; then
        printf '| Category | Open | Closed |\n|---|---|---|\n'
        local t
        for t in "$HOME"/.claude/todos/*.md; do
            [[ -f "$t" ]] || continue
            local cat open closed
            cat=$(basename "$t" .md)
            open=$(awk '/^## Open/,/^## Closed/' "$t" | grep -cE '^- \[ \]' || echo 0)
            closed=$(awk '/^## Closed/,EOF' "$t" | grep -cE '^- \[x\]' || echo 0)
            printf '| `%s` | %s | %s |\n' "$cat" "$open" "$closed"
        done
    else
        printf '_(no `~/.claude/todos/` directory)_\n'
    fi
    printf '\n'

    # --- Watchlists ---
    printf '### Watchlists (`~/.claude/watchlists/`)\n\n'
    if [[ -d "$HOME/.claude/watchlists" ]]; then
        printf '| Name | Last modified |\n|---|---|\n'
        local w
        for w in "$HOME"/.claude/watchlists/*.md; do
            [[ -f "$w" ]] || continue
            local name mtime
            name=$(basename "$w" .md)
            mtime=$(file_mtime "$w")
            printf '| `%s` | %s |\n' "$name" "$mtime"
        done
    else
        printf '_(no `~/.claude/watchlists/` directory)_\n'
    fi
    printf '\n'

    # --- References catalog ---
    local ref="$DOTFILES_ROOT/claude/references"
    if [[ -d "$ref" ]]; then
        printf '### Reference catalog (`%s/`)\n\n' "${ref/$HOME/\~}"
        printf 'Catalog files cited from CLAUDE.md scopes (loaded on-demand, not auto-loaded):\n\n'
        local r
        for r in "$ref"/*.md; do
            [[ -f "$r" ]] || continue
            local name mtime
            name=$(basename "$r")
            mtime=$(file_mtime "$r")
            printf -- '- `%s` (last modified %s)\n' "$name" "$mtime"
        done
        printf '\n'
    fi
}

# ---------- main ----------

printf '<!-- Generated by ~/.claude/skills/meta-inventory/scripts/meta-inventory.sh -->\n'
printf '<!-- Run timestamp: %s -->\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

emit_primitives
emit_persistence
