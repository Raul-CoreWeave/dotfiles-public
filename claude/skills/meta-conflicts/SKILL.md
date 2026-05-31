---
name: meta-conflicts
description: Cross-scope CLAUDE.md conflict detector. Extracts rules from all in-scope CLAUDE.md files (global, project, mode) and surfaces header collisions, near-duplicate headers, and body overlaps — candidate cases where the same topic is covered in multiple scopes (consolidate / intentional-override / contradict / complement / false-positive). Sensor-only by design — produces a classification proposal table for human review, never auto-edits. Composes with `/meta-rules` (reuses extract-rules.sh) and feeds `claude-md-improver` for the edit phase. Triggers on "/meta-conflicts", "conflicting CLAUDE.md rules", "duplicate rules across scopes", "scope contradictions", "find rule overlap".
---

# /meta-conflicts — cross-scope CLAUDE.md conflict detector

CLAUDE.md scopes grow independently. Rules added to global may already exist in a project scope, or contradict a project-level override, or duplicate a sibling scope's content. Without active detection these accumulate silently — the inconsistency only surfaces when an engineer (or Claude) tries to apply both rules and discovers they disagree.

This skill surfaces the candidates. The actual resolution (consolidate / override / contradict / complement / false-positive) is a judgment call left to the engineer, with the bodies side-by-side for inspection.

## Composes with

- `/meta-rules` — reuses `extract-rules.sh` for the rule extraction step. The conflict detection is a different aggregation over the same primitive.
- `claude-md-improver` — the editor. Once a conflict is classified, this skill recommends which scope's content to keep / merge / rewrite; `claude-md-improver` applies the edit.
- `/meta-context` — adjacent. /meta-context measures size of each scope; /meta-conflicts measures overlap between scopes.

## Conflict taxonomy

| Class | Definition | Resolution |
|---|---|---|
| `duplicate` | Same header AND substantially-same body across two scopes | Remove from the broader scope OR the narrower; keep the canonical |
| `intentional-override` | Same header but body differs; narrower scope intentionally overrides broader | Document the override; ensure narrower scope is loaded after broader |
| `contradiction` | Same header, bodies prescribe opposing actions | Resolve via human judgment; pick one and trim the other |
| `complement` | Same header, bodies cover different facets of the same topic | Merge into a single canonical entry (typically in the broader scope) |
| `false-positive` | Header collision but unrelated content (e.g., generic "Usage" appearing in multiple files) | Tag and ignore; no action needed |

The classification is the LLM's job. The script's job is to find candidates.

## Trigger

- `/meta-conflicts` (defaults: all in-scope CLAUDE.md files; canonical-header-match)
- `/meta-conflicts --scope=global,project` (limit to specific scope pairs)
- `/meta-conflicts --include-similar` (also surface near-duplicates via Levenshtein on canonicalized headers)
- `/meta-conflicts --threshold=2` (minimum scope count for a collision to surface; default 2)
- `/meta-conflicts -h` / `--help`

## Phase 0: extract rules from all scopes

Reuses `/meta-rules` extraction:

```
{
  bash ~/.claude/skills/meta-rules/scripts/extract-rules.sh ~/.claude/CLAUDE.md --scope=global
  bash ~/.claude/skills/meta-rules/scripts/extract-rules.sh <project>/CLAUDE.md --scope=project
  bash ~/.claude/skills/meta-rules/scripts/extract-rules.sh <project>/CLAUDE.<mode>.md --scope=mode
  # ... etc per scope tree
} > all-rules.jsonl
```

This avoids re-implementing extraction. Both skills evolve together; if `/meta-rules` improves recall (e.g., body-distinctive-phrase extraction in v1), `/meta-conflicts` inherits.

## Phase 1: find header collisions

Run `scripts/find-collisions.sh < all-rules.jsonl`:

```
bash scripts/find-collisions.sh < all-rules.jsonl > collisions.jsonl
```

The script:
1. Groups rules by **canonical header** (lowercase, strip punctuation, collapse whitespace, sort words)
2. Surfaces groups with `≥ --threshold` entries (default 2)
3. Emits one JSON object per collision group:

```
{
  "canonical": "memory hygiene",
  "occurrences": 2,
  "scopes": ["global", "project"],
  "entries": [
    {"scope":"global", "header":"Memory Hygiene", "body_preview":"...", "file":"...", "line":234},
    {"scope":"project", "header":"Memory Hygiene", "body_preview":"...", "file":"...", "line":456}
  ]
}
```

When `--include-similar` is set, also group by Levenshtein-similarity ≤ 2 on canonical headers (catches "Memory Hygene" typo + "memory hygiene" + "Memory-Hygiene"). v0 default OFF (exact-canonical only); turn on when sweeping.

## Phase 2: classify each collision

For each collision group from Phase 1, the LLM reads the bodies side-by-side and classifies into one of the five taxonomy categories. Specific prompts to apply:

- **duplicate test**: do the bodies say substantially the same thing? Token-by-token comparison is too strict — focus on whether a reader following one body would behave identically to a reader following the other. Yes → `duplicate`.
- **override test**: same topic, different prescriptions, with narrower scope's prescription being more specific or more restrictive? Yes → `intentional-override`. The narrower scope's rule overrides the broader; both can coexist as long as the narrower is loaded after.
- **contradiction test**: same topic, conflicting prescriptions, neither obviously supersedes? Yes → `contradiction`. This is the highest-priority class — needs explicit resolution.
- **complement test**: same topic but bodies cover different facets that don't overlap? Yes → `complement`. Suggest merging.
- **false-positive**: do the bodies share a header label but address unrelated topics? (Generic labels like "Usage", "References", "Tips" are common offenders.) Yes → `false-positive`. Surface anyway in case the user wants to rename for clarity, but don't recommend action.

## Phase 3: render the report

Per-collision-group output (clamp to ~115 chars / row per global CLI render rule):

```
### Collision: "Memory Hygiene" (2 occurrences)

| Scope | File | Line | Body preview |
|---|---|---|---|
| global | ~/.claude/CLAUDE.md | 234 | How to write and maintain... |
| project | <project>/CLAUDE.md | 456 | Project-specific learning routing... |

**Classification**: intentional-override (high confidence)
**Reasoning**: global covers the framework; the project scope specializes to its domain learning routing. Both load in sequence; narrower extends broader.
**Recommended action**: keep both; ensure the project scope doesn't restate the framework (currently it doesn't — references back to global).
```

For contradictions:

```
### Collision: "Branch defaults" (2 occurrences) — CONTRADICTION

| Scope | File | Body preview |
|---|---|---|
| global | ~/.claude/CLAUDE.md | "Always branch before editing a git repo..." |
| project | <project>/CLAUDE.md | "For long-lived working branches, prefer rebase..." |

**Classification**: complement (medium confidence)
**Reasoning**: global covers the always-branch rule; the project scope covers the sync-with-main flow on existing long-lived branches. Different lifecycle phases.
**Recommended action**: clarify in the project scope that the always-branch rule still applies on first edit; the rebase guidance is for subsequent syncs.
```

## Phase 4: surface + gate

Present the full report. No edits applied automatically.

The engineer chooses per group:
- `apply <N>` → invoke `claude-md-management:claude-md-improver` against the named scope(s) with the recommended action
- `defer <N>` → log as P2 in a todo category for a later batch
- `dismiss <N>` → mark as false-positive (the canonical grouping was too coarse)
- `re-classify <N> <class>` → override the LLM's classification

`/meta-conflicts` does NOT itself apply CLAUDE.md edits — same sensor-vs-editor split as `/meta-rules`.

## Efficiency notes

- Reuses extract-rules.sh: extraction cost is amortized across /meta-rules + /meta-conflicts
- Collision detection is O(rules × distinct-canonical-headers) — jq pipeline, sub-second for ~100 rules
- Classification phase is LLM-driven and scales with collision count, not total rules
- Expected runtime: <2s for the script; ~30s for the LLM classification on ~5 collisions

## Scalability notes

- Adding a new CLAUDE.md scope means: include it in the Phase 0 extraction list — everything else flows
- Adding a new conflict class means: extend the classification prompts in Phase 2 — no script change
- `--include-similar` makes the comparison fuzzier but quadratic; default OFF for that reason

## Limitations (v0)

- **Header-based collision detection only.** Two rules with completely different headers but conceptually identical content (e.g., "Memory Hygiene" vs "Persistent State Rules") would not be detected. Body-keyword overlap is v1.
- **Canonical form is lossy.** "Memory Hygiene" and "Memory Hygiene Framework" canonicalize differently; they may be the same topic.
- **No body diff visualization.** v0 shows previews; v1 could integrate side-by-side diff for the engineer to read.
- **Classification confidence is LLM-judgment.** No ground-truth labels yet; rely on the engineer's review-gate.

## Out of scope (v1+)

- Body-keyword overlap detection (semantic similarity beyond header match)
- Side-by-side body diff render (visualization for the engineer)
- Auto-resolution of `duplicate` class (would break review-gate)
- Cross-reference with `/wtf` sentinels — a user-flagged correction whose claim contradicts an existing CLAUDE.md rule is a signal the rule may be the problem
- Memory ↔ CLAUDE.md cross-conflict detection (memory entry duplicates a CLAUDE.md rule)
- Skill-description ↔ CLAUDE.md conflict (skill says X, rule says don't-X)

## Related

- `/meta-rules` — sibling sensor; measures rule usage. This skill measures rule overlap.
- `/meta-context` — sibling sensor; measures rule budget.
- `claude-md-management:claude-md-improver` — the editor consuming the classification proposal.
- `/meta-inventory` dangling-refs lint — adjacent (detects broken cross-references; this skill detects duplicate or conflicting authored content).
- Global `~/.claude/CLAUDE.md` § "Memory Hygiene" — promotion criteria for memory → CLAUDE.md; this skill catches scope-mismatch errors in those promotions.
