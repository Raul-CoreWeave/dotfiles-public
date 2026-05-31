#!/usr/bin/env bash
# draft-pr-body.sh — emit raw material for the LLM to compose a PR body in repo voice.
#
# Used by /dev-gh-pr Phase 5. Does NOT compose the body itself — the LLM does that,
# using this output + reference/pr-template.md + the engineer's prior PR style.
#
# Inputs: BASE_SHA env var (locked from preflight). HEAD is implicit.
#
# Output: a single JSON envelope containing:
#   - commit_log:   list of commits since BASE_SHA (subject lines, oldest first)
#   - file_changes: git diff --stat output, line by line
#   - voice_sample: last 20 commit subjects on this branch's history (for style inference)
#   - recent_prs:   gh-derived recent merged PRs from origin (titles only, for title inference)
#
# Exit codes:
#   0 — JSON emitted
#   2 — BASE_SHA missing or invalid
#   3 — no commits ahead of BASE_SHA (nothing to draft)

set -euo pipefail

err() { echo "draft-pr-body: $*" >&2; }

if [[ -z "${BASE_SHA:-}" ]]; then
    err "BASE_SHA env var required"
    exit 2
fi

if ! git cat-file -e "$BASE_SHA" 2>/dev/null; then
    err "BASE_SHA $BASE_SHA not found in repo"
    exit 2
fi

ahead_count=$(git rev-list --count "${BASE_SHA}..HEAD")
if [[ "$ahead_count" -eq 0 ]]; then
    err "no commits ahead of BASE_SHA $BASE_SHA"
    exit 3
fi

# Commit log: subject lines only, oldest first. JSON-escape via jq if available; otherwise raw.
commit_log_raw=$(git log "${BASE_SHA}..HEAD" --reverse --format='%h %s')

# Diff stat: list of files with change counts.
file_changes_raw=$(git diff --stat "${BASE_SHA}..HEAD")

# Voice sample: last 20 commit subjects on this branch + recent history.
voice_sample_raw=$(git log -20 --format='%s' 2>/dev/null || echo "")

# Recent merged PRs (best-effort; gh may be unauthed or rate-limited).
# Fall back to "" silently if gh fails.
recent_prs_raw=""
if command -v gh >/dev/null 2>&1; then
    repo_slug=$(git remote get-url origin 2>/dev/null | sed -E 's|^git@github.com:||; s|^https://github.com/||; s|\.git$||')
    if [[ -n "$repo_slug" ]]; then
        recent_prs_raw=$(gh pr list --repo "$repo_slug" --state merged --limit 10 --json title \
            --jq '.[].title' 2>/dev/null || echo "")
    fi
fi

# Emit JSON. Use jq for safe escaping if available, else use a python3 fallback.
if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg commit_log "$commit_log_raw" \
        --arg file_changes "$file_changes_raw" \
        --arg voice_sample "$voice_sample_raw" \
        --arg recent_prs "$recent_prs_raw" \
        --argjson ahead_count "$ahead_count" \
        --arg base_sha "$BASE_SHA" \
        '{
            base_sha: $base_sha,
            ahead_count: $ahead_count,
            commit_log: $commit_log,
            file_changes: $file_changes,
            voice_sample: $voice_sample,
            recent_prs: $recent_prs
        }'
else
    python3 -c '
import json, os, sys
print(json.dumps({
    "base_sha": os.environ["BASE_SHA"],
    "ahead_count": int(sys.argv[1]),
    "commit_log": sys.argv[2],
    "file_changes": sys.argv[3],
    "voice_sample": sys.argv[4],
    "recent_prs": sys.argv[5],
}, indent=2))
' "$ahead_count" "$commit_log_raw" "$file_changes_raw" "$voice_sample_raw" "$recent_prs_raw"
fi
