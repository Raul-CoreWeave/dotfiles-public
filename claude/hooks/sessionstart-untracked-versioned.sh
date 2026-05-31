#!/usr/bin/env bash
# sessionstart-untracked-versioned.sh — surface orphan-untracked files at session start.
#
# Companion to sessionstart-dangling-refs.sh. Fires the untracked-versioned
# lint and emits a one-line summary when orphans exist. Silent when clean.
# Silent when the lint fails (don't disrupt session startup on a script error).
#
# Wired in: ~/.claude/settings.json → hooks.SessionStart[]
# Companion: ~/.claude/skills/meta-inventory/scripts/check-untracked-versioned.sh
# Details : run `/meta-inventory` (or `git -C <root> status` per the rule in
#           global CLAUDE.md § "No orphan-untracked files in versioned roots").

set -uo pipefail

LINT="$HOME/.claude/skills/meta-inventory/scripts/check-untracked-versioned.sh"

[[ -f "$LINT" ]] || exit 0

output=$(bash "$LINT" 2>/dev/null) || true

total=$(printf '%s\n' "$output" | grep -E '^Total untracked files:' | awk '{print $4}')
roots_scanned=$(printf '%s\n' "$output" | grep -E '^Scanned ' | awk '{print $2}')

if [[ -z "${total:-}" ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
    exit 0
fi

[[ "$total" -eq 0 ]] && exit 0

echo "[untracked] ${total} orphan file(s) across ${roots_scanned} versioned root(s) — run /meta-inventory for details"
