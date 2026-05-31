---
name: meta-redundancy
description: Cross-primitive content-shape sensor for the persistence graph. Scans the action/reference stores (todos, memory) for content sitting in the wrong store — three defect classes: misplacement (right content, wrong store → MOVE), duplication (same content in two stores → DELETE one), lifecycle expiry (right store, outlived purpose → DELETE). A deterministic script narrows candidates + emits JSON; the LLM does the semantic shape-classification over the pointed-at content. Sensor-only by design — produces a routed proposal table for human review, never auto-moves. Distinct from /meta-conflicts (CLAUDE.md×CLAUDE.md rule overlap) and /meta-memory-audit (memory×CLAUDE.md fact-vs-rule); this covers the OTHER stores on the content-shape axis. Routes accepted candidates to the existing apply skills (/todo, /meta-lessons, /meta-memory-promote). Triggers on "/meta-redundancy", "misfiled content", "wrong store", "cross-primitive redundancy", "content in the wrong place", "todos that duplicate stored facts".
---

# /meta-redundancy — cross-primitive content-shape sensor

The persistence graph has many stores, each with a *content shape* that's
supposed to live there. The hygiene tiebreakers in CLAUDE.md (memory-vs-todo,
memory-vs-KB) define the right shape per store. Write-time discipline is
imperfect — especially across sessions and under time pressure — so content
drifts into the wrong store and accumulates silently. This sensor is the
periodic drift-catch: it automates those tiebreakers as a sweep.

This is **not** a redundancy-only scan. Three distinct defects need different
detectors and different fixes:

| Defect | Meaning | Fix verb |
|---|---|---|
| **Misplacement** | Content is fine, wrong store | **MOVE** |
| **Duplication** | Correct in store A, *also* copied in store B | **DELETE** one copy |
| **Lifecycle expiry** | Right store, outlived its purpose (volatile state) | **DELETE** |

The sensor classifies the defect and proposes the *direction*; the engineer
decides at the review-gate.

## Where it sits in the meta-* family

Three orthogonal cuts of "is this content in the right place":

```
/meta-conflicts      → CLAUDE.md × CLAUDE.md   (rule duplication)
/meta-memory-audit   → memory × CLAUDE.md      (fact-vs-rule promotion)
/meta-redundancy     → todos/memory/KB × each other   (content-shape misfit)   ← this
```

Together they cover the persistence graph. memory↔CLAUDE.md and
CLAUDE.md↔CLAUDE.md are explicitly **out of scope here** — they're the other
two sensors' lanes, and overlapping would re-create the very duplication this
family exists to prevent.

## Directed-edge detection table

Each misfile is a directed edge with its own signal + route. The script
detects the deterministic edges; the LLM judges the semantic ones.

| From → To | Signal | Defect | Detection | Route (apply skill) |
|---|---|---|---|---|
| memory → ∅ | volatile: "N commits ahead", "PR open/merged", dated "as of <date>" | expiry | **script** (confidence: review) | Write-delete (re-query, don't store) |
| memory → todo | imperative + future tense, no `**Why:**/**How to apply:**` scaffold | misplace | **LLM** | `/todo add` + rm memory file |
| memory → KB | universal fact, no first-person, grep-target under a repo `docs/` | misplace (durability promote) | **LLM** | `/meta-memory-promote` (KB variant) or `/meta-lessons` |
| memory ⇄ KB | same fact present in both | dup | **LLM** | rm memory (KB wins on ties per hygiene) |
| todo → KB | numbered procedure / "the canonical way to X is" prose | misplace (it's a playbook) | **LLM** | `/meta-lessons` |

Confidence reflects how much the script can judge alone: the script tags
volatile-marker hits `review` (can't distinguish volatile-state from a legit
anchor-pointer).

## Trigger

- `/meta-redundancy` (defaults: both stores)
- `/meta-redundancy --stores=memory` (limit to a subset)
- `/meta-redundancy --memory-slug=<slug>` (non-default project-memory dir)
- `/meta-redundancy -h` / `--help`

## Phase 0: deterministic narrowing

```
bash ~/.claude/skills/meta-redundancy/scripts/scan-stores.sh [flags] > scan.json
```

The script (a) emits deterministic misfile candidates it can judge alone, and
(b) emits `semantic_scan_targets` — pointers to the content the LLM must read
to judge the semantic edges. It does **not** classify the semantic edges and
does **not** dump full file bodies; it bounds its own output. Sub-second on the
typical store sizes.

## Phase 1: semantic shape-classification

For each entry in `scan.json.semantic_scan_targets`, read the pointed-at files
and apply the edge-specific shape test from its `instruction` field:

- **memory → todo**: a memory line in imperative mood + future tense, lacking
  the `**Why:**/**How to apply:**` scaffold a feedback/project entry carries,
  is action-shaped → propose move to a todo. (Provenance lines — "Decomposed
  from…", "promoted YYYY-MM-DD via…" — start with verbs but are NOT actions;
  don't flag them.)
- **memory → KB**: a `reference_*` or fact entry that's universal (no
  first-person, a sensible grep-target exists under a repo `docs/`) → propose
  KB promotion for durability.
- **memory ⇄ KB**: a fact already present in a KB file → propose deleting the
  memory copy (KB wins on ties per the hygiene tiebreaker).
- **todo → KB**: a todo body that's a numbered procedure or "canonical way to
  X" prose → propose moving the playbook to KB; the *action* (if any) stays as
  the todo.

Also re-judge the script's `review`-confidence deterministic candidates:
upgrade volatile-marker hits that are genuinely stored state ("N commits
ahead" describing current divergence) to `high`; downgrade legit anchor-pointer
hits ("canonical as of <date>" = a dated decision pointer, not volatile
state) to `false-positive`.

## Phase 2: render the report

Group by defect class, not by store (clamp to ~115 chars/row per the global
CLI render rule):

```
# /meta-redundancy — <YYYY-MM-DD HH:MM UTC>

## Misplacement (MOVE)
| # | From → To | Store/file:line | Why it's misfiled | Route |
|---|---|---|---|---|
| 1 | memory→todo | feedback_x.md:14 | imperative+future, no Why/How scaffold | /todo add + rm |

## Duplication (DELETE one)
| # | Stores | Anchor/fact | Which copy to drop | Route |

## Lifecycle expiry (DELETE)
| # | Store/file | Signal | Confirm-before | Route |

## False-positives (no action)
<script hits the LLM downgraded — surfaced so the engineer sees what was checked>

---
Scanned: todos, memory. Deterministic: K. Semantic: M.
```

## Phase 3: surface + gate

Present the report. **No moves applied automatically.** Per candidate:

- `apply <N>` → invoke the candidate's `route` apply skill (`/todo add`,
  `/todo trash`, `/meta-lessons`, `/meta-memory-promote`, or a Write-delete).
  The downstream skill's own consent flow fires.
- `defer <N>` → log as a todo for a later batch.
- `dismiss <N>` → mark false-positive (the signal over-fired).
- `re-route <N> <edge>` → override the LLM's edge classification.

`/meta-redundancy` never moves content itself — same sensor-vs-applier split
as `/meta-conflicts` and `/meta-memory-audit`. The MOVE/DELETE is always the
downstream skill's job, behind its own gate.

## Output contract

`scripts/scan-stores.sh` emits a single JSON object:

```
{
  "scanned_at": "<ISO-8601 UTC>",
  "stores_scanned": ["todos","memory"],
  "deterministic_candidates": [
    {"edge","defect","confidence","store","file","line","signal","match"?,"route"}
  ],
  "semantic_scan_targets": [
    {"store","dir"|"files","edges":[...],"instruction":"..."}
  ],
  "summary": {"deterministic_count","semantic_target_count","by_defect":{...}}
}
```

Exit 0 always on a completed scan (candidates may be empty); 2 on arg error /
missing dependency (`jq`, `rg`, `python3`).

## Composes with

- `/meta-memory-audit` — adjacent. That sensor decides memory-fact-vs-rule (→
  CLAUDE.md/KB promotion); this one decides memory-content-vs-store-shape.
  Both can flag the same memory file from different angles; the report notes
  the overlap when it happens.
- `/todo`, `/meta-lessons`, `/meta-memory-promote` — the appliers. This sensor
  proposes the route; they execute behind their gates.
- CLAUDE.md § "Cross-Session Persistence" (the decision tree + tiebreakers) and
  § "Memory Hygiene" — the source of truth for what shape belongs where. This
  skill is the enforcement sweep for those rules.

## Cadence

Not every session — too noisy. Run on-demand, or when a store crosses an
N-th-artifact review threshold in CLAUDE.md (e.g. 25 memory entries).

## Limitations (v0)

- **Deterministic edges are precision-tuned, low-recall.** The volatile-marker
  regex only catches the canonical phrasings ("commits ahead", "PR open", "as
  of <date>"); a volatile fact phrased differently slips through. Recall is the
  LLM semantic phase's job, not the script's.
- **No cross-store fact-similarity.** memory⇄KB duplication is judged by the
  LLM reading both; there's no embedding/keyword match to surface non-obvious
  duplicates. v1.

## Out of scope (v1+)

- Semantic fact-similarity (embedding/keyword) to catch non-obvious memory⇄KB
  and todo⇄todo duplication beyond literal-anchor match.
- ledger (`*.jsonl`) shape-checking — structured-event stores have a fixed
  schema; misfile risk is low, deferred.
- Bidirectional MOVE execution inside this skill (stays sensor-only by design).

## Related

- `/meta-conflicts` — sibling sensor; CLAUDE.md rule overlap.
- `/meta-memory-audit` — sibling sensor; memory fact-vs-rule axis.
- CLAUDE.md § "Cross-Session Persistence" → decision tree + tiebreakers — the
  rules this sensor enforces.
