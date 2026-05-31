---
name: dev-skill
description: Skill-development workflow orchestrator. When you've finished editing a skill, this composes the full ship cycle — detect changes → /sync-skill-docs to catch reference drift → optional /skill-creator eval if measurable behavior changed → /meta-conflicts if CLAUDE.md scopes were edited → commit per repo convention with no AI attribution. Closes the "forgot to run /sync-skill-docs" gap that creates downstream drift the meta-* sensors later catch. Read-only by default until commit phase; per-phase review-gates for any mutation. Triggers on "/dev-skill", "ship skill", "finish skill", "wrap up skill change", "complete skill build".
argument-hint: "[skill-name] [--eval] [--no-commit] [--dry-run]"
---

# /dev-skill — skill-development workflow orchestrator

Composes the full ship cycle for a skill edit, replacing the manual sequence
(edit → maybe-sync → maybe-eval → maybe-conflict-check → commit) with a single
phased flow that gates each step.

## Why this exists

Skill changes drift quietly: SKILL.md gets edited, but `/sync-skill-docs` (which
catches references to that skill in CLAUDE.md tables, sibling SKILL.md files,
docs/index rows, CONTRIBUTING.md, etc.) gets forgotten. The drift surfaces later
via `/meta-conflicts` / `/meta-rules` audits, often weeks after the edit.
Prevention is cheaper than detection.

This orchestrator runs the same checks that `/dev-gh-pr` runs at PR-time, but at
single-edit granularity — useful for working-branch sessions where commits land
without PRs.

## Inputs

| Arg | Meaning |
|---|---|
| `<skill-name>` | Explicit skill to ship; otherwise auto-detect from `git diff` |
| `--eval` | Run `skill-creator:skill-creator` eval after sync (default: skip — eval is slow + only meaningful when measurable behavior changed) |
| `--no-commit` | Stage edits but skip commit (engineer wants to bundle with other work) |
| `--dry-run` | Surface what each phase would do; apply nothing |

## Phases

### Phase 0 — detect changes

`git diff HEAD --name-only` from each candidate skill root. Common roots:
- `~/.claude/skills/` (user-level)
- `<repo>/.claude/skills/` (project-level, when CWD is inside a repo that ships skills)

Filter to skill-shaped paths (`<root>/<skill-name>/SKILL.md` or `<root>/<skill-name>/{scripts,reference}/*`).

If multiple skills modified and no `<skill-name>` arg, surface the list and ask which to ship. If none, exit clean.

### Phase 1 — /sync-skill-docs

For the target skill, invoke `/sync-skill-docs <skill-name>` via the Skill tool
(if available). Read its output for drift findings. Surface to the engineer:

- Files referencing the skill that need updates (e.g., a CLAUDE.md Quick Reference table row)
- Stale path references (e.g., a SKILL.md mentioning a script that's been moved)
- New references that should be added but aren't

If `--dry-run`: stop here with the drift report. Otherwise, gate on accept;
apply the propagation edits.

### Phase 2 — optional eval (gated by `--eval`)

If `--eval`: invoke `skill-creator:skill-creator` eval mode against the skill.
Surface eval results (description-matching accuracy, trigger-precision, variance
analysis). Engineer decides whether to revise description before commit.

Skip if eval is slow (typically minutes) and the skill change is prose-only or
purely structural.

### Phase 3 — conflict check (conditional)

If the skill edits also touched CLAUDE.md scopes (any CLAUDE.md file), invoke
`/meta-conflicts` filtered to the touched scopes. Surface any header collisions /
near-duplicates / body overlaps introduced by the edit.

Gate on accept; revise edits if conflicts surface.

### Phase 4 — commit

Bundle stage + verify + commit in a single shell call:

```bash
git -C <repo> add <explicit-files> \
  && git -C <repo> diff --cached --stat \
  && git -C <repo> commit -m "<message>"
```

Commit message style inferred from `git log -20 --oneline`. No Claude / AI
authorship attribution. One commit per skill — cross-repo edits get one commit
per repo.

If `--no-commit`: stage only; print the diff stat for the engineer to commit
manually when bundling other work.

### Phase 5 — recap

Single-line summary: `Shipped <skill-name>: <N> files in <M> repos. Drift
caught: <K>. Conflicts: <J>. Commit: <SHA>.`

## Composes with

- `/sync-skill-docs` — Phase 1 — the deterministic doc-sync engine
- `skill-creator:skill-creator` — Phase 2 — optional eval
- `/meta-conflicts` — Phase 3 — CLAUDE.md scope-overlap detector
- `/dev-gh-pr` — sibling pattern at PR-time. `/dev-skill` is the
  single-commit-at-edit-time equivalent for working-branch flows where PRs
  aren't the work unit.

## Pitfalls

- **Don't `--eval` for prose-only changes.** Eval is slow and reveals no signal
  for description or formatting tweaks. Reserve for changes to triggers,
  scripts, or output shapes.
- **Phase 3 only fires if CLAUDE.md scopes were also edited.** A pure SKILL.md
  edit won't trigger it. That's correct — conflicts are scope-vs-scope.
- **The Phase 4 commit lands on whatever branch is currently checked out** —
  don't override. Verify the branch is the one you intend before committing.
- **Multiple-skill edits**: when several skills are touched together, default
  to one-commit-per-skill.
- **Don't suppress `/sync-skill-docs` output.** Even on `--no-commit`, surface
  the drift so the engineer sees what got modified in the working tree.
