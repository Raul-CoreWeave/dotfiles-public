#!/usr/bin/env bash
# install.sh — set up dotfile symlinks. Idempotent; safe to re-run.
#
# Behavior per target:
#   - Already a symlink to the right source → skip silently
#   - Symlink to the wrong source         → re-point
#   - Regular file present                 → back up to <path>.bak.<timestamp>, then symlink
#   - Source missing                       → warn and skip (so partial adoption / incremental
#                                            buildout doesn't hard-fail; remove the module's
#                                            line if you never want it)
#
# Optional private overlay: a non-public machine can drop a private Claude scope
# at claude/CLAUDE.local.md and a settings overlay at claude/settings.private.json
# (both gitignored). When present, the CLAUDE overlay is symlinked alongside the
# global one and the settings overlay is merged into the generated settings via
# claude/scripts/merge-json.py. When absent, only the portable base installs.
#
# Add a new module by appending another `link` call below.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (try -h)" >&2; exit 2 ;;
  esac
done

# --- Helpers --------------------------------------------------------------
# Define link() only if not already defined — lets bootstrap.sh --dry-run
# override it as a checker before sourcing this file. Without the guard,
# sourcing would clobber the override and silently fall back to the real
# link creator.
if ! declare -f link >/dev/null 2>&1; then
  link() {
    local src="$1" dst="$2"
    [[ -e "$src" ]] || { echo "skip   $dst (source missing: $src)" >&2; return 0; }
    if [[ -L "$dst" ]]; then
      [[ "$(readlink "$dst")" == "$src" ]] && { echo "ok     $dst"; return 0; }
      echo "relink $dst"
      ln -sfn "$src" "$dst"
      return 0
    fi
    if [[ -e "$dst" ]]; then
      local bak; bak="${dst}.bak.$(date +%Y%m%d-%H%M%S)"
      echo "backup $dst → $bak"
      mv "$dst" "$bak"
    fi
    echo "link   $dst → $src"
    ln -s "$src" "$dst"
  }
fi

# ensure_dir — convert a stale dir-symlink to a real directory before
# per-file symlinking inside. Used when migrating a path from whole-dir
# symlink to per-file symlinks (e.g., commands/, hooks/).
ensure_dir() {
  local d="$1"
  if [[ -L "$d" ]]; then
    echo "convert-to-dir $d (was symlink → $(readlink "$d"))"
    rm "$d"
  fi
  mkdir -p "$d"
}

# merge_or_copy_json — generate a merged JSON file under _generated/.
# If a private overlay exists: run merge-json.py (array-aware merge for hooks +
# sandbox domains, object merge for plugins). Otherwise: copy base verbatim.
# If base is missing entirely: warn and skip. Output is written under
# $DOTFILES_DIR/claude/_generated/ which is gitignored.
merge_or_copy_json() {
  local base="$1" overlay="$2" output="$3"
  [[ -f "$base" ]] || { echo "skip   $output (base missing: $base)" >&2; return 0; }
  mkdir -p "$(dirname "$output")"
  if [[ -f "$overlay" ]]; then
    python3 "$DOTFILES_DIR/claude/scripts/merge-json.py" "$base" "$overlay" "$output"
  else
    cp "$base" "$output"
    echo "copy   $output ← $base (no overlay applied)"
  fi
}

# --- Module: claude -------------------------------------------------------
mkdir -p "$HOME/.claude" "$HOME/.claude/plugins"

# Global CLAUDE.md (portable) + optional private overlay (gitignored, present
# only on machines that have one).
link "$DOTFILES_DIR/claude/CLAUDE.md"            "$HOME/.claude/CLAUDE.md"
link "$DOTFILES_DIR/claude/CLAUDE.local.md"      "$HOME/.claude/CLAUDE.local.md"

# Settings: portable base + optional private overlay merged into
# _generated/settings.json at install time, then symlinked.
merge_or_copy_json \
  "$DOTFILES_DIR/claude/settings.json" \
  "$DOTFILES_DIR/claude/settings.private.json" \
  "$DOTFILES_DIR/claude/_generated/settings.json"
link "$DOTFILES_DIR/claude/_generated/settings.json"  "$HOME/.claude/settings.json"

# Skills + references (whole-dir symlinks).
link "$DOTFILES_DIR/claude/skills"               "$HOME/.claude/skills"
link "$DOTFILES_DIR/claude/references"           "$HOME/.claude/references"

# Commands — per-file.
ensure_dir "$HOME/.claude/commands"
link "$DOTFILES_DIR/claude/commands/session-id.md"    "$HOME/.claude/commands/session-id.md"
link "$DOTFILES_DIR/claude/commands/todo.md"          "$HOME/.claude/commands/todo.md"
link "$DOTFILES_DIR/claude/commands/util.md"          "$HOME/.claude/commands/util.md"
link "$DOTFILES_DIR/claude/commands/dev.md"           "$HOME/.claude/commands/dev.md"
ensure_dir "$HOME/.claude/commands/scripts"
link "$DOTFILES_DIR/claude/commands/scripts/todo.sh"  "$HOME/.claude/commands/scripts/todo.sh"

# Hooks — per-file.
ensure_dir "$HOME/.claude/hooks"
link "$DOTFILES_DIR/claude/hooks/check-skill-doc-sync.py"             "$HOME/.claude/hooks/check-skill-doc-sync.py"
link "$DOTFILES_DIR/claude/hooks/sessionstart-dangling-refs.sh"       "$HOME/.claude/hooks/sessionstart-dangling-refs.sh"
link "$DOTFILES_DIR/claude/hooks/sessionstart-untracked-versioned.sh" "$HOME/.claude/hooks/sessionstart-untracked-versioned.sh"
link "$DOTFILES_DIR/claude/hooks/log-bash-command.py"                 "$HOME/.claude/hooks/log-bash-command.py"
link "$DOTFILES_DIR/claude/hooks/warn-protected-branch-commit.py"     "$HOME/.claude/hooks/warn-protected-branch-commit.py"

# Plugins: portable base + optional private overlay merged, then symlinked.
# NOTE: known_marketplaces.json is NOT tracked — Claude Code overwrites it via
# atomic rename on marketplace refresh, which would break a symlink. Bootstrap a
# fresh machine with `claude plugin marketplace add ...` once after install.
merge_or_copy_json \
  "$DOTFILES_DIR/claude/plugins/installed_plugins.json" \
  "$DOTFILES_DIR/claude/plugins/installed_plugins.private.json" \
  "$DOTFILES_DIR/claude/_generated/installed_plugins.json"
link "$DOTFILES_DIR/claude/_generated/installed_plugins.json"  "$HOME/.claude/plugins/installed_plugins.json"

# Per-project memory. Source lives at a portable name in dotfiles
# (claude/memory/<project>/); the destination is the path-slug-derived directory
# Claude Code creates at ~/.claude/projects/<slug>/memory/. The slug is derived
# from the absolute project path (every '/' → '-', leading slash included), so
# it differs across machines — install.sh composes it here.
link_memory() {
  local memory_name="$1" project_path="$2"
  local slug; slug=$(printf '%s' "$project_path" | sed 's|/|-|g')
  local src="$DOTFILES_DIR/claude/memory/$memory_name"
  [[ -d "$src" ]] || { echo "skip   memory $memory_name (source missing: $src)" >&2; return 0; }
  local proj_dir="$HOME/.claude/projects/$slug"
  mkdir -p "$proj_dir"
  link "$src" "$proj_dir/memory"
}

link_memory "home" "$HOME"

# --- Module: shell --------------------------------------------------------
# (zshrc is handled by bootstrap.sh — it's a template instantiated per-machine,
# not a symlink target.)
link "$DOTFILES_DIR/shell/gitconfig"   "$HOME/.gitconfig"
link "$DOTFILES_DIR/shell/zprofile"    "$HOME/.zprofile"
mkdir -p "$HOME/.ssh"
link "$DOTFILES_DIR/shell/ssh-config"  "$HOME/.ssh/config"

# --- Module: config -------------------------------------------------------
mkdir -p "$HOME/.config" "$HOME/.config/atuin"
link "$DOTFILES_DIR/config/starship.toml"      "$HOME/.config/starship.toml"
link "$DOTFILES_DIR/config/atuin-config.toml"  "$HOME/.config/atuin/config.toml"

# --- Module: hammerspoon --------------------------------------------------
# macOS-only; symlink is inert without Hammerspoon.app installed.
mkdir -p "$HOME/.hammerspoon"
link "$DOTFILES_DIR/hammerspoon/init.lua"      "$HOME/.hammerspoon/init.lua"

echo ""
echo "Done."
