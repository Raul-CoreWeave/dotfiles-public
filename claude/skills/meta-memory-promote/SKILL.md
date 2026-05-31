---
name: meta-memory-promote
description: Apply promotion candidates from /meta-memory-audit — graduate rule-shaped memory entries from per-project auto-memory into the right CLAUDE.md scope, then trim the source memory file to a one-line ↑-pointer. Single review-gate; one edit per candidate. Triggers on "promote memory", "graduate to CLAUDE.md", "apply audit promotions", "land these promotions", "/meta-memory-promote".
argument-hint: "[--dry-run] [--only=<slug>,<slug>,...] [--skip-memory-trim]"
---

# meta-memory-promote

Orchestrator: takes `/meta-memory-audit`'s promotion-candidate output and applies
the user-approved subset as concrete CLAUDE.md edits + memory-side trims.

Companion to `/meta-memory-audit` — that skill produces the proposal table and
explicitly stops at "Surface; don't unilaterally edit." This skill is the
"apply" half: audit produces, separate orchestrator consumes.

Scope intentionally narrow (v1):
- **Promotions** (memory → CLAUDE.md scope) — yes, this skill.
- **Dangle-fixes** (broken pointers in CLAUDE.md) — manual; the audit
  surfaces them clearly enough.
- **Demotions** (CLAUDE.md → memory) — manual; rarer and more
  judgment-heavy.
- **Deletions** (duplicates, volatile state) — manual; high-impact, low
  effort, doesn't earn an orchestrator.

## Phase 0: parse args

- `--dry-run` — render the proposed edits but don't apply. Useful for
  walking through a large audit's promotion list without commitment.
- `--only=<slug1>,<slug2>,...` — restrict to specific memory-file slugs
  (without `.md`). Lets the engineer cherry-pick candidates from a long
  list.
- `--skip-memory-trim` — don't modify the source memory files after
  promotion. The promoted entry stays full-content in memory; only the
  CLAUDE.md edit lands. Useful when the memory body has detail worth
  retaining in memory too (past-failure context, links to related
  entries).

## Phase 1: source candidates

Determine the project slug + memory dir per `/meta-memory-audit` Step 1:

```
SLUG=$(pwd | sd '^/' '' | sd '/' '-' | sd '^' '-')
MEMORY_DIR=~/.claude/projects/${SLUG}/memory/
```

If `$MEMORY_DIR/MEMORY.md` doesn't exist, ask the user which slug to target.

Run the audit script directly (no need to dispatch the full skill):

```
~/.claude/skills/meta-memory-audit/scripts/audit-memory.sh "$MEMORY_DIR"
```

Output is the JSON manifest documented in `/meta-memory-audit` SKILL.md Step 2.
Parse it inline.

## Phase 2: identify promotion candidates

For each `memory_files[]` entry in the manifest, classify on the facts vs
rules axis per global `~/.claude/CLAUDE.md` § "Memory Hygiene":

- **Rule** (normative — "always X" / "never Y" — generalizable) →
  **promotion candidate**.
- **Fact** (state / context / project status / personal pointer) → keep
  in memory; skip.
- **Hybrid** — lead with the dominant aspect. Surface the choice in the
  Phase 4 draft.

First-pass signal: the frontmatter `description`. If the description
matches "always …", "never …", "before …, do …", "when X, …", treat as
promotion candidate. If "uses X", "X is the default", "X happened at Y",
treat as fact and skip.

For self-disclosed reinforcers (`self_disclosed_reinforcer: true`) or
self-disclosed duplicates (`self_disclosed_duplicate_of: <line>`), the
entry is a **delete candidate**, not a promotion candidate. Skip — those
go through manual cleanup.

If `--only=` was passed, intersect with that list.

## Phase 3: pick destination scope

For each promotion candidate, pick the narrowest CLAUDE.md scope that
still applies. Use the destination table from `/meta-memory-audit` Step 4:

| Scope | Destination |
|---|---|
| Generic / machine-portable | `~/dotfiles/claude/CLAUDE.md` (source-of-truth; `~/.claude/CLAUDE.md` may be a symlink) |
| Project-specific | `<repo>/CLAUDE.md` |
| Catalog content (too big to inline) | `~/dotfiles/claude/references/<name>.md` (CLAUDE.md keeps a tight summary + pointer) |

Within the destination file, pick the specific section header to insert
under. Use the existing `## ` / `### ` structure; don't invent new
sections unless the candidate genuinely doesn't fit anywhere.

## Phase 4: draft each edit

For each promotion candidate, render a **draft block** with:

```
=== Promotion: <slug>.md ===
  Source: ~/.claude/projects/<slug>/memory/<file>.md
  Destination: <CLAUDE.md path> § "<section>"

  Proposed CLAUDE.md insertion (new paragraph after current § contents):
  ┌─────────────────────────────────────────────────────────────────┐
  │ <drafted rule text — 1-3 sentences, condensed from memory body, │
  │  matches the destination scope's voice and style>               │
  └─────────────────────────────────────────────────────────────────┘

  Memory-side trim (unless --skip-memory-trim):
    Replace body with: "Promoted to <destination> § <section> on YYYY-MM-DD.
    Detail kept for past-failure context: <one-liner from memory body>."
```

Voice for the CLAUDE.md insertion:
- Match the destination file's existing voice. Read 5-10 lines of the
  target section first.
- Lead with the rule ("Always X." / "Never Y." / "Before X, do Y.").
- Include the **Why:** line if it's load-bearing (the memory body usually
  has it).
- Trim past-failure narrative; that stays in memory.

## Phase 5: single review-gate

Show all drafts grouped by destination file. Ask:

> Approve all? Reply `yes` to apply all, `no` to abort, or a
> comma-separated list of slugs to approve a subset.

If `--dry-run`, stop here and don't apply.

## Phase 6: apply

For each approved candidate:

1. **Apply the CLAUDE.md edit** via the Edit tool. The `old_string` is
   the section's current closing context (last line of the section
   before the next `## `), and `new_string` adds the drafted rule
   before that closing context.
2. **Trim the memory file** (unless `--skip-memory-trim`):
   - Replace the body (preserve frontmatter) with the one-liner
     ↑-pointer drafted in Phase 4.
   - Optionally, update `MEMORY.md` line for this entry to add "(promoted YYYY-MM-DD)" suffix.
3. **Record per-candidate result**: applied / skipped / errored.

Verify after each edit: `git diff --stat` on the target repo should show
the right files modified. Apply the "check `git diff --cached --stat`
before commit" discipline if/when the user commits.

## Phase 7: surface a commit message

Group touched files by repo:

- `~/dotfiles/` (if any CLAUDE.md / references / memory edits)
- the project repo (if any project CLAUDE.md edits)

Propose a commit message per repo. Example:

```
docs(claude): promote 2 memory rules to CLAUDE.md

  * feedback_X.md → § "Section Y"
  * feedback_Z.md → § "Section W"

Memory entries trimmed to ↑-pointers; past-failure context retained.
```

Do **not** run `git commit` — that's the engineer's call, per the
no-AI-attribution rule and the per-repo branch discipline.

## Related

- `/meta-memory-audit` — produces the proposal table this skill consumes.
- `~/.claude/CLAUDE.md § "Memory Hygiene"` — the bidirectional facts-vs-rules
  axis this skill operationalizes.

## When to invoke

Triggered by intent phrases ("promote memory", "graduate to CLAUDE.md",
"apply audit promotions", "land these promotions") or typed
`/meta-memory-promote`. Typical workflow:

1. Run `/meta-memory-audit` — surfaces the full proposal table.
2. Decide which promotions to land now.
3. Run `/meta-memory-promote --only=<comma-separated-slugs>` to apply just
   those, OR run `/meta-memory-promote` with no filter to walk the full
   promotion subset at the review-gate.

Cadence: every few weeks, after a session that surfaces multiple
durable rules via memory writes. Not part of daily flow.
