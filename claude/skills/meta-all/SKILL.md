---
name: meta-all
description: Apparatus-wide audit orchestrator. Runs the meta-* sensors in sequence — inventory + lint, context-budget, cross-scope conflicts, rule activation, memory facts-vs-rules, cross-primitive content-shape, execution-layer placement, cross-session correction patterns — and produces a single consolidated report grouped by finding class (structural debt / promotion candidates / dead-weight / overdue). Read-only by default; `--act` opens per-candidate review-gates for `meta-memory-promote`. Writes a completion timestamp to `~/.local/share/claude-meta/last-meta-all` for the session-end overdue-flag rule in global CLAUDE.md § "Cross-Session Persistence" → Rule C. Triggers on "/meta-all", "audit my apparatus", "meta audit", "run the meta sensors", "apparatus health check".
---

# /meta-all — apparatus audit orchestrator

Single entry point that chains the eight read-only `meta-*` sensors into one
audit pass with a consolidated report. Phased-orchestrator shape: phased
execution, optional `--skip-*` flags, one review-gate at the end for any
mutating action.

The eight `meta-*` skills are orthogonal sensors over the same surface
(apparatus health = primitives + persistence + CLAUDE.md scopes +
memory + transcript archive). Running them ad-hoc means juggling eight
mental triggers and eight separate output reads. This orchestrator
collapses that into one invocation, one report, one decision moment.

## What it composes

| Phase | Skill | What it surfaces |
|---|---|---|
| 1 | `meta-inventory` | Primitives count + persistence-graph dangling-refs + untracked-in-versioned-roots orphans |
| 2 | `meta-context` | Bytes/lines/tokens loaded into session start; CLAUDE.md size trends |
| 3 | `meta-rules` | CLAUDE.md rule activation (cite counts, dead-weight candidates, orphan citations) |
| 4 | `meta-conflicts` | Cross-scope CLAUDE.md collisions, near-duplicates, body overlaps |
| 5 | `meta-memory-audit` | Memory entries that are rules (→ CLAUDE.md candidates) or facts (→ KB candidates) |
| 5.5 | `meta-redundancy` | Content in the wrong store across todos/watchlists/memory — misplacement / duplication / lifecycle expiry |
| 5.6 | `meta-layering` | Logic at the wrong execution layer — deterministic glue described for the LLM to hand-run inside a skill that a `scripts/*.sh` should own (Class A, under-scripted) |
| 6 | `meta-patterns` | Cross-session `/wtf` sentinel clusters → durable-artifact candidates |

`meta-memory-promote` is the only mutating sensor; **excluded by default**.
Opt in via `--act` and only after the audit surfaces promotion candidates
the user explicitly accepts (per-candidate review-gate).

## Phase ordering

Sequential, not parallel. Two reasons:
1. Token budget — eight parallel meta-* invocations would flood context with
   intermediate outputs before the synthesis step can read them. The
   orchestrator reads each phase's structured output, summarizes, and only
   carries forward the synthesis-relevant fields.
2. Cache reuse — phases 3 and 4 both call `meta-rules`' extraction script
   (`extract-rules.sh`); running them sequentially lets phase 4 reuse phase
   3's cached extraction. The reuse handoff is documented in `meta-conflicts/SKILL.md`.

Order is chosen so each phase's output feeds the next when useful:
inventory first (foundation for "what exists"), context next (cheap
byte-count snapshot), rules → conflicts (shared extraction), memory →
redundancy → layering → patterns (the placement-hygiene sensors cluster —
memory-audit on the fact/rule axis, redundancy on the content-shape/wrong-store
axis, layering on the execution-layer/wrong-layer axis, then patterns on the
transcript archive; all surface durable-artifact or cleanup candidates that
get grouped in the final report).

## Inputs

`$ARGUMENTS` is zero-or-more of:

| Flag | Effect |
|---|---|
| `--skip-inventory` | Skip phase 1 |
| `--skip-context` | Skip phase 2 |
| `--skip-rules` | Skip phase 3 |
| `--skip-conflicts` | Skip phase 4 |
| `--skip-memory` | Skip phase 5 |
| `--skip-redundancy` | Skip phase 5.5 |
| `--skip-layering` | Skip phase 5.6 |
| `--skip-patterns` | Skip phase 6 |
| `--lessons` | Add Phase 6.5 — invoke `/meta-lessons --dry-run` to surface session-lesson candidates alongside the audit findings. Off by default (most `/meta-all` runs are mid-session apparatus checks, not session-end). |
| `--act` | After the report, open per-candidate review-gates for `meta-memory-promote` candidates surfaced by phase 5 |
| `--quiet` | Suppress per-phase progress lines; output the consolidated report only |
| `-h` / `--help` | Print this matrix and exit |

Default (no flags): run all eight read-only phases (1, 2, 3, 4, 5, 5.5, 5.6, 6),
surface report, write timestamp, exit. No mutations.

## Execution

### Phase 0 — preamble

1. Acknowledge start: `Starting /meta-all — N phases ...` (skip if `--quiet`).
2. `mkdir -p ~/.local/share/claude-meta` (state dir for completion timestamp).
3. Initialize an in-context findings buffer: a list of `{phase, severity, category, summary, detail_link?}` records.

### Phase 1–6 (incl. 5.5, 5.6) — invoke each meta-* sensor

Phase 5.5 (`meta-redundancy`) and Phase 5.6 (`meta-layering`) are default-on,
unlike the opt-in Phase 6.5 (`meta-lessons`); the `.5`/`.6` denote insertion
order, not opt-in status. For each non-skipped phase:

1. Invoke the corresponding skill via the Skill tool, passing args appropriate
   to the sensor (most accept zero args; pass through any user-specified
   sensor-specific args if provided).
2. Read the sensor's structured output. The meta-* skills are sensor-only —
   they surface candidates as tables, never auto-edit. Parse the table into
   per-finding records.
3. Append findings to the buffer with phase tag.
4. Surface a one-line per-phase status (skip if `--quiet`):
   `Phase N (<sensor>): K findings (<top category breakdown>)`

### Phase 6.5 — `--lessons` session-lesson capture (opt-in only)

If `--lessons` flag passed, after Phase 6 and before Phase 7:

1. Invoke `/meta-lessons --dry-run` via the Skill tool.
2. Read its proposal table — one entry per lesson candidate with class
   (rule / fact-universal / fact-user) and destination.
3. Add each candidate to the findings buffer with phase tag `meta-lessons`
   and category `lesson-candidate`.
4. Surface a one-line status (skip if `--quiet`):
   `Phase 6.5 (meta-lessons): K candidates (<rule/fact-universal/fact-user breakdown>)`

Per `/meta-lessons`'s own design, `--dry-run` mode surfaces candidates
without applying — the user runs `/meta-lessons` (without flags)
explicitly later to apply. The `/meta-all` consolidated report includes
them under the **Promotion candidates** section alongside memory-audit
and patterns findings.

### Phase 7 — consolidated report

Synthesize the buffer into a single report grouped by **finding class**, not
by phase:

```
# /meta-all audit — <YYYY-MM-DD HH:MM UTC>

## Structural debt
<inventory's dangling-refs, orphan untracked, context-budget over-threshold,
 conflicts' near-duplicates ranked by severity,
 redundancy's misplacement candidates (content in the wrong store → MOVE)>

## Promotion candidates
<memory-audit's rule-shaped entries, patterns' multi-session clusters,
 redundancy's memory→KB / todo→KB candidates (durability promotes),
 grouped by proposed destination (CLAUDE.md scope / KB file)>

## Dead-weight candidates
<rules' zero-cite sections, memory-audit's stale entries, patterns'
 superseded sentinels, redundancy's duplication (DELETE one copy) +
 lifecycle-expiry (stale watchlists, volatile memory) candidates>

## Overdue / drift signals
<orphan citations to deleted rules, untracked work in versioned roots,
 CLAUDE.md scope size growth above threshold>

## No-finding phases
<list the phases that returned clean>

---
Last `/meta-all`: <timestamp>. Next recommended: <30 days from now>.
Run `/meta-all --act` to open review-gates for promotion candidates.
```

Group ordering rationale: **structural debt first** (broken refs cause
silent failures and should be fixed before anything depends on them);
**promotion candidates second** (highest-leverage action — converting
isolated learnings into durable artifacts); **dead-weight third**
(token-budget pressure, lower urgency); **overdue/drift last**
(awareness, no action required this run).

### Phase 8 — `--act` review-gates (opt-in only)

If `--act` AND any promotion candidates surfaced in phase 5:

1. For each candidate, present the proposal (memory entry → CLAUDE.md
   destination + draft text) via interactive consent (`AskUserQuestion` or
   direct prompt). One candidate at a time. Default-no.
2. On accept, invoke `meta-memory-promote` for that single candidate.
3. After all candidates resolved, surface a summary: `Promoted: N. Skipped: M.`

`--act` does NOT apply phase 1's untracked-file fixes, phase 4's
conflict consolidations, or phase 6's pattern promotions automatically.
Those have their own existing skills with their own consent models;
they live outside the orchestrator's mutation surface by design.

### Phase 9 — timestamp write

Always (even on partial-skip runs):

```bash
date -u +%Y-%m-%dT%H:%M:%SZ > ~/.local/share/claude-meta/last-meta-all
```

This timestamp is read by the session-end footer in global CLAUDE.md §
"Cross-Session Persistence" → Rule C to surface the overdue flag when
`/meta-all` hasn't run in >30 days.

## Output contract

| Surface | Shape |
|---|---|
| Per-phase status (stdout, unless `--quiet`) | One line per phase, terse |
| Consolidated report (always) | Markdown, sections per finding class |
| `~/.local/share/claude-meta/last-meta-all` | ISO-8601 UTC timestamp, one line |
| Side-effect on `--act` | Per-candidate edits via `meta-memory-promote`'s own consent flow |

The orchestrator does NOT write a report file. The output is in-conversation
only — each sub-sensor may write its own detail file (e.g.,
`meta-inventory` writes a dated architecture-inventory doc).
The consolidated report references those sub-sensor detail files when present.

## Composes with

- A modern-tooling-audit cloud routine (if configured) — that surfaces
  modern-tooling drift; this orchestrator surfaces apparatus drift.
  Different signals, complementary cadences.
- Session-end footer (global CLAUDE.md § "Cross-Session Persistence" → Rule
  C) — reads `~/.local/share/claude-meta/last-meta-all` and surfaces
  "overdue: N days" when stale.
- `claude-md-management:claude-md-improver` — the editor for findings
  surfaced by phases 3 / 4. The orchestrator surfaces; the improver edits.

## Pitfalls

- **Don't run with `--act` blind.** Phase 5's promotion candidates need
  human classification. The `--act` gate is per-candidate for a reason.
- **Skipping phases shifts the consolidated grouping.** A `--skip-rules`
  + `--skip-conflicts` run produces a report missing the dead-weight
  section entirely — note the skips in the report header.
- **`meta-patterns` requires N sessions of /wtf sentinel history.** On a
  fresh machine the phase will return empty; that's not a bug.
- **Timestamp write is unconditional.** Even a `--skip-inventory --skip-context
  --skip-rules --skip-conflicts --skip-memory --skip-patterns` (all-skip)
  run writes the timestamp — that's a documentation gap to fix in v2;
  for v1, don't all-skip.
- **Don't substitute for the individual sensors.** When the question is
  narrow ("what's loading into my context right now?"), invoke
  `/meta-context` directly. `/meta-all` is for the *periodic sweep*, not
  the targeted query.
