---
name: sync-skill-docs
description: After changing a Claude Code skill, locate every reference to it across CLAUDE.md scopes, commands, references, agents, other skills, and docs; identify drift between the change and those references; propose unified edits before commit. Triggers on "/sync-skill-docs", "sync skill docs", "did my skill change break any references", "check skill doc drift".
argument-hint: "<skill-name> [--base=<git-ref>]"
---

# Sync Skill Docs

Verify that a skill's documentation layers stay in sync after the skill
changes. Runs a deterministic locator script for cross-layer references,
then reasons about whether each reference still matches the new behavior.

A skill change that renames a flag, moves a path, or alters output should
update every place that *describes* the skill — CLAUDE.md Quick Reference
rows, command/agent prose that invokes it, cross-skill See-alsos, README
usage examples. That drift is easy to miss because the references live in
files you weren't editing. This skill makes the *locating* step
deterministic; the LLM still owns the judgment about which references
actually need updating.

## Context

- Working directory: !`pwd`
- Today's date: !`date +%Y-%m-%d`
- Current branch: !`git branch --show-current`
- Working tree state: !`git status --porcelain | head -10`

## Instructions

**Input**: a skill name (matching a directory under `.claude/skills/`).
Optional `--base=<git-ref>` to compare against an older state (default:
HEAD, i.e., uncommitted changes vs. last commit).

```
$ARGUMENTS -> <skill-name> [--base=<git-ref>]
```

If no skill name is given, stop and tell the user:
"Usage: /sync-skill-docs <skill-name> [--base=<git-ref>]
Example: /sync-skill-docs my-skill
Example: /sync-skill-docs my-skill --base=main"

If the skill home (`.claude/skills/<name>/`) does not exist, stop and
report which skill names are valid (`ls .claude/skills/`).

---

## Phase 1: Locate references

Run the deterministic locator:

```
.claude/skills/sync-skill-docs/scripts/find-skill-references.sh \
  <skill-name> [--base=<git-ref>]
```

This returns a JSON manifest with:
- `skill_home`, `home_listing` — files inside the skill's directory
- `git.changed_files`, `git.shortstat`, `git.working_tree` — what actually
  changed (the diff context for everything else)
- `layers.<layer-name>` — every reference to the skill across six layers:
  `claude-md`, `commands`, `references`, `agents`, `other-skills`, `docs`.
  Each layer is an array of `{file, line, excerpt}`.
- `help_drift` — structural diff between the skill's frontmatter
  `argument-hint` flag set and the flags listed in its `## Help` section.
  See Phase 3.5 below.

Read the manifest. If `summary.changed_in_home == 0` AND
`summary.uncommitted_files == 0`, stop — there are no skill changes to
sync against. Otherwise proceed.

---

## Phase 2: Understand the change

Read the actual diff so you can reason about drift:

```
git diff <base> -- <skill_home>
```

Default base is HEAD (working-tree vs. last commit). Identify the categories
of change present:

- **Surface change** — flag added/removed/renamed, output path/format
  changed, command name changed, argument-hint updated. These are the
  highest-priority drift sources because Quick Reference tables and usage
  examples will mismatch.
- **Behavior change** — phase split/merged, new sub-step, new precondition.
  References that describe what the skill *does* may now be wrong.
- **Internal refactor** — script extraction, prompt re-organization, file
  rename inside the skill home. Usually only references that point at
  specific paths are affected.
- **Doc-only** — comment/heading edits inside the skill home with no
  behavior change. Drift risk is low but cross-layer wording consistency
  may still warrant updates.

State which categories apply before continuing.

---

## Phase 3: Cross-reference per layer

For each layer with matches, walk the array. For each `{file, line,
excerpt}`:

1. Read the surrounding context (~10 lines) in the referenced file.
2. Compare against the diff. Decide:
   - **Stale** — the reference describes behavior or surface that changed.
     Plan an Edit.
   - **Affected but acceptable** — the reference is a passing mention that
     happens to be technically accurate. No edit needed.
   - **Out of scope** — the reference is to a different aspect of the
     skill that this change didn't touch.

High-signal layers:

- **`claude-md`** — `CLAUDE.md` / `CLAUDE.*.md` Quick Reference tables.
  Argument-hint and one-liner description must match the SKILL.md
  frontmatter exactly.
- **`commands`** — slash-command files that invoke or index this skill
  (e.g., a `dev.md`/`util.md`-style command catalog). Name/flag changes
  belong here.
- **`other-skills`** — cross-skill prompts and SKILL.md files that
  reference this skill. Path/flag changes can break cross-skill workflows.
- **`agents`** — agent definitions that dispatch this skill.

Skip the `skill_home` listing for drift purposes — that's the source of
truth, not a reference.

---

## Phase 3.5: Help-drift check

Read the manifest's `help_drift` block. It captures:

- `has_help_section` — `true` if the SKILL.md has a `## Help` section.
  If `false`, the skill renders help from prose each invocation (or has
  none). If the skill has user-facing flags, consider adding a `## Help`
  section so help rendering is deterministic.
- `argument_hint_flags` — flags extracted from the frontmatter
  `argument-hint` string.
- `help_section_flags` — flags extracted from the `## Help` section.
- `flags_in_hint_not_in_help` / `flags_in_help_not_in_hint` — the
  symmetric set diff. `in_sync` is the AND of both being empty.

When `in_sync == false`, walk both diff lists. For each flag:

- **Legitimate drift** — the flag was added to `argument-hint` (or a
  phase prose block) but missed in the `## Help` section, or removed
  from the phase but left in Help. Propose the corresponding edit.
- **Cross-skill reference (auto-filtered)** — when a flag belongs to a
  different skill referenced inside the prose (e.g., the Help section
  mentions `/other-skill --some-flag`), the locator truncates the line
  at the cross-skill `/<name>` token before extracting flags, so it
  won't surface here. If one DOES surface, it's a real own-flag drift.
  (The filter only triggers when the `/<name>` token has a trailing
  space; bare `/foo` mentions don't.)
- **Output-path or example glob** — the regex tries to skip path globs,
  but a tightly-scoped string inside an example URL may still trip it.
  Dismiss qualitatively.

If `has_help_section == true` and `in_sync == true`, this check passes —
no edits proposed from this block, even if other layers have drift.

---

## Phase 4: Propose unified edits

Present a single consolidated plan before editing. Group by file:

```
CLAUDE.md
  L78  | Quick Reference description mentions removed --auto flag

.claude/commands/dev.md
  L41  | catalog row needs new --base flag
```

For each file, show the proposed `old_text` → `new_text` (or unified diff)
without applying it yet. Wait for the user to approve the batch.

Once approved, apply edits with the Edit tool, file by file. Re-run the
locator script after edits to confirm zero remaining stale references.

---

## Phase 5: Suggest commit message

Inspect recent skill-change commits with
`git log --oneline -10 -- .claude/skills/<skill>/` and match the repo's
commit format. Propose a single commit covering the skill change *and* the
doc-sync edits — they're one logical change. Example:

```
feat(my-skill): add --base flag + sync doc references

* SKILL.md argument-hint + Help
* CLAUDE.md Quick Reference row
* .claude/commands/dev.md catalog row
```

Do not run `git commit` yourself — that's the user's call. Just present
the message.

---

## Tips

- For high-reference skills, walk one layer at a time and report progress.
  Don't try to hold the whole manifest in working memory at once.
- The `excerpt` field is truncated to 200 chars. When the surrounding
  context matters (table cells, code blocks), Read the file directly.
- If the diff is purely additive (new flag, new phase) and no excerpts
  contradict it, the right answer is often *additive* edits rather than
  rewrites — extend the table row, add a sub-bullet, etc.
- If you're mid-refactor and haven't finished the skill change yet, this
  skill's job is to surface drift, not to insist on premature doc updates.
