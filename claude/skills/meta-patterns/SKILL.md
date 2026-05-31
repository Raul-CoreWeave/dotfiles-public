---
name: meta-patterns
description: Cross-session sentinel analyzer. Greps the Claude Code transcript archive (`~/.claude/projects/<slug>/*.jsonl`) for sentinels emitted by `/wtf` (and future `/gem`, `/landmine`, `/eureka`), clusters matches by `topic`, surfaces patterns occurring across ≥ N sessions, and recommends a promotion path (KB / memory / CLAUDE.md / skill-fix) per the existing three-tier hygiene framework. Closes the highest-leverage gap in the self-improvement loop — cross-session pattern detection that turns isolated session-level corrections into durable artifacts. Triggers on "/meta-patterns", "cross-session patterns", "recurring corrections", "what mistakes do I keep making", "find sentinels across sessions".
---

# /meta-patterns — cross-session sentinel analyzer

When the user wants to see recurring correction patterns across sessions, this skill greps the transcript archive for sentinels emitted by `/wtf` (and future sentinel-emitters), clusters by `topic`, and surfaces patterns that occur across multiple sessions — turning the per-session capture work into ambient cross-session signal.

Closes the highest-leverage gap in the self-improvement loop: **same-mistake-twice detection.** Without this, every `/wtf` capture lives in its own session's transcript and the second occurrence reads like a first.

## Why this exists

The `/wtf` skill captures corrections per-session and routes each to a durable artifact. But Claude's failure modes don't all manifest as obvious single-session bugs — many are recurring drift patterns where the same shape of mistake surfaces across weeks. The single-session capture catches each individually; only cross-session aggregation reveals the pattern.

Examples of what this skill would have caught earlier:
- Three `/wtf` captures with `topic=cli-flag-misnamed` across two months → strong signal to land the flag-semantics note as a CLAUDE.md rule, not just a one-off correction
- Five `/wtf` captures with `topic=stale-config-edit` → CLAUDE.md already has the rule; the recurring violations suggest the rule isn't being applied consistently → instrument or relocate

## Trigger

- `/meta-patterns` (defaults: `--since=90d`, `--sentinel=wtf`, `--min-occurrences=2`)
- `/meta-patterns --since=2026-04-01`
- `/meta-patterns --topic=cli-flag` (substring match on topic)
- `/meta-patterns --sentinel=all` (wtf + future gem/landmine/eureka)
- `/meta-patterns --min-occurrences=3` (raise the cluster threshold)
- `/meta-patterns -h` / `--help` (print help and exit)

## Phase 0: locate the transcript root

Default: `~/.claude/projects/<slug>/*.jsonl` where `<slug>` is the per-project transcript dir.

The user can override via `--root=<path>` if they want to grep a different archive (e.g., a backup, a different machine's mirror, a specific session dir).

## Phase 1: run the deterministic grep

Run `scripts/grep-sentinels.sh` with the user's filters:

```
bash scripts/grep-sentinels.sh \
  --since "$SINCE" \
  --sentinel "$SENTINEL" \
  [--topic-filter "$TOPIC"] \
  [--root "$ROOT"]
```

The script emits one JSON object per match to stdout:

```
{"file":"<path>","session":"<id>","ts":"<ISO-8601>","topic":"<kebab>","classified":"<class>","claim":"<one-line>"}
```

Implementation notes (in the script):
- Uses `rg -uu` to grep gitignored / hidden directories (transcript archives are typically excluded)
- Matches both raw (`"`) and JSON-escaped (`\"`) attribute forms because the marker tag itself is delimiter-free
- Surfaces parse errors as `{"file":...,"parse_error":...}` rather than crashing the pipeline

## Phase 2: cluster by topic

Group matches by `topic` field. For each cluster, compute:
- N = total occurrences (sentinels with this topic)
- M = distinct sessions (sentinels with this topic in unique `session` ids)
- latest_ts = most recent occurrence
- earliest_ts = first occurrence
- classifications = count of each `classified=` value within the cluster (consensus or split signal)
- representative_claim = the most recent `claim=` value (verbatim, for engineer recognition)

Drop clusters where `M < --min-occurrences` (default 2). Single-session sentinels are already captured at their original capture site; they don't need re-surfacing here unless the user explicitly lowers the threshold.

## Phase 3: render the report

For each surviving cluster, render:

```
### <topic>

- N occurrences across M sessions
- earliest: <ts> · latest: <ts> (<duration>)
- classification: <dominant> (<count>/<total>) <list-others-if-split>
- representative claim: "<verbatim from latest sentinel>"
- promotion recommendation: <see below>
```

Promotion recommendations follow the three-tier hygiene framework:

| Pattern | Recommendation |
|---|---|
| ≥ 3 sessions, all `classified=skill-bug`, same skill | The skill has a persistent failure mode. Run `/sync-skill-docs` + audit the skill's prompts for the gap. |
| ≥ 3 sessions, all `classified=kb-gap` | The KB / docs are missing canonical content. Run `/meta-lessons` to land it. |
| ≥ 3 sessions, all `classified=memory-rule` | Memory entry should exist + be graduating per `/meta-memory-audit`. If already in memory, the rule may need promotion to CLAUDE.md. |
| ≥ 3 sessions, all `classified=claude-md-rule` | Rule is either missing or being violated. If missing, draft + apply at narrowest scope. If present, audit its placement (is the scope right? is the rule findable from the relevant turn?). |
| Mixed classifications | The cluster's classification taxonomy may be wrong. Surface for engineer review; don't auto-promote. |

## Phase 4: surface + gate

Present the full report. No edits applied automatically. Each cluster shows its recommendation; the engineer chooses which to act on. Common follow-up moves:

- `apply cluster N` → execute the recommended skill (`/meta-lessons`, `/meta-memory-promote`, etc.) for that cluster
- `defer cluster N` → log as a todo for a later batch
- `dismiss cluster N` → mark as false-positive (the topic clusters were too coarse / the matches are unrelated)

`/meta-patterns` does NOT itself apply CLAUDE.md or KB edits — it surfaces patterns and routes to the existing single-edit skills. This keeps the apply-layer narrow and existing review-gates intact.

## Efficiency notes

- All grep is deterministic literal-substring; no LLM classification at grep time
- One rg pass over the transcript root regardless of cluster count
- jq processing is per-line, streamable
- Cluster aggregation is O(N) where N = sentinel count, not transcript size
- For a year of daily sessions × ~5 sentinels/session = ~1800 sentinels, expected runtime ≤ 2 seconds

## Scalability notes

- Topic taxonomy is open — new topics surface as new clusters automatically
- Sentinel format version (`v=1`) means future format changes can coexist with old captures via dual-pattern matching
- The script is the deterministic layer; the SKILL.md is the reasoning layer. Adding a new sentinel type (`/eureka`, `/landmine`) means: extend `grep-sentinels.sh --sentinel` enum + extend the promotion-recommendation table here. No transcript reprocessing required.
- Per-machine slug dependence is the one fragility — if the user moves machines, transcripts don't auto-mirror. Acceptable for v0; a cross-machine sync is a separate problem.

## Out of scope (v1+)

- Automatic promotion (apply edits without engineer review) — explicitly NO, would break the review-gate discipline
- Adversarial regression — running fresh-context sub-agents on the same prompts to detect rule-following drift
- Conflict detection across CLAUDE.md scopes — separate skill (`/meta-conflicts`)
- Rule-activation tracking (which CLAUDE.md rules I actually cite) — separate skill (`/meta-rules`)
- Hook-driven auto-capture when the user forgot `/wtf` — separate hook design

## Related

- `/wtf` — the sentinel emitter that produces the matches this skill consumes
- `/meta-memory-audit` / `/meta-memory-promote` — downstream for memory-rule clusters
- `/meta-lessons` — downstream for kb-gap clusters
- `/sync-skill-docs` — downstream for skill-bug clusters
