#!/usr/bin/env bash
# bootstrap.sh — full new-machine setup. Wraps install.sh plus the
# non-symlink steps (brew bundle, repos clone, pipx tools).
#
# Run on a fresh machine AFTER:
#   1. Xcode CLT installed (`xcode-select --install`)   [macOS]
#   2. Homebrew installed (https://brew.sh)
#   3. `gh auth login` completed (interactive — opens browser), if cloning
#      private repos listed in repos.txt
#
# This script will NOT do steps 1-3. Run them first; this is the personal-layer step.
#
# install.sh handles all symlinkable configs. Edit there to add new symlink targets.
# Edit here only for actions that don't fit the symlink model (install commands,
# repo clones, package installs).
#
# Flags:
#   --dry-run   No installs. Verify every symlink install.sh would create
#               resolves correctly (ok / wrong-target / not-symlink /
#               missing-src / missing-dst), and surface entries under
#               ~/.claude/ that are neither tracked by install.sh nor
#               matched by ~/dotfiles/.gitignore (drift candidates).
#               Exit non-zero on any anomaly so a wrapping cron / launchd
#               job can pipe to notification.
#   -h, --help  Print this and exit.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf '[bootstrap] unknown arg: %s (try --help)\n' "$arg" >&2; exit 1 ;;
  esac
done

log()   { printf '[bootstrap] %s\n' "$*"; }
warn()  { printf '[bootstrap] WARN: %s\n' "$*" >&2; }
fatal() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$DOTFILES" ]] || fatal "dotfiles dir not found at $DOTFILES (set DOTFILES env var if elsewhere)"

# ---------------------------------------------------------------------------
# Dry-run / drift-detection mode
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  declare -a EXPECTED_DESTS=()
  declare -a ANOMALIES=()

  # Override install.sh's link() to be a checker instead of a creator.
  link() {
    local src="$1" dst="$2"
    EXPECTED_DESTS+=("$dst")
    if [[ ! -e "$src" ]]; then
      ANOMALIES+=("missing-src: $src (declared by install.sh as source for $dst)")
      printf 'MISSING-SRC   %s\n' "$src"
      return 0
    fi
    if [[ -L "$dst" ]]; then
      local actual; actual=$(readlink "$dst")
      if [[ "$actual" == "$src" ]]; then
        printf 'ok            %s\n' "$dst"
      else
        ANOMALIES+=("wrong-target: $dst -> $actual (expected $src)")
        printf 'WRONG-TARGET  %s -> %s (expected %s)\n' "$dst" "$actual" "$src"
      fi
    elif [[ -e "$dst" ]]; then
      ANOMALIES+=("not-symlink: $dst (real file/dir; install.sh would back up + symlink)")
      printf 'NOT-SYMLINK   %s\n' "$dst"
    else
      ANOMALIES+=("missing-dst: $dst (install.sh has not run for this entry)")
      printf 'MISSING-DST   %s\n' "$dst"
    fi
  }

  log "Checking install.sh-declared symlinks..."
  echo
  # shellcheck disable=SC1091  # sourcing install.sh intentionally; link() is overridden above.
  # Plain source — must run in the current shell so EXPECTED_DESTS populates here.
  source "$DOTFILES/install.sh"

  echo
  log "Checking for drift in ~/.claude/ — entries neither tracked nor gitignored..."
  echo

  is_tracked() {
    local p="$1" d
    for d in "${EXPECTED_DESTS[@]}"; do
      [[ "$p" == "$d" ]] && return 0
    done
    return 1
  }

  is_ignored() {
    local p="$1"
    local rel="claude/${p#$HOME/.claude/}"
    [[ -d "$p" ]] && rel="$rel/"
    (cd "$DOTFILES" && git check-ignore -q "$rel" 2>/dev/null)
  }

  classify() {
    local p="$1"
    if is_tracked "$p" || is_ignored "$p"; then
      return
    fi
    ANOMALIES+=("drift: $p (consider tracking via install.sh or adding to .gitignore)")
    printf 'DRIFT         %s\n' "$p"
  }

  CONTAINERS=("plugins" "projects")
  while IFS= read -r path; do
    base=$(basename "$path")
    skip=0
    for c in "${CONTAINERS[@]}"; do
      [[ "$base" == "$c" ]] && { skip=1; break; }
    done
    [[ "$skip" == "1" ]] && continue
    classify "$path"
  done < <(find "$HOME/.claude" -maxdepth 1 -mindepth 1 2>/dev/null)

  while IFS= read -r path; do
    classify "$path"
  done < <(find "$HOME/.claude/plugins" -maxdepth 1 -mindepth 1 2>/dev/null)

  while IFS= read -r path; do
    classify "$path"
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -mindepth 2 -name memory 2>/dev/null)

  echo
  log "Summary: ${#ANOMALIES[@]} anomalies"
  if [[ "${#ANOMALIES[@]}" -gt 0 ]]; then
    echo
    log "Details:"
    printf '  - %s\n' "${ANOMALIES[@]}"
    exit 1
  fi
  log "Clean. Every install.sh symlink resolves correctly, no drift in ~/.claude/."
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Symlink all the things — delegate to install.sh
# ---------------------------------------------------------------------------
log "running install.sh for symlinks"
"$DOTFILES/install.sh"

# ---------------------------------------------------------------------------
# 2. Personal Brewfile
# ---------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
    log "installing personal Brew formulae"
    brew bundle install --file="$DOTFILES/Brewfile.personal"
else
    warn "brew not found — install Homebrew first, then re-run bootstrap"
fi

# ---------------------------------------------------------------------------
# 3. zshrc — copy from template only if no live ~/.zshrc exists.
#    (zshrc is NOT symlinked in install.sh because the template is meant as a
#    starting point for per-machine instantiation, not the live config.)
# ---------------------------------------------------------------------------
if [[ -f "$DOTFILES/shell/zshrc.template" ]]; then
    if [[ ! -f "$HOME/.zshrc" ]]; then
        log "copying zshrc.template -> $HOME/.zshrc (fresh install)"
        cp "$DOTFILES/shell/zshrc.template" "$HOME/.zshrc"
    else
        log "$HOME/.zshrc already exists; not overwriting (compare with shell/zshrc.template)"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Clone repos listed in repos.txt (tab-separated: <relpath>\t<url>).
#    Cloned under $HOME/<relpath>. No repos.txt → step is a no-op.
# ---------------------------------------------------------------------------
if [[ -f "$DOTFILES/repos.txt" ]]; then
    log "cloning repos (skipping any that already exist)"
    while IFS=$'\t' read -r relpath url; do
        [[ -z "${relpath:-}" || "${relpath:0:1}" == "#" ]] && continue
        local_path="$HOME/$relpath"
        if [[ -d "$local_path/.git" ]]; then
            log "  exists: $relpath"
        else
            mkdir -p "$(dirname "$local_path")"
            git clone "$url" "$local_path" || warn "  clone failed: $url (may need gh auth)"
        fi
    done < "$DOTFILES/repos.txt"
fi

# ---------------------------------------------------------------------------
# 5. pipx tools
# ---------------------------------------------------------------------------
if command -v pipx >/dev/null 2>&1 && [[ -f "$DOTFILES/tools/pipx.txt" ]]; then
    log "installing pipx tools"
    while IFS=$'\t' read -r name source; do
        [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue
        if pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$name"; then
            log "  pipx already has: $name"
        else
            expanded_source="${source//\$HOME/$HOME}"
            pipx install "$expanded_source" || warn "  pipx install failed: $name from $expanded_source"
        fi
    done < "$DOTFILES/tools/pipx.txt"
fi

# ---------------------------------------------------------------------------
# 6. Reminders
# ---------------------------------------------------------------------------
log "done. Outstanding manual steps:"
log "  - 'gh auth login -h github.com' (if cloning private repos)"
log "  - wire up your secret manager and load tokens at shell startup"
log "  - open a fresh shell and verify your environment"
