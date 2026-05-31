---
name: meta-context
description: Context-budget auditor for the Claude Code apparatus. Measures the bytes / lines / estimated tokens consumed by every surface that loads into a session at startup — CLAUDE.md scope tree (global + project + mode + @-imports), MEMORY.md auto-load, KB INDEX auto-loads, skill catalog (system-reminder injection), agent definitions, MCP server descriptions. Produces a categorized breakdown so the engineer can see where the budget is actually going before adding more. Complements `/meta-inventory` (which counts files) by measuring bytes-in-context. Triggers on "/meta-context", "context budget audit", "what's loading into my context", "context size breakdown", "how big is my CLAUDE.md".
---

# /meta-context — context-budget auditor

Measures what actually loads into the Claude Code context window at session start. CLAUDE.md scopes grow monotonically; the skill catalog grows with every new plugin; KB indexes get pulled in via `@~/...` autoloads. Without a budget measurement, "we're approaching cache-breaking thresholds" is a gut feeling.

Complements:
- `/meta-inventory` — counts files in the persistence graph; this skill measures bytes-in-context
- `/meta-rules` — measures behavioral usage of rules within CLAUDE.md scopes; this skill measures size of CLAUDE.md (and adjacent surfaces) regardless of usage
- `claude-md-improver` — audits structural quality; this skill audits size

The three together answer: how big is the apparatus, what's well-written, what's load-bearing.

## Why this exists

Three common growth trends over the lifetime of a Claude Code setup:
1. CLAUDE.md scopes grow in line count as rules accrete
2. The skill catalog grows as plugins and skills are added — each entry's `description:` loads at session start
3. New `@<path>` autoloads get added without removing old ones

Engineers don't naturally feel the per-byte cost of these additions until something breaks (cache misses, context-window pressure, slow session starts). A periodic budget snapshot makes the cost visible at decision time.

## Surfaces measured

Hardcoded list of surfaces that load at session start. Extending this list when new surface types are added is a documented v1 task.

| Surface | Path / source | How loaded |
|---|---|---|
| Global CLAUDE.md | `~/.claude/CLAUDE.md` | Always |
| Project CLAUDE.md | `<repo>/CLAUDE.md` | When CWD is inside a repo with one |
| Mode-symlinked CLAUDE.md | `<repo>/CLAUDE.<mode>.md` via symlink | When mode is active |
| Project @-imports | `@<path>` lines in any loaded CLAUDE.md | Recursive walk |
| MEMORY.md (auto-load) | `~/.claude/projects/<slug>/memory/MEMORY.md` | Always per project |
| Skill catalog (estimated) | sum of `description:` from all available SKILL.md files | System-reminder at session start |
| Agent catalog (estimated) | sum of `description:` from all `.claude/agents/*.md` | Per-spawn (not session-start) — measured for awareness |
| MCP server descriptions | `mcp.*` instruction blocks in system reminders | Always (server-provided) |

## Trigger

- `/meta-context` (defaults: current CWD's scope tree)
- `/meta-context --scope=global-only` (skip project)
- `/meta-context --json` (emit JSON instead of table — for piping into other tools)
- `/meta-context --growth=30d` (v1: compare to snapshot from N days ago)
- `/meta-context -h` / `--help`

## Phase 0: enumerate surfaces

Walk the CLAUDE.md scope tree:

1. Read `~/.claude/CLAUDE.md`. Find `@<path>` lines, add to the queue.
2. For each queued file, read it. Find `@<path>` lines (recursive), add to queue.
3. Continue until queue is empty. Deduplicate by canonical path.
4. Add `~/.claude/projects/<slug>/memory/MEMORY.md` for the current project.
5. Enumerate `~/.claude/skills/` + project `.claude/skills/` + plugin skill dirs; extract `description:` frontmatter from each SKILL.md.
6. Enumerate `~/.claude/agents/` + project `.claude/agents/`; extract `description:` from each.

Output: a list of `{category, path, bytes, lines, est_tokens}` records.

## Phase 1: measure

Run `scripts/measure-context.sh` against the enumerated surfaces:

```
bash scripts/measure-context.sh --enumerate > context-snapshot.jsonl
```

The script emits one JSON object per surface:

```
{"category":"claude-md","path":"...","bytes":18234,"lines":342,"est_tokens":4559}
```

Token estimation: `bytes / 4` rough heuristic. English prose averages ~4 bytes/token; technical content with code may be lower, prose-heavy may be higher. v0 accepts the heuristic; v1 could integrate a real tokenizer (tiktoken or the Anthropic SDK).

## Phase 2: aggregate + categorize

Group by `category`:
- `claude-md` (all CLAUDE.md files in the scope tree)
- `claude-md-import` (autoloaded `@<path>` content — typically KB INDEX files)
- `memory` (MEMORY.md auto-load)
- `skill-catalog` (sum of `description:` from all available skills)
- `agent-catalog` (sum of `description:` from all agents)
- `mcp` (MCP server instruction blocks — measured from connected servers)

Total = sum of all categories.

## Phase 3: render the report

Default table view (CLI-render-target width per global CLI render rule):

```
=== Context budget snapshot — 2026-05-20T15:30Z ===

Category              Bytes      Lines   Est-tokens   % total
─────────────────────────────────────────────────────────────
claude-md             68,234     1,196      17,058    14.2%
  global              18,234       342       4,559     3.8%
  project             21,456       398       5,364     4.5%
  mode                28,544       456       7,136     5.9%
claude-md-import      35,678       567       8,919     7.4%
  domain/INDEX.md     12,340       234       3,085     2.6%
  platform-doc        23,338       333       5,834     4.8%
memory                 9,876       148       2,469     2.1%
skill-catalog         45,678       678      11,420    23.8%
agent-catalog          8,234       123       2,058     4.3%
mcp                   12,034       189       3,008     6.3%
─────────────────────────────────────────────────────────────
TOTAL                179,734     2,901      44,932   100.0%

Anthropic prompt cache budget: ~200K tokens
Used: 44,932 (22.5% of cache)
Remaining: 155,068 (77.5%) for session content
```

Plus recommendations:

```
Largest categories:
  skill-catalog (23.8%) — review whether all skills earn their description-tokens cost.
                          Skills not used in 90+ days: see /meta-rules with --skill-mode.
  claude-md     (14.2%) — review for trimming candidates via /meta-rules (dead-weight rules).

Per-file outliers (>5K tokens):
  CLAUDE.<mode>.md (7,136 tokens)        — consider splitting mode-specific rules into ref/*.md
  platform-doc (5,834 tokens)            — consider per-domain INDEX restructuring
  project CLAUDE.md (5,364 tokens)       — review for KB-extractable content

Sanity checks:
  ✓ No surface > 25% of total (single point of bloat)
  ✓ Total < 50K tokens (well under cache budget)
  ⚠ skill-catalog is largest category — natural growth pattern; flag if it crosses 30%
```

## Phase 4: optionally write snapshot

If `--snapshot` is set, write the JSONL to `~/.claude/meta-context-snapshots/YYYY-MM-DD.jsonl` so future runs with `--growth=30d` can diff against historical state. v0 surfaces the report; the snapshot dir is created lazily on first `--snapshot` invocation.

## Efficiency notes

- One pass per surface file (wc + bytes); no LLM in the loop
- Skill catalog enumeration is a directory walk + frontmatter parse, fast
- Full run on a typical machine should complete in <2 seconds
- No transcript-archive scanning (unlike `/meta-rules` and `/meta-patterns`); this is purely current-state measurement

## Scalability notes

- Adding a new surface type means: extend the Phase 0 enumeration and the category list
- Token heuristic (bytes/4) is constant-cost; real tokenizer would add per-byte cost but stay sub-second
- Historical snapshot diffing scales with number of snapshots, not transcript size
- Cross-machine: each machine measures itself; no aggregation needed

## Limitations (v0)

- **Token estimation is approximate.** bytes/4 is the standard heuristic but actual tokens depend on content type. Off by ±20% for typical prose; worse for heavily-formatted markdown tables or code.
- **MCP instruction-block sizes are estimated** from local config, not measured from actual server-provided content. Real MCP instruction blocks may be larger.
- **No historical trending in v0.** Snapshot-and-diff is `--growth=30d` in v1.
- **Skill catalog measurement covers user-level + project-level + plugin skills.** It does NOT include any session-specific catalog augmentation (e.g., deferred-tool schemas loaded via ToolSearch mid-session).

## Out of scope (v1+)

- Real tokenizer integration (tiktoken / anthropic SDK)
- Historical snapshot diffing + growth charts
- Per-rule budget attribution (overlaps with `/meta-rules`)
- Cache-hit-rate measurement (requires harness instrumentation)
- Compaction-impact estimation (predict how much budget would be freed by a /compact)

## Related

- `/meta-inventory` — counts files in persistence graph; this skill measures bytes-in-context
- `/meta-rules` — measures behavioral usage within CLAUDE.md (whether the budget earns its cost)
- `claude-md-improver` — structural quality; this skill is size measurement
- Global `~/.claude/CLAUDE.md` § "Filesystem & KB architecture" — the persistence graph this skill measures
