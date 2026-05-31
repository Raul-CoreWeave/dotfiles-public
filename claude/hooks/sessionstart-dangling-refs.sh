#!/usr/bin/env bash
# sessionstart-dangling-refs.sh — surface persistence-graph health at session start.
#
# Fires the dangling-refs lint, emits a one-line summary if findings exist.
# Silent when the persistence graph is clean. Silent when the lint fails
# (don't disrupt session startup on a script error).
#
# Wired in: ~/.claude/settings.json → hooks.SessionStart[]
# Companion: ~/.claude/skills/meta-inventory/scripts/check-dangling-refs.sh
# Details : run `/meta-inventory` to regenerate the full inventory + lint report.

set -uo pipefail

LINT="$HOME/.claude/skills/meta-inventory/scripts/check-dangling-refs.sh"

# Bail silently if the lint script is missing — don't break startup.
[[ -f "$LINT" ]] || exit 0

# Run the lint, capture totals. Take stdout only; stderr suppressed.
output=$(bash "$LINT" 2>/dev/null) || true

total=$(printf '%s\n' "$output" | grep -E '^Total dangling refs:' | awk '{print $4}')
files_scanned=$(printf '%s\n' "$output" | grep -E '^Scanned ' | awk '{print $2}')

if [[ -z "${total:-}" ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
    exit 0
fi

# 0 findings — stay quiet.
[[ "$total" -eq 0 ]] && exit 0

echo "[dangling-refs] ${total} ref(s) flagged across ${files_scanned} files in the persistence graph — run /meta-inventory for details"
