---
name: meta-edit
description: CLAUDE.md edit orchestrator with PRE-edit conflict + activation checks. Inverts the current "edit then discover overlap weeks later via /meta-conflicts" pattern. Before any CLAUDE.md write, invokes /meta-rules to surface existing related sections and /meta-conflicts (simulation mode) to detect what the draft would collide with — engineer revises before commit, not after drift is already shipped. Operates on global, project, or mode scopes. Triggers on "/meta-edit", "edit CLAUDE.md", "add a rule to CLAUDE.md", "draft a CLAUDE.md edit", "modify CLAUDE.md".
argument-hint: "<scope> [topic-hint] [--dry-run]"
---

# /meta-edit — CLAUDE.md edit with pre-check

Orchestrator for adding or modifying a CLAUDE.md rule. Composes the existing
`/meta-rules` and `/meta-conflicts` sensors as PRE-edit checks instead of
post-hoc audits.

## Why this exists

Current CLAUDE.md edit pattern:
1. Engineer drafts a new rule
2. Edits the CLAUDE.md scope
3. Commits
4. Weeks later, `/meta-conflicts` surfaces the new rule overlaps with an
   existing rule in another scope, OR `/meta-rules` shows the new section
   is dead-weight (zero cites) because an existing rule covered it
5. Engineer rewrites / consolidates / removes — work was wasted

Pre-edit checks invert this. The orchestrator surfaces existing related
content + potential conflicts BEFORE the engineer writes the new rule, so
the engineer either revises the draft to fit existing scope, consolidates
into the related section, or proceeds with conscious awareness of the
overlap.

## Inputs

| Arg | Meaning |
|---|---|
| `<scope>` | Required. One of: `global`, `project`, `mode`. Selects which CLAUDE.md scope to edit. (Add your own scope aliases in Phase 0 if you maintain extra mode files.) |
| `<topic-hint>` | Optional. Short keyword to filter /meta-rules to related sections (e.g., "memory hygiene", "commit conventions", "shell idioms") |
| `--dry-run` | Surface the pre-check findings only; skip the edit + commit |

## Phases

### Phase 0 — resolve scope path

| Scope arg | File |
|---|---|
| `global` | `~/.claude/CLAUDE.md` (or its dotfiles source, e.g. `~/dotfiles/claude/CLAUDE.md`) |
| `project` | active CWD's `CLAUDE.md` |
| `mode` | the active mode file in the project, e.g. `<repo>/CLAUDE.<mode>.md` |

Confirm the file exists; surface to the engineer for verification. If you
maintain additional named scope files, add them to this table.

### Phase 1 — related-sections scan (/meta-rules)

Invoke `/meta-rules` filtered to the target scope. Surface:

- Section headers in the target scope (cite_count, last_cite_ts)
- If `<topic-hint>` provided, narrow to sections whose headers match
  topic keywords (substring; case-insensitive)
- Highlight sections with >0 recent cite count — those are load-bearing
  rules the engineer should respect / consolidate with

This gives the engineer the "what's already there" context before drafting.

### Phase 2 — engineer drafts the rule

Engineer provides the draft text (in chat or via prompt). For new rules:
section header + body paragraph. For modifications: target section header
+ proposed new content.

Skill prompts: "Drop the draft text here, or describe the rule and I'll
propose wording."

### Phase 3 — conflict simulation (/meta-conflicts)

Run `/meta-conflicts` in simulation mode against the draft:

- Extract the draft's section header + body bullet content
- Compare against rules in OTHER scopes (cross-scope collisions are the
  primary risk; same-scope is usually intentional refinement)
- Classify: header collision / near-duplicate header / body overlap
- Surface candidates: `consolidate` / `intentional-override` /
  `contradict` / `complement` / `false-positive`

If `--dry-run`: stop here with the conflict report.

### Phase 4 — gate + apply

Surface the draft alongside conflict findings. Engineer's choices:
- Apply as-is (conscious of overlap)
- Consolidate with existing section (modify scope of edit)
- Refine the draft (re-loop to Phase 3)
- Abort

On apply: Edit the CLAUDE.md scope file at the appropriate insertion point
(end of relevant section, or after the last related rule). Use the Edit
tool with exact old_string + new_string matches.

### Phase 5 — commit

Per global "Bundle stage + verify + commit":

```bash
git -C <repo> add claude/CLAUDE.md  # or appropriate scope
git -C <repo> diff --cached --stat
git -C <repo> commit -m "<type>(claude): <one-line summary>

<body paragraph>

<context about why this rule earns its place — past failure context,
related sentinels, etc.>"
```

Commit-message style inferred from `git log -20 --oneline` on the target
repo per "Discover per-repo conventions". No AI attribution.

## Output contract

- Phase 1: list of related sections with cite counts
- Phase 3: conflict findings table
- Phase 4: applied diff
- Phase 5: commit SHA

## Composes with

- `/meta-rules` — Phase 1 — extracts existing rules + their activation
- `/meta-conflicts` — Phase 3 — cross-scope conflict detector (uses its
  simulation/draft mode if available, else compares draft body against
  the existing extracted rules)
- `claude-md-management:claude-md-improver` — adjacent. That plugin
  audits CLAUDE.md structural quality; this orchestrator does pre-edit
  conflict checks. Could compose: run `claude-md-improver` after
  `/meta-edit` to verify the new section follows the template.
- `/dev-skill` — sibling pattern. `/dev-skill` is the pre-commit gate
  for skill edits; `/meta-edit` is the pre-edit gate for CLAUDE.md.

## Pitfalls

- **Don't bypass for "small" edits.** Even one-line additions can collide.
  The orchestrator is fast; engineer reflex of "I'll just edit directly"
  is the failure mode.
- **Phase 2 expects the draft, not the desired outcome.** "I want a rule
  about commit conventions" is not enough — surface a request for draft
  text before running Phase 3 conflict-check.
- **`--dry-run` for exploring before drafting.** Use it to scope what
  exists in the target area before committing to a draft.
- **Cross-scope vs same-scope conflicts.** Same-scope refinements (adding
  a sub-bullet under an existing rule) typically aren't conflicts; the
  orchestrator should suppress those by default. Cross-scope is where
  silent drift accumulates.
