---
name: meta-lessons
description: Session-type-agnostic lesson-capture skill. Audits the current session for operational lessons, design insights, gotchas, and durable-artifact-worthy findings — across any session shape (dev / ad-hoc / docs / investigation). Classifies each finding as KB-shaped (route to a repo's docs/ or ~/dotfiles/claude/references/), CLAUDE.md-shaped (route to the narrowest applicable scope), or memory-shaped (route to ~/.claude/projects/<slug>/memory/) per the three-tier hygiene framework in global CLAUDE.md § "Memory Hygiene". Surfaces a proposal table for human review; applies on accept. Triggers on "/meta-lessons", "session lessons", "lessons learned this session", "what should we capture from this session", "session audit".
argument-hint: "[-h|--help] [--dry-run] [--no-commit] [--skip-memory]"
---

# /meta-lessons — session-type-agnostic lesson capture

Audits the current conversation for durable-artifact-worthy findings,
classifies them per the three-tier hygiene framework, routes each to the
appropriate destination, applies edits + commits on the current branch
(no PR by default).

## Why this exists

Claude Code sessions span many shapes:

- **Dev sessions** — extending skills, building hooks, refactoring
  CLAUDE.md, designing orchestrators. Lessons here belong to
  `~/dotfiles/claude/references/`, global CLAUDE.md, or memory.
- **Cross-domain investigations** — patterns that don't fit any single
  domain doc.
- **Ad-hoc tool exploration** — discoveries about MCP servers, plugin
  behaviors, harness quirks that route to references/ catalogs.

`/meta-lessons` routes by destination class, not by source session type.

## Relationship to siblings

| Skill | Scope | Destination |
|---|---|---|
| `/meta-lessons` (this skill) | Any session type, additions sourced from session experience | Per-finding routing across all three tiers |
| `/meta-memory-audit` | Bidirectional facts↔rules audit of EXISTING memory | Surfaces promotion candidates from already-stored content |

The boundary with `/meta-memory-audit`: this skill harvests NEW lessons
from the current session's flow; that skill audits the ALREADY-STORED
memory state for misclassification. Different I/O.

## Inputs

`$ARGUMENTS` is zero-or-more of:

| Flag | Effect |
|---|---|
| `--dry-run` | Surface the proposal table only; don't apply edits or commit. |
| `--no-commit` | Apply edits in working tree but skip the git commit. |
| `--skip-memory` | Don't write memory entries; only consider KB / CLAUDE.md destinations. |
| `-h` / `--help` | Print this matrix and exit. |

Default: full audit → proposal table → review-gate → apply + commit per
file on the current branch (no PR).

## Phase 1 — gather session signals

Scan the conversation transcript for lesson-worthy patterns. Signals
include:

- **Corrections from the user** (any "actually" / "no, the right approach
  is X" / "stop doing Y") — strong signal these are rule-shaped.
- **`/wtf` sentinels** emitted earlier this session — already classified
  by the wtf skill; this skill consumes the classification.
- **Verified facts the user surfaced** ("turns out the bucket is
  public-readable") — fact-shaped, route to KB.
- **Design decisions reached in conversation** ("we're going with B
  because A is structurally impossible") — could route to CLAUDE.md if
  generalizable, or memory if user-specific.
- **Gotchas / surprise behaviors** (sandbox blocks, BSD-vs-GNU
  differences, tool flag misnamings) — typically references/ catalog
  shaped.
- **Cross-skill design patterns** observed during skill-building (the
  scripts-first contract, verb-dispatcher patterns, JSON envelopes) —
  CLAUDE.md / references shaped.

## Phase 2 — classify each finding

For each candidate, apply the three-tier hygiene framework per global
CLAUDE.md § "Memory Hygiene" → "Quick decision flow":

1. Is it a **rule** (always X / never Y, normative)? → CLAUDE.md (tier 1).
2. Otherwise it's a **fact**. Is it specific to this user (role, prefs,
   machine, project state)? → memory (tier 2).
3. Is it generalizable to any engineer in this project / domain? → KB
   (tier 3).
4. Tiebreaker: prefer KB unless Claude would behave wrong from turn 1
   without already knowing the fact.

For each finding, also identify the most-specific scope:

| Tier | Scope question | Destinations |
|---|---|---|
| CLAUDE.md | Universal / project? | `~/dotfiles/claude/CLAUDE.md` (global), `<repo>/CLAUDE.md` (project) |
| memory | Project-scoped persistent memory | `~/.claude/projects/<cwd-slug>/memory/<descriptive_name>.md` |
| KB | What's the topic? | `~/dotfiles/claude/references/<topic>.md`, repo-specific `docs/` dirs |

## Phase 3 — surface proposal table

Format:

```
# /meta-lessons proposal — YYYY-MM-DD

## Findings (N)

| # | Lesson | Class | Destination | Action |
|---|--------|-------|-------------|--------|
| 1 | <one-line summary> | rule | `~/dotfiles/claude/CLAUDE.md § <section>` | append section |
| 2 | <one-line summary> | fact-universal | `~/dotfiles/claude/references/<topic>.md` | new file |
| 3 | <one-line summary> | fact-user | `~/.claude/projects/<slug>/memory/feedback_<name>.md` | new file |

## Body drafts

### Finding #1 — <topic>

**Destination:** `<path>` (append to section "<section title>")

**Draft body:**

```markdown
<draft text exactly as it would land>
```

### Finding #2 — ...

...

---

Reply with:
- `apply N` — apply finding N (single)
- `apply N M ...` — apply listed findings
- `apply all` — apply everything
- `skip N` — drop finding N
- `revise N` — surface for re-classification
- `done` — accept current state, no more changes
```

## Phase 4 — apply + commit (default; skip on --dry-run)

For each accepted finding:

1. Read the destination file (or note it's a new file).
2. Apply the edit (Write for new, Edit for append).
3. Per global CLAUDE.md "Bundle stage + verify + commit": chain
   `git add <file> && git diff --cached --stat && git commit -m "<msg>"`
   for each repo touched. Multiple files in the same repo can batch
   into one commit; cross-repo edits get one commit each.
4. Commit message style: match the repo's `git log -20 --oneline` per
   "Discover per-repo conventions before your first commit".
5. No AI-authorship attribution per global rule.

## Phase 5 — apply timestamp + recap

Write completion marker for downstream consumers (the session-end footer
reads this):

```bash
mkdir -p ~/.local/share/claude-meta
date -u +%Y-%m-%dT%H:%M:%SZ > ~/.local/share/claude-meta/last-meta-lessons
```

Surface a recap: "Applied N findings across M files in K repos. Skipped X.
Dry-run only" (if --dry-run).

## Composes with

- `/meta-memory-audit` — adjacent. That skill audits ALREADY-STORED
  memory; this skill writes NEW memory entries from session experience.
  Run them in sequence at session-end for full memory hygiene.

## Pitfalls

- **Don't surface findings the user explicitly rejected mid-session.**
  When the user said "no, that's not right" earlier and the correction
  already landed in conversation, capturing it as a "lesson" double-counts.
  Surface only findings that haven't yet been written to durable storage.
- **Memory entries pay context cost forever.** Per global "Memory Hygiene"
  tiebreaker: prefer KB unless Claude would behave wrong from turn 1
  without already knowing the fact. When ambiguous, route to KB.
- **CLAUDE.md edits require human review.** Even when the classification
  is clearly rule-shaped, surface the draft and wait for approval — don't
  silently edit a CLAUDE.md scope. Same discipline as `/meta-memory-promote`.
- **Respect per-repo push constraints.** If a repo has no push perms, use
  its long-lived working branch; commits land there without push. Match
  the per-repo branch convention.
- **`--dry-run` is the safe exploratory mode.** Surfaces candidates without
  applying; run `/meta-lessons` (without flags) explicitly to apply.
