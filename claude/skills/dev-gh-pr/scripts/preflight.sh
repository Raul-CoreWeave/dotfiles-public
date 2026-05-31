#!/usr/bin/env bash
# preflight.sh — emit a JSON envelope describing the current branch's ship-readiness.
#
# Used by /dev-gh-pr Phase 0. Determines: branch, base ref, base SHA, ahead/behind
# counts, working-tree cleanliness, push permissions. Bail conditions are
# enforced by the calling SKILL.md, not here — this script just reports state.
#
# Exit codes:
#   0 — JSON envelope emitted to stdout (caller decides if it's a go/no-go)
#   2 — not inside a git repo (no envelope, error on stderr)
#   3 — branch has no upstream and no obvious base candidate (envelope emitted with base_ref=null)

set -euo pipefail

err() { echo "preflight: $*" >&2; }

# Hard requirement: inside a git repo.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    err "not inside a git repo"
    exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
repo_remote_url=$(git remote get-url origin 2>/dev/null || echo "")
# Normalize to owner/repo when origin is a GitHub URL.
repo_slug=""
case "$repo_remote_url" in
    git@github.com:*)
        repo_slug="${repo_remote_url#git@github.com:}"
        repo_slug="${repo_slug%.git}"
        ;;
    https://github.com/*)
        repo_slug="${repo_remote_url#https://github.com/}"
        repo_slug="${repo_slug%.git}"
        ;;
esac

branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" == "HEAD" ]]; then
    err "detached HEAD; /dev-gh-pr needs a named branch"
    branch="(detached)"
fi

# Discover base ref — the branch a PR from HEAD would target.
# Preference order:
#   1. origin's HEAD symbolic ref (GitHub's repo default branch — the authoritative answer)
#   2. origin/main, origin/master, origin/development (fallbacks if origin/HEAD unset)
# Notably, the local branch's @{upstream} is NOT used — for a feature branch pushed
# to its own name, upstream IS the branch itself, and that's not a useful PR base.
base_ref=""
origin_head=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || echo "")
if [[ -n "$origin_head" ]]; then
    # Format: refs/remotes/origin/main -> strip "refs/remotes/"
    base_ref="${origin_head#refs/remotes/}"
fi
if [[ -z "$base_ref" ]]; then
    for candidate in origin/main origin/master origin/development; do
        if git rev-parse --verify --quiet "$candidate" >/dev/null; then
            base_ref="$candidate"
            break
        fi
    done
fi
# If the resolved base is the same ref as HEAD, /dev-gh-pr is being invoked on the
# default branch directly — no PR-ready scenario, flag this in the envelope.
on_default_branch=false
if [[ -n "$base_ref" ]]; then
    base_short="${base_ref#origin/}"
    if [[ "$branch" == "$base_short" ]]; then
        on_default_branch=true
    fi
fi

base_sha=""
ahead_count=0
behind_count=0
if [[ -n "$base_ref" ]]; then
    base_sha=$(git rev-parse "$base_ref")
    # ahead/behind relative to base
    counts=$(git rev-list --left-right --count "${base_ref}...HEAD" 2>/dev/null || echo "0	0")
    behind_count=$(echo "$counts" | awk '{print $1}')
    ahead_count=$(echo "$counts" | awk '{print $2}')
fi

# Working tree cleanliness — porcelain output is empty iff clean.
clean_tree=true
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    clean_tree=false
fi

# Push permissions detection.
# Layer 1: per-repo known-no-push list. Add a `case` entry here if a given repo
# is known to refuse pushes for the current user (e.g. you only have read access
# and contribute via someone else's merge). Default: no entries — assume pushable.
push_perms="unknown"
denied_reason=""

# Layer 2: if not denied by layer 1 and we have a remote, we *could* probe push
# perms via git ls-remote. Skipped here to keep preflight offline; report
# "unknown" and let the engineer decide. A real push attempt later will surface
# a clear error.
if [[ "$push_perms" == "unknown" && -n "$repo_remote_url" ]]; then
    push_perms="unknown"
fi

# Emit JSON envelope.
# Using printf rather than jq to avoid a hard dependency. Values are simple strings/ints/bools.
cat <<EOF
{
  "repo_root": "$repo_root",
  "repo_slug": "$repo_slug",
  "repo_remote_url": "$repo_remote_url",
  "branch": "$branch",
  "base_ref": $(if [[ -n "$base_ref" ]]; then echo "\"$base_ref\""; else echo "null"; fi),
  "base_sha": $(if [[ -n "$base_sha" ]]; then echo "\"$base_sha\""; else echo "null"; fi),
  "ahead_count": $ahead_count,
  "behind_count": $behind_count,
  "clean_tree": $clean_tree,
  "on_default_branch": $on_default_branch,
  "push_perms": "$push_perms",
  "denied_reason": "$denied_reason"
}
EOF

if [[ -z "$base_ref" ]]; then
    exit 3
fi
