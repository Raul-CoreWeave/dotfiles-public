---
name: meta-rules
description: CLAUDE.md rule-activation tracker. Extracts section headers from all in-scope CLAUDE.md files (global, project), greps the Claude Code transcript archive for literal-string citations of those headers, and produces a per-rule usage signal (cite_count, last_cite_ts, distinct_sessions). Surfaces dead-weight candidates (zero cites in N days), proven load-bearing rules (high cite-frequency), and orphan citations (text references to rules that no longer exist). Designed as a SENSOR — feeds usage data to a CLAUDE.md editor, CLAUDE.md authors, and humans deciding what to trim or relocate. Triggers on "/meta-rules", "rule activation tracking", "which CLAUDE.md rules do I actually use", "dead-weight rules", "scan rule usage".
---

# /meta-rules — CLAUDE.md rule-activation tracker

Measures dynamic behavioral usage of CLAUDE.md rules across sessions. Complement to a structural CLAUDE.md auditor — that kind of skill audits *structural quality* (template adherence, currency, conciseness); this skill measures *whether the rules actually fire in practice*.

A rule can be perfectly written, current, and well-placed — and still be dead weight if Claude never cites or applies it. Without instrumentation we can't distinguish load-bearing rules from artifact rules. This skill closes that gap.

## Why this exists

CLAUDE.md scopes grow monotonically — we add rules but rarely subtract. The accumulated context cost is real (every line loads into every session that touches the scope), but we have no data on which rules earn their place. By default, "is this rule load-bearing?" is decided by gut feel.

A clean cite-count signal turns the decision into: keep rules with N+ cites/quarter; review rules with zero cites; restructure rules with high violation count (cited via `/wtf` rather than positively-applied).

Pairs with:
- `/wtf` (real-time correction sentinel — surfaces rule violations)
- `/meta-patterns` (cross-session correction pattern detection)

## How citation tracking works (v0)

Section headers in CLAUDE.md are the **deterministic citation target**. When Claude applies a rule, it typically cites the section by name — `per CLAUDE.md § Memory Hygiene`, `per the global "Surface changes outside CWD" rule`, etc. The skill extracts all section headers from in-scope CLAUDE.md files, then greps the transcript archive for literal-string matches.

This is **high-precision, lower-recall** by design:
- High precision — citing a section header that doesn't exist is rare
- Lower recall — silently-applied rules (no citation) don't count; this is a coarse signal, not an absolute

For v0 we accept the recall gap. Future work: distinctive-phrase extraction from rule bodies for second-level grep.

## Trigger

- `/meta-rules` (defaults: `--since=90d`, `--threshold-dead=0`, `--threshold-busy=10`)
- `/meta-rules --since=2026-01-01`
- `/meta-rules --scope=global` (filter to one CLAUDE.md scope)
- `/meta-rules --rule="Memory Hygiene"` (filter to one rule by section-header substring)
- `/meta-rules --dead-only` (only surface zero-cite rules)
- `/meta-rules --busy-only` (only surface high-cite-frequency rules — proves load-bearing)
- `/meta-rules -h` / `--help`

## Phase 0: locate in-scope CLAUDE.md files

Enumerate the CLAUDE.md scope tree by walking imports:

1. **Global**: `~/.claude/CLAUDE.md` (may symlink to `~/dotfiles/claude/CLAUDE.md`)
2. **Imports**: follow any `@./<path>` / `@~/<path>` imports from the global file
3. **Project**: if CWD is inside a repo with a `CLAUDE.md`, include it
4. **Project autoloads**: any `@<path>` imports from the project CLAUDE.md

Each file goes into the rules.jsonl as a separate `scope`.

## Phase 1: extract rules

Run `scripts/extract-rules.sh` against each in-scope CLAUDE.md file:

```
bash scripts/extract-rules.sh ~/.claude/CLAUDE.md > rules-global.jsonl
bash scripts/extract-rules.sh <repo>/CLAUDE.md > rules-project.jsonl
# ... etc
```

The script emits one JSON object per section header found:

```
{"scope":"global","file":"...","header":"Memory Hygiene","level":2,"line":234,"body_preview":"How to write and..."}
```

Section headers at `##` and `###` levels are tracked; `####` and deeper are skipped (typically sub-points of a rule, not the rule itself).

## Phase 2: grep citations

Build a patterns file (one section header per line) and run `scripts/grep-citations.sh` against the transcript archive:

```
jq -r '.header' rules-all.jsonl > patterns.txt
bash scripts/grep-citations.sh --patterns patterns.txt --since "$SINCE"
```

The script uses `rg -F -f patterns.txt` for single-pass literal-string matching across `~/.claude/projects/<slug>/*.jsonl`. Emits one JSON object per match:

```
{"file":"...","session":"sess-abc","ts":"2026-05-20T...","matched_header":"Memory Hygiene","context_line":"<text 80 chars around match>"}
```

The timestamp is approximated from the transcript JSONL line's timestamp field (per session-id mapping), or derived from filename if not available.

## Phase 3: aggregate

Join rules with citations on `header`. For each rule compute:
- `cite_count` — total citations across sessions
- `distinct_sessions` — count of distinct session ids
- `last_cite_ts` — most recent citation timestamp
- `first_cite_ts` — earliest citation timestamp
- `cite_frequency` — distinct_sessions / total_sessions_in_window (gives a "applied in N% of sessions" signal)

Categorize each rule:

| Category | Definition | Signal |
|---|---|---|
| `dead` | cite_count == 0 in window | candidate for trim or relocate |
| `cold` | cite_count between 1 and `--threshold-dead` (default: leave at 0 → no cold tier) | review for restructuring or scope move |
| `warm` | cite_count between `--threshold-dead+1` and `--threshold-busy` | normal, load-bearing |
| `busy` | cite_count >= `--threshold-busy` | proven essential; protect from trimming |

## Phase 4: surface report

Render a per-scope table (efficiency: clamp row width to ~115 chars per the CLI render rule in global CLAUDE.md):

```
### CLAUDE.md scope: global (~/.claude/CLAUDE.md)

| Rule | Cites | Last cite | Category |
|---|---|---|---|
| Memory Hygiene | 47 | 2026-05-19 | busy |
| Surface changes outside CWD | 18 | 2026-05-18 | warm |
| Bundle stage + verify + commit | 11 | 2026-05-20 | warm |
| Cross-Session Persistence | 0 | (never) | dead |
| ... | ... | ... | ... |

Dead-weight candidates: 4 rules with zero cites in 90d
  - Cross-Session Persistence
  - ...

Recommended actions:
  - Audit dead candidates to confirm structural relevance
  - Consider trimming or relocating dead candidates to a references/ directory
```

No auto-edits. The report feeds engineer judgment.

## Phase 5: handoff to editor (v1.1+)

A CLAUDE.md editor can consume a JSON usage signal as an extra scoring dimension: **Usage** (15 points). Mapping:

| Cite frequency | Usage score |
|---|---|
| Dead (0 cites in window) | 0 |
| Cold (1-2 cites) | 5 |
| Warm (3-9 cites) | 10 |
| Busy (10+ cites) | 15 |

v0 does NOT produce this JSON; v0 surfaces the human report and stops.

## Efficiency notes

- Rule extraction: one pass per CLAUDE.md file, fast (sub-100ms per file)
- Citation grep: single `rg -F -f patterns.txt` pass over transcript archive — fixed-string matching is optimal in rg
- Aggregation: jq pipeline, O(citations + rules)
- For ~50 rules × ~1800 transcript matches expected over 90 days, full pipeline runs in <5 seconds

## Scalability notes

- Adding a new CLAUDE.md scope means adding it to the Phase 0 enumeration; everything else flows
- Adding a new citation pattern (beyond section-header) means extending `grep-citations.sh` — new pattern + new dedup logic in aggregator
- Transcript size grows with usage; the script reads JSONL line-by-line so memory stays bounded
- Cross-machine: per-machine transcript means per-machine signal; multi-machine aggregation is a separate problem

## Limitations (v0)

- **Citation grep is high-precision, low-recall** by design. Rules applied without citation don't count. Signal is directional, not absolute.
- **Section-header-only** — distinctive-phrase matching from rule bodies is v1+.
- **No violation tracking** — `/wtf` sentinels with `classified=claude-md-rule` are the violation signal; this skill doesn't cross-reference them yet. v1+.
- **No historical trending** — single-snapshot report, no "vs 30 days ago" comparison. Would need snapshot persistence; v1+.

## Out of scope (v1+)

- Auto-application of trim recommendations (would break review-gate discipline)
- Body-text distinctive-phrase extraction
- Cross-reference with `/wtf` sentinels classified as `claude-md-rule` for violation tracking
- Snapshot persistence + trend analysis
- Memory-entry usage tracking (similar shape, applies to `~/.claude/projects/<slug>/memory/`)

## Related

- `/wtf` + `/meta-patterns` — capture violations / corrections, which this skill could cross-reference in v1
- `~/.claude/CLAUDE.md` § "Memory Hygiene" — the framework distinguishing rules from facts; this skill measures rules (and rule-shaped facts)
