---
name: meta-memory-audit
description: Audit Claude Code per-project auto-memory against the in-scope CLAUDE.md files, classify each memory entry as fact vs rule per the global "Memory Hygiene" axis, and surface promotion / demotion / deletion candidates as a structured proposal table. Triggers on "memory audit", "audit my memory", "facts vs rules check", "/meta-memory-audit", or "scan memory for promotion candidates."
---

# meta-memory-audit — bidirectional facts ↔ rules audit of Claude Code memory

When invoked, run the audit per the global `~/.claude/CLAUDE.md` § "Memory Hygiene" axis: **facts go in memory, rules go in CLAUDE.md**. Surface promotion candidates (memory entries that are rules) and demotion candidates (CLAUDE.md content that's actually facts), grouped by destination scope. **Surface; don't unilaterally edit** — present the proposal table and wait for direction.

## How it works

The deterministic part is in `scripts/audit-memory.sh` (scripts-first contribution discipline — the script does the cheap deterministic work, the LLM does the judgment): it enumerates memory files, parses frontmatter, locates in-scope CLAUDE.md files, and detects self-disclosed reinforcers ("reinforcer for CLAUDE.md", "duplicate of …", "expansion of line X"). Output is structured (JSON). The LLM (this skill's prompt) reasons over that output to classify and propose moves.

## Steps

### Step 1 — Determine the memory directory for the current project

Claude Code stores per-project auto-memory under `~/.claude/projects/<cwd-slug>/memory/`. The slug is derived from the launch CWD. Discover it:

```
SLUG=$(pwd | sd '^/' '' | sd '/' '-' | sd '^' '-')
MEMORY_DIR=~/.claude/projects/${SLUG}/memory/
```

If `$MEMORY_DIR/MEMORY.md` exists, that's the audit target. If it doesn't, ask the user which slug they want audited (they may have switched directories mid-session).

### Step 2 — Run the audit script

```
.claude/skills/meta-memory-audit/scripts/audit-memory.sh "$MEMORY_DIR" | tee "${TMPDIR:-/tmp}/meta-memory-audit-output.json"
```

The script emits a JSON manifest:

```json
{
  "memory_dir": "/Users/<user>/.claude/projects/.../memory/",
  "memory_files": [
    {
      "name": "feedback_X.md",
      "type": "feedback|user|project|reference",
      "frontmatter": {"name": "...", "description": "..."},
      "body_first_500": "...",
      "self_disclosed_reinforcer": true | false,
      "self_disclosed_duplicate_of": "<CLAUDE.md line N>" | null,
      "indexed_in_MEMORY_md": true | false
    }
  ],
  "claude_md_files": [
    {"path": "/Users/<user>/.claude/CLAUDE.md", "size_bytes": ..., "section_headers": [...]}
  ],
  "references_files": [...],
  "dangling_pointers": [{"claude_md": "...", "missing_path": "..."}]
}
```

The set of in-scope CLAUDE.md files (global + project-repo) is discovered by the script via the `CLAUDE_MD_FILES` env var (a colon-separated list); if unset it defaults to the global scope plus any `CLAUDE.md` in the launch CWD's git root.

### Step 3 — Classify each memory entry

For each `memory_files[]` entry, classify it on the **facts vs rules** axis:

- **Fact**: state, context, who/what/where, current project status, historical reference, current operational reality. Stays in memory.
- **Rule**: always X / never Y / generalizable behavior. Belongs in CLAUDE.md at the narrowest scope that still applies.
- **Hybrid**: lead with the dominant aspect. If the fact-part is what's load-bearing, keep in memory and inline-mention the rule. If the rule-part is load-bearing, promote and let the fact stay implied.

Use the `description` frontmatter as the first-pass signal; read the body if uncertain. Memory entries with `self_disclosed_reinforcer: true` or `self_disclosed_duplicate_of: <line>` are usually delete candidates.

### Step 4 — Pick destination scope for each rule

| Rule scope | Destination |
|---|---|
| Generic / machine-portable | `~/.claude/CLAUDE.md` (→ `~/dotfiles/claude/CLAUDE.md` if symlinked) |
| Project-specific | `<repo>/CLAUDE.md` |
| Catalog content (too big to inline) | `~/dotfiles/claude/references/<name>.md` (CLAUDE.md keeps a tight inline summary + pointer) |

For each rule candidate, name the specific section/subsection in the destination file where it'd land.

### Step 5 — Look for facts in CLAUDE.md (the demotion direction)

Read the in-scope CLAUDE.md files and flag anything that's a fact rather than a rule. Common patterns:
- "As of <date>, X is the current Y" → fact (memory candidate)
- Project status snapshots → borderline; usually stable enough to leave
- Path tables, MCP endpoint tables, skill quick-reference tables → facts-as-context for rules; almost always stay

Most CLAUDE.md fact-shaped content is load-bearing context for rules; don't demote unless removal wouldn't force the rules to repeat the context. Demotion candidates are rarer than promotion candidates in practice.

### Step 6 — Detect dangling pointers

The audit script's `dangling_pointers[]` lists CLAUDE.md references to memory files that no longer exist. Either:
- The memory file was deleted but the CLAUDE.md reference wasn't updated
- The memory file was renamed
- The reference was a typo

Flag each in the proposal as a `dangling` fix.

### Step 7 — Emit the proposal table

Group by action category:

```markdown
## Memory → CLAUDE.md promotions

### Global ~/.claude/CLAUDE.md
- `feedback_X.md` — short description; destination section

### Project <repo>/CLAUDE.md
- `feedback_Y.md` — ...

## Memory → references/ (catalog content)
- `feedback_A.md` — destination: `~/dotfiles/claude/references/<name>.md`

## Delete from memory (duplicates / self-disclosed reinforcers)
- `feedback_B.md` — duplicates CLAUDE.md line N

## Delete from memory (volatile state per "no volatile state in memory" rule)
- `project_C.md` — answerable by git log / ls / re-query

## CLAUDE.md → memory demotions (facts that drifted into CLAUDE.md)
(usually empty or 1-2 borderline candidates)

## Dangling pointers
- `~/.claude/CLAUDE.md` line N references `<missing path>`

## Summary
- N promotions, M deletes, K dangling-fixes
- Estimated blast radius: low / medium / high
- Recommendation: action all / batch high-confidence first / hold for review
```

### Step 8 — Wait for direction

Do NOT auto-action the moves. Show the proposal table and let the user pick: full pass, high-confidence first pass, or specific items.

## Anti-patterns

- **Auto-editing CLAUDE.md without confirmation.** Always surface the proposal; let the user direct.
- **Treating frontmatter type as authoritative.** A `feedback_*.md` entry might be a fact-shaped reference (just mis-typed at creation); read the body before deciding.
- **Stopping at memory.** The bidirectional audit means scanning CLAUDE.md for facts too — don't skip Step 5 just because most demotion candidates fail.

## Related rules

- Global `~/.claude/CLAUDE.md` § "Memory Hygiene" — the facts/rules axis + no-volatile-state rule + promotion-candidate signals.
