---
name: dev-gh-pr
description: PR-preparation orchestrator for a feature branch ready to push. Runs preflight (branch ahead of base, working tree clean, push perms), an optional simplification pass (code-simplifier agent on non-trivial code; skipped for prose-only diffs), then /deep-review against a locked base SHA, presents a triage menu for Medium+ findings (act-on-all / act-on-subset / ignore-and-proceed / abort), dispatches /feedback-driven-dev for the act path, loops up to 3 cycles, then drafts a PR body in repo voice for review-gate approval before any gh pr create. Triggers on "/dev-gh-pr", "ship this branch", "wrap up the PR", "ready to push", "open the PR", "prepare the PR".
---

# /dev-gh-pr — PR-preparation pipeline

Orchestrator skill. Wraps an optional simplification pass (code-simplifier agent), `/deep-review`, and `/feedback-driven-dev` into one review-gated flow ending at a copy-pasteable `gh pr create` command. The skill does not push or open the PR itself — the last step prints the body for the engineer to run.

## When to use this
After the work feels done on a feature branch and you want a coherent preflight → review → fix → re-review → PR-draft pass without typing the four commands separately. The skill drafts the PR body for the engineer; the actual `gh pr create` happens at the engineer's prompt — Claude Code's interactive consent for the `gh` tool call surfaces naturally if it's not auto-allowed.

## When NOT to use this
- WIP branches you're not ready to ship — run `/deep-review` standalone instead, or the `code-simplifier` agent.
- One-line fixes that don't justify the cycle cost. Just commit and `gh pr create` manually.

## Inputs

`$ARGUMENTS` is optional:

| Form | Meaning |
|---|---|
| (empty) | Run the full pipeline against the current branch's upstream base (auto-discovered) |
| `--base=<ref>` | Override base branch (default: `origin/main` or `origin/master`, falls back to repo's default) |
| `--dry-run` | Run preflight + one deep-review pass; skip the iteration loop and PR draft. Useful as a "show me what /dev-gh-pr would do" check. |
| `--max-cycles=<N>` | Override the cycle cap (default 3). `N=1` for single-pass mode. |

## Phases

### Phase 0 — Preflight

Run `scripts/preflight.sh`. The script emits a JSON envelope:

```json
{
  "repo_slug": "owner/repo",
  "branch": "feature/my-topic",
  "base_ref": "origin/main",
  "base_sha": "5659afcc...",
  "ahead_count": 12,
  "behind_count": 0,
  "clean_tree": true,
  "on_default_branch": false,
  "push_perms": "unknown",
  "denied_reason": ""
}
```

**Bail conditions** (surface the reason, exit before invoking any other skill):
- `on_default_branch=true` → "you're on the default branch (`<base>`); /dev-gh-pr is for feature branches. Switch to a topic branch before invoking."
- `clean_tree=false` → "working tree dirty; commit or stash before /dev-gh-pr". Show `git status --short`.
- `ahead_count=0` → "branch has no commits ahead of `<base>`; nothing to ship".
- `push_perms=denied` → print `denied_reason` and stop. Suggest the alternative (commit locally; the work-product is the local commits).
- `behind_count>0` → "branch is N commits behind `<base>`; rebase first to avoid merge-conflict noise in /deep-review". Don't auto-rebase — that's a destructive op user must opt in to.

If all checks pass, **lock `base_sha` for the rest of the run**. Every subsequent `/deep-review` invocation compares against this SHA, not the moving `origin/<base>` tip — that avoids the rebase-changes-the-diff gotcha.

### Phase 1 — Simplification pass (optional)

If a `code-simplifier:code-simplifier` agent is available, use it; if not, skip this phase. Default behavior: **skip this phase** unless the diff warrants it.

Substitute conditions (opt-in, only when the diff actually warrants it):

- Diff includes **non-trivial code** (scripts, hooks, integrations) — spawn the `code-simplifier:code-simplifier` agent via the Agent tool against the changed files. Then check `git status`; if the agent left edits, commit with a terse message (subject style inferred from `git log -20 --oneline`; no AI authorship attribution).
- Diff is **prose-only** (docs, markdown content, config edits) — skip entirely. Simplification has no value on prose; the engineer's voice + tight commits are the quality bar.

If a pre-commit hook fails on a simplify commit: do NOT `--no-verify`. Surface the hook output, ask the engineer to fix manually, then re-run `/dev-gh-pr`. (Per git safety: after a hook failure, fix the issue, re-stage, and create a NEW commit.)

### Phase 2 — /deep-review

Invoke `/deep-review` via the Skill tool. Pass the locked base via `args` if the skill accepts it; otherwise it auto-derives.

`/deep-review` reports Medium+ findings only by design. Read its output, group findings by category (correctness / security / architecture / git-history) and severity (Critical / High / Medium). If zero Medium+ findings, jump to Phase 5.

### Phase 3 — Triage gate (Medium+ findings present)

Present grouped findings to the engineer with a four-option menu via `AskUserQuestion`:

| Option | Behavior |
|---|---|
| **Act on all** | Pass the entire findings block to `/feedback-driven-dev` |
| **Act on subset** | Follow-up: which findings to act on? (numbered list). Pass only the selected subset. |
| **Ignore and proceed** | Treat the findings as accepted-as-is; jump to Phase 5 with a note in the PR body's "Known limitations" section |
| **Abort** | Exit without drafting a PR. State remains: branch untouched beyond any commit Phase 1 may have produced. |

Phrase the menu in plain English — no phase numbers, no JSON field names. Findings already have skill-emitted labels; reuse those.

### Phase 4 — /feedback-driven-dev (loop body)

Invoke `/feedback-driven-dev` via the Skill tool with the selected findings as `args`. The skill has internal gates (plan review, PR creation). `/dev-gh-pr` should ignore the skill's own PR-creation step — it's running inside `/dev-gh-pr`'s loop, so the outer skill draws the PR draft, not the inner skill. If the inner skill insists on opening a PR, surface that and let the engineer abort or accept.

On return, increment cycle counter. If `cycle < max_cycles` (default 3): loop back to Phase 2 with the **same locked base_sha**. If `cycle == max_cycles`: surface "hit cycle cap; remaining Medium+ findings may be taste-divergent reviewer opinions — proceeding to PR draft with findings noted". Then Phase 5.

### Phase 5 — PR body draft

Run `scripts/draft-pr-body.sh` to scaffold the raw material:
- `git log <base_sha>..HEAD --reverse --format='%h %s'` for the commit list
- `git diff <base_sha>..HEAD --stat` for the file-change summary
- `git log -20 --oneline` for repo voice inference

The LLM (you) then composes the PR body using `reference/pr-template.md` as the structural skeleton. Match the repo's commit style for the PR title; mirror past PR titles where visible (the engineer's recent merged PRs are a stronger signal than my defaults). Strip any AI authorship attribution — the template explicitly omits it; if the inferred voice somehow surfaces one, drop it.

Include a "Known limitations" or "Out of scope" section ONLY if Phase 3 was reached with "Ignore and proceed".

### Phase 6 — Review gate + output

Present the drafted body for review via plain chat (NOT `AskUserQuestion` — this is paste-quality content the engineer wants to see in full, not a dropdown). Show the suggested `gh pr create` command beneath. Default to `--draft`:

```
gh pr create \
  --base <base_ref> \
  --head <branch> \
  --draft \
  --title "<inferred title>" \
  --body "$(cat <<'EOF'
<drafted body>
EOF
)"
```

Wait for explicit approval per the review-gate rule. On approval, the engineer runs the command themselves — `/dev-gh-pr` does NOT invoke `gh pr create`. This keeps the public-record artifact creation firmly in the engineer's hands.

## State across phases

Single-session in-memory state suffices:
- `base_sha` (locked once at Phase 0)
- `cycle` counter (0-indexed, increments at Phase 4 exit)
- `accepted_findings` (list of findings the engineer accepted-as-is in Phase 3, for the PR body's limitations section)

No state file needed. If the engineer ctrl-Cs mid-run, restart from Phase 0 — preflight is idempotent.

## Voice + attribution

`/dev-gh-pr` output to the engineer is plain English. No phase numbers in chat (those are for this SKILL.md, not the engineer). No "Co-Authored-By: Claude" / "Generated with Claude Code" in any commit or PR artifact, ever.

## Output shape

End-of-run, the chat surfaces:
1. Preflight snapshot (one-line: branch, base, ahead count, cycles run)
2. Findings summary (count by severity, after Phase 4 loop concludes)
3. The drafted PR body (in a fenced block, ready to copy)
4. The suggested `gh pr create` command (in a fenced block beneath)
5. Any accepted-as-is findings, with a one-line rationale per item

## Related skills

- `code-simplifier:code-simplifier` agent — optional Phase 1 pass, only when diff includes non-trivial code
- `/deep-review` — invoked in Phase 2 when loaded; if it isn't active in this session, surface the gap and substitute with `/code-review` + `/security-review` (built-in)
- `/feedback-driven-dev` — invoked in Phase 4 when loaded
