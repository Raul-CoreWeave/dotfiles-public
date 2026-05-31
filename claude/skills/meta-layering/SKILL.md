---
name: meta-layering
description: Execution-layer placement sensor for the skill apparatus. Detects logic living at the wrong LAYER — deterministic glue described for the LLM to hand-execute inside a skill that a script should own instead (Class A, "under-scripted"). A deterministic script narrows candidates from skill prose (SKILL.md + reference/*.md); the LLM classifies each as truly-deterministic (→ fold into a scripts/*.sh) vs genuine judgment (→ keep). Sensor-only by design — proposes the route, never auto-edits. The LAYER twin of /meta-redundancy (which does wrong STORE). Enforces the "skills justify themselves with scripts" + "Picking a primitive" principles as a periodic drift-catch, not just an authoring-time gate. Class B (CLAUDE.md/SKILL.md procedure-prose that should be extracted to a skill/reference) is deferred to v1+. Triggers on "/meta-layering", "wrong execution layer", "should be a script", "LLM doing deterministic work", "under-scripted skill", "determinism in prose", "logic in the wrong layer".
---

# /meta-layering — execution-layer placement sensor

Skills split work across execution layers: deterministic logic belongs in a
`scripts/*.sh` (the scripts-first pattern); LLM judgment belongs in the
prompt. Under time pressure that split drifts — a deterministic reshape, a
timestamp computation, a JSON normalization gets *described in prose for the
LLM to hand-execute* instead of scripted. That costs reliability (the
dirty-stdout / hand-built-JSON bug class) and tokens (re-deriving the transform
every run). This sensor is the periodic drift-catch for that split.

Same shape as /meta-redundancy, one axis over:

| | /meta-redundancy | **/meta-layering** |
|---|---|---|
| Axis | wrong **store** (todos/watchlists/memory) | wrong **layer** (LLM-prose vs script vs hook) |
| Defect | content-shape misfit | logic-placement misfit |
| Fix | MOVE / DELETE / ARCHIVE | **script-it** / extract / keep |

## Defect classes

| Class | Defect | Cost | v1? |
|---|---|---|---|
| **A — under-scripted** | deterministic glue described for the LLM to run by hand, inside a skill's SKILL.md / reference prose | reliability + per-run tokens | ✅ **this version** |
| **B — over-prosed** | a multi-step procedure encoded as always-loaded CLAUDE.md / SKILL.md prose that should be a script/skill + on-demand reference + pointer | always-loaded context + re-derivation | ⏳ v1+ (Out of scope below) |

Per-candidate **verdict**: `script-it` (fold into a `scripts/*.sh`) · `keep`
(genuine judgment — false-positive) · later (Class B): `extract-to-reference` /
`extract-to-skill` / `hook-it`.

## Where it sits in the meta-* family

```
/meta-conflicts     → CLAUDE.md × CLAUDE.md     (rule duplication)
/meta-memory-audit  → memory × CLAUDE.md        (fact-vs-rule promotion)
/meta-redundancy    → stores × stores           (content in the wrong STORE)
/meta-layering      → skill prose × scripts     (logic in the wrong LAYER)   ← this
```

The first three ask "is this *content* in the right place"; this one asks "is
this *logic* at the right execution layer". Orthogonal — a line can be
correctly-stored AND wrongly-layered (deterministic glue that belongs in the
skill but in a script, not the prompt).

## Trigger

- `/meta-layering` (defaults: scan `~/.claude/skills` + the project's
  `.claude/skills-base` and `.claude/skills` when present)
- `/meta-layering --skill-roots=<csv>` (override the scanned roots)
- `/meta-layering -h` / `--help`

## Phase 0: deterministic narrowing

```
bash ~/.claude/skills/meta-layering/scripts/find-layer-candidates.sh [flags] > scan.json
```

The script greps skill prose (SKILL.md + `reference/*.md`, **never** a skill's
own `scripts/`) for three Class-A smells, and per flagged skill emits a
`semantic_scan_targets` pointer listing the skill's existing `scripts/*.sh` —
the fold-into targets. It does not classify; it narrows. Sub-second.

| Smell | Regex catches | Confidence | Why |
|---|---|---|---|
| `llm-determinism` | subject-is-the-LLM + a determinism verb ("the LLM constructs / reshapes / normalizes / computes / stamps …") | `review` | highest signal — prose instructing the LLM to do mechanical shaping |
| `inline-jq` | `jq -n` / `jq -cn` / `--slurpfile` / `--argjson` in prose | `low` | a reshape the LLM hand-builds — but also appears in legit script-invocation docs; context-dependent |
| `manual-mech` | `strftime` / `todateiso8601` / `date +%s` / `stat -f %m\|-c %Y` prescribed in prose | `low` | timestamp/staleness math the LLM runs by hand |

Precision-tuned, low-recall (same posture as /meta-redundancy's
`scan-stores.sh`): catches the canonical phrasings, tags confidence, lets the
LLM finish. False positives are expected and dismissed in Phase 1.

## Phase 1: deterministic-vs-judgment classification

For each `semantic_scan_targets` entry, read the flagged lines in context (and
the listed `scripts_present`). Per flagged line decide:

- **`script-it`** — the step is **pure data-shaping / mechanical transform**
  with no inference (JSON reshape, timestamp build, lowercase/prefix-strip,
  staleness math, ID translation). → fold it into one of `scripts_present` (or
  a new `scripts/*.sh`) and reduce the prose to an invocation. Name the target
  script. The canonical fix shape: the reshape moves into the script, the prose
  becomes "dump → pipe".
- **`keep`** (false-positive) — the step is **genuine LLM judgment**:
  symptom→file picking, RCA reasoning, scoping, NL classification,
  choosing *which* deterministic call to make. Determinism-adjacent prose that
  *describes* what a script already does ("the script drops drafts and computes
  aliases") is also `keep` — it's documentation, not an instruction to the LLM.

The discriminator is **"is there a decision in this step?"** No decision →
`script-it`. A decision → `keep`.

## Phase 2: render the report

```
# /meta-layering — <YYYY-MM-DD HH:MM UTC>

## Class A — under-scripted (script-it)
| # | Skill | file:line | Flagged prose | Fold into | Confidence |
|---|---|---|---|---|---|
| 1 | <skill> | SKILL.md:230 | "the LLM constructs targets.json …" | <existing-script>.sh / new | review |

## Kept (false-positive — describes a script, or genuine judgment)
<flagged lines the LLM dismissed — surfaced so the engineer sees what was checked>

---
Scanned roots: <…>. Candidates: K across M skills. script-it: X, keep: Y.
```

## Phase 3: surface + gate

Present the report. **No edits applied automatically** — same sensor-vs-applier
split as /meta-redundancy and /meta-conflicts. Per candidate:

- `apply <N>` → make the code change: extend/author the named `scripts/*.sh`,
  reduce the prose to the invocation, then run `/sync-skill-docs <skill>` and
  commit on the skill's working branch. The edit is a normal skill-dev change
  behind the usual review.
- `defer <N>` → log to a dev-todo category for a later batch.
- `dismiss <N>` → mark false-positive (the regex over-fired).

`/meta-layering` never edits a skill itself — it routes to a code change the
engineer makes + reviews. Sensor-only by design.

## Output contract

`scripts/find-layer-candidates.sh` emits a single JSON object:

```
{
  "scanned_at": "<ISO-8601 UTC>",
  "skill_roots": ["<dir>", …],
  "class_a_candidates": [
    {"class":"A","skill","file","line","smell","confidence","match","route"}
  ],
  "semantic_scan_targets": [
    {"skill","home","scripts_present":[…],"instruction":"…"}
  ],
  "summary": {"candidate_count","skills_flagged","by_smell":{…}}
}
```

Exit 0 always on a completed scan (candidates may be empty); 2 on arg error /
missing dependency (`jq`, `rg`).

## Composes with

- The **"skills justify themselves with scripts"** + **CLAUDE.md "Picking a
  primitive"** + **scripts-first-vs-prompt-extension** design principles —
  the *normative* rules this sensor enforces. Those fire at authoring time;
  this catches what drifted past them under pressure (the same justification
  every meta-* sensor has).
- **/meta-redundancy** — sibling sensor, one axis over (store vs layer). Same
  script-narrows / LLM-classifies / route-to-applier mold.
- **/meta-context** — pairs on the (future) Class-B axis: meta-context reports
  *that* a section is large; meta-layering's Class B would explain *why*
  (procedure-prose) and propose extraction. v1 is Class-A-only, so this is a
  v1+ pairing.
- **/sync-skill-docs** — the applier's mandatory follow-up after a `script-it`
  edit (a SKILL.md prose→invocation change is exactly its drift surface).
- **/meta-all** — should fold in as a read-only sensor step (not yet wired;
  see Out of scope).

## Cadence

Not every session — noisy. On-demand, in dev sessions after a batch of skill
work, or via `/meta-all`. Highest-value right after shipping a skill that did
LLM-side glue under time pressure (the drift it's built to catch).

## Limitations (v0)

- **Class-A only.** CLAUDE.md/SKILL.md procedure-prose that should be extracted
  (Class B) is not scanned yet — see Out of scope.
- **Precision-tuned, low-recall.** The three regexes catch canonical phrasings;
  a deterministic step phrased outside them slips through. Recall is the LLM
  phase's job on the candidates surfaced, not the script's.
- **Can't perfectly tell "instructs the LLM" from "describes a script".** The
  `inline-jq` and `manual-mech` smells fire on both; the LLM disambiguates in
  Phase 1 (hence their `low` confidence). `llm-determinism` anchors on the
  subject so it's cleaner (`review`).
- **No fold-into-which-script judgment offline.** The script lists
  `scripts_present`; choosing the target (or deciding a new script is needed)
  is the LLM/engineer's call.
- **Other meta-* sensors self-match** on documented smell patterns; the
  meta-layering home is skipped, but a sensor that *quotes* `jq -n` in its docs
  may surface — dismiss in Phase 1.

## Out of scope (v1+)

- **Class B — procedure-prose extraction.** Detect CLAUDE.md / SKILL.md
  sections that are multi-step procedures (command fences + step-numbering +
  named-script refs, gated by size) living as always-loaded prose that should
  be a script/skill + on-demand reference + pointer. Needs a size-gated
  narrower + the contract-vs-procedure distinction (some long prose is a
  cross-primitive *contract* whose extraction loses value). Routes to
  `/meta-edit` (CLAUDE.md) or a skill-creator. Ship after Class A proves out.
- **Wiring into `/meta-all`** as a sensor step (deliberate orchestrator edit;
  do it once Class A has a real run or two behind it).
- **Agents + hooks** as scanned surfaces (agent prompts doing deterministic
  glue; behaviors that should be hooks). v2.
- **Auto-applying the `script-it` edit** (stays sensor-only by design).

## Related

- `/meta-redundancy` — sibling sensor; the wrong-store axis. Template this skill
  mirrors (script-narrows / LLM-classifies / route-to-applier, sensor-only).
- `/meta-conflicts`, `/meta-memory-audit` — the other content-shape sensors.
- The "skills justify themselves with scripts" + CLAUDE.md "Picking a primitive"
  design principles — the rules this sensor enforces as a drift-catch.
- `/sync-skill-docs` — the post-`script-it` doc-sync applier.
