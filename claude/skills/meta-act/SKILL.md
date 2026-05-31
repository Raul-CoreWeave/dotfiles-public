---
name: meta-act
description: Pattern-resolution orchestrator that closes the loop /meta-patterns opens. Reads top recurring /wtf sentinel clusters, classifies each cluster's corrective shape (skill-bug / kb-gap / memory-rule / claude-md-rule) per the sentinel's own classification field, drafts the appropriate artifact, opens a per-cluster review-gate, and applies via the right downstream skill (a KB-fix skill for KB, /meta-edit for CLAUDE.md, Write for memory entry, Edit for skill bugfix). Closes the "we have a recurring pattern but no resolution" gap. Triggers on "/meta-act", "act on patterns", "resolve recurring corrections", "promote cluster patterns", "land /wtf clusters".
argument-hint: "[--top=N] [--cluster=<topic>] [--dry-run] [--min-occurrences=N]"
---

# /meta-act — pattern-resolution from /meta-patterns clusters

`/meta-patterns` surfaces recurring `/wtf` sentinel clusters across sessions
but is sensor-only — it doesn't write artifacts. This orchestrator reads the
clusters and drafts + applies the corrective artifact per cluster's
classification.

## Why this exists

The self-improvement loop today:
1. Engineer runs `/wtf` → sentinel captured + classified at capture time
2. `/meta-patterns` clusters sentinels by topic across sessions
3. `/meta-patterns` recommends a promotion path per cluster
4. **GAP: engineer manually drafts + applies the corrective artifact**
5. Cluster resolved; future occurrences don't surface (or do but should be
   re-classified as not-applicable)

Step 4 is currently manual. The classification at step 1 already encodes
the corrective shape (`skill-bug` / `kb-gap` / `memory-rule` /
`claude-md-rule`). This orchestrator reads that classification and routes
to the right downstream skill — turning step 4 into one review-gate per
cluster rather than per-sentinel manual work.

## Inputs

| Arg | Meaning |
|---|---|
| `--top=<N>` | Process top N clusters by occurrence count (default 5) |
| `--cluster=<topic>` | Process one specific cluster by topic slug |
| `--min-occurrences=<N>` | Skip clusters with fewer than N occurrences (default 3 — single-session occurrence isn't a pattern yet) |
| `--dry-run` | Surface draft artifacts; skip the apply phase |
| `--class=<value>` | Filter to one classification: `skill-bug`/`kb-gap`/`memory-rule`/`claude-md-rule` |

## Phases

### Phase 1 — fetch clusters (/meta-patterns)

Invoke `/meta-patterns` via the Skill tool. Read its output — clusters
grouped by `topic` with member sentinels (file, session, ts, classification).

Filter:
- Apply `--top=N` / `--cluster=<topic>` / `--min-occurrences=N` /
  `--class=<value>`
- Order by occurrence count descending, then by recency descending

### Phase 2 — classify the corrective shape per cluster

For each cluster, read the dominant `classified=` field across its member
sentinels:

| Classification | Corrective routing |
|---|---|
| `skill-bug` | Direct Edit against the skill's SKILL.md or scripts. Surface the lines that produced the wrong output |
| `kb-gap` (correction shape) | A KB-fix skill if KB content is wrong; the orchestrator drafts the fix |
| `kb-gap` (addition shape) | A lessons-capture skill (`/meta-lessons`) — the orchestrator drafts the addition |
| `memory-rule` | Direct Write against `~/.claude/projects/<slug>/memory/feedback_<topic>.md` per the global Memory Hygiene format |
| `claude-md-rule` | `/meta-edit` — composes the pre-check before the CLAUDE.md edit |
| `out-of-scope` | Skip — out-of-scope sentinels capture pattern detection signal but warrant no artifact |

Mixed-classification clusters (members with different `classified=` values)
are surfaced for human classification rather than auto-routed.

### Phase 3 — draft per cluster

For each classified cluster, draft the corrective artifact:

- **skill-bug**: identify the file + line ranges from member sentinel
  context; propose Edit diff
- **kb-gap correction**: locate the wrong content; propose the fix +
  destination
- **kb-gap addition**: identify the right KB file under
  `docs/knowledge/<domain>/` or `~/dotfiles/claude/references/` (using any
  existing INDEX.md for routing); draft the addition
- **memory-rule**: draft `feedback_<topic>.md` per the memory format
  (frontmatter + Why + How-to-apply); destination
  `~/.claude/projects/<slug>/memory/`
- **claude-md-rule**: identify the narrowest applicable scope (global /
  project / mode); draft the rule body; queue for `/meta-edit`

Output: per-cluster proposal table with: topic, occurrence count,
classification, destination, draft body preview, apply-confidence
(high/medium/low based on draft-fit + member-sentinel consistency).

### Phase 4 — per-cluster review-gate

For each draft, present the engineer:

1. Cluster topic + member-sentinel summary
2. Proposed corrective artifact (destination + body)
3. Choice:
   - **Apply** → execute via the routing in Phase 2
   - **Revise** → engineer provides modifications; re-loop to Phase 3
   - **Skip** → leave cluster unresolved (mark in log for next /meta-act
     run)
   - **Reclassify** → engineer overrides; re-route to different
     classification

One cluster at a time. Default-no on each gate — applying requires
explicit accept.

### Phase 5 — apply

On accept, route to the downstream skill or direct write/edit. Commit per
destination repo's conventions (`Bundle stage + verify + commit`, no AI
attribution).

For `claude-md-rule` → invoke `/meta-edit <scope>` (composes!) — that
orchestrator runs its own pre-check + edit gate, so this step is
double-gated for CLAUDE.md changes.

### Phase 6 — recap + write resolution log

After all clusters processed, append to
`~/.local/share/claude-meta/cluster-resolutions.log`:

```
<ISO-8601-UTC> /meta-act resolved cluster=<topic> via=<routing> commit=<SHA>
<ISO-8601-UTC> /meta-act skipped cluster=<topic> reason=<engineer-choice>
```

This log is read by future `/meta-act` runs to suppress re-surfacing
already-resolved clusters (unless their occurrence count has grown since
resolution — that's signal the resolution didn't take).

## Output contract

- Per-cluster proposal preview (always)
- Per-cluster apply result + commit SHA (on apply)
- Resolution log append (always)
- Timestamp at `~/.local/share/claude-meta/last-meta-act`

## Composes with

- `/meta-patterns` — Phase 1 — the cluster sensor
- `/meta-edit` — Phase 5 for `claude-md-rule` classifications
- a KB-fix skill — Phase 5 for `kb-gap correction` classifications
- `/meta-lessons` — Phase 5 for `kb-gap addition`
- `/wtf` — upstream sentinel source; this orchestrator closes /wtf's loop
- `/meta-retro` — sibling. `/meta-retro` surfaces emerging clusters
  weekly; `/meta-act` resolves established ones.

## Pitfalls

- **Don't act on low-occurrence clusters.** Default `--min-occurrences=3`
  filters single-session noise. Resolving a one-off too aggressively
  creates spurious artifacts. Wait for the pattern to establish.
- **Mixed-classification clusters need human reclassification.** When
  sentinels in the same cluster have different `classified=` values, the
  orchestrator surfaces for human review rather than auto-routing — the
  classification at capture time may have been wrong, or the cluster may
  span multiple corrective shapes.
- **Apply confidence isn't authority.** "High" confidence means the
  draft-fit is mechanical; the engineer still gates each accept.
- **Resolved clusters can recur.** If the same topic re-clusters after
  resolution, the resolution didn't take — re-surface with a flag noting
  the prior resolution attempt + commit SHA so the engineer can read
  what was tried.
- **claude-md-rule via /meta-edit is double-gated.** /meta-act's gate
  approves the draft; /meta-edit's pre-check runs its own conflict +
  activation surfacing. Engineer can abort at either gate.
