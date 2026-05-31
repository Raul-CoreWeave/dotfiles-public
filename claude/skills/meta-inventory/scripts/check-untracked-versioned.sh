#!/usr/bin/env bash
# check-untracked-versioned.sh — surface untracked files in known-versioned roots.
#
# Catches the orphan-untracked-file pattern: a file created via a symlink
# (e.g., a new skill / hook / memory entry written through ~/.claude/...
# that resolves through to ~/dotfiles/...) appears live to the running
# system but is invisible to the dotfiles repo's git unless someone
# remembers to `git add` it on the dotfiles side. Same pattern applies to
# any code repo where work-in-progress files can pile up untracked.
#
# Only flags untracked files (`git ls-files --others --exclude-standard`);
# modified files are explicit work-in-progress and not the concern here.
# Honors each repo's .gitignore.
#
# Configuration: edit the ROOTS=(...) array to point at your versioned
# repos, or set META_INVENTORY_PROJECT_ROOT to add one project repo.
#
# Exit codes:
#   0 — no orphans
#   2 — orphans found (for SessionStart-hook use)
#
# Usage: check-untracked-versioned.sh

set -uo pipefail

DOTFILES_ROOT="${META_INVENTORY_DOTFILES_ROOT:-$HOME/dotfiles}"

# Known versioned roots to scan. Add more as the working surface grows.
# Each must be a git repo root (we check for .git/).
ROOTS=(
    "$DOTFILES_ROOT"
)
[[ -n "${META_INVENTORY_PROJECT_ROOT:-}" ]] && ROOTS+=("$META_INVENTORY_PROJECT_ROOT")

total=0
findings=$(mktemp)
trap 'rm -f "$findings"' EXIT

home_tilde() { printf '%s' "${1/#$HOME/\~}"; }

for root in "${ROOTS[@]}"; do
    [[ -d "$root/.git" ]] || continue
    untracked=$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null || true)
    [[ -n "$untracked" ]] || continue
    count=$(printf '%s\n' "$untracked" | wc -l | tr -d ' ')
    total=$((total + count))
    {
        printf '### `%s` — %d untracked file(s)\n\n' "$(home_tilde "$root")" "$count"
        printf '```\n%s\n```\n\n' "$untracked"
    } >> "$findings"
done

printf '## 4. Untracked-in-versioned-roots lint\n\n'
printf 'Scanned %d versioned root(s).\n' "${#ROOTS[@]}"
printf 'Total untracked files: %d\n\n' "$total"

if [[ "$total" -eq 0 ]]; then
    printf 'No orphan-untracked files in versioned roots.\n'
    exit 0
fi

cat "$findings"
exit 2
