---
name: wtf
description: Real-time correction sentinel. When the user types `/wtf [optional note]`, capture the wrong claim from the immediately-preceding assistant turn(s), classify the failure mode (skill-bug / kb-gap / memory-rule / claude-md-rule / out-of-scope), emit a transcript-greppable sentinel for downstream `/meta-patterns` analysis, and draft the appropriate corrective artifact with a review-gate before applying. Pairs with `/gem` (positive sentinel, v1) and `/meta-patterns` (cross-session analyzer). Triggers ONLY on the literal slash command `/wtf` — does NOT fire on natural-language "wrong" / "actually" / "no" to avoid false positives.
---

# /wtf — real-time correction sentinel

When the user types `/wtf [optional one-line note]`, Claude said something wrong in the immediately-preceding turn(s). This skill captures the wrong claim, emits a structured sentinel into the transcript for later cross-session analysis, and routes the correction to the appropriate durable artifact (skill bugfix, knowledge-base edit, memory entry, or CLAUDE.md rule).

The sentinel is the load-bearing artifact — it makes the correction **deterministically greppable** by `/meta-patterns`, so recurring failure patterns across sessions surface automatically rather than dying in chat history.

## Why this exists

Claude can't reliably self-classify when it's wrong (if it could, it wouldn't be). The user can. A single-keystroke sentinel gives the user a low-friction way to inject ground-truth correction signal without breaking flow. The downstream `/meta-patterns` skill grep-finds these sentinels across the transcript archive (`~/.claude/projects/<slug>/*.jsonl`) and clusters by topic — turning isolated session-level corrections into cross-session pattern detection, which is the highest-leverage gap in the self-improvement loop.

## Trigger

- Literal slash command `/wtf`
- Optional inline note: `/wtf claimed the flag was --foo when it's --bar`
- Optional turn-count: `/wtf --turns=3` (default 1; widen when the wrong claim sits 2-3 turns back)

**Does NOT trigger on:**
- Natural-language "that's wrong" / "actually" / "no" / "incorrect" — too many false positives in non-correction contexts. Use `/wtf` explicitly.
- Bare `wtf` without a leading slash — that's an exclamation, not an invocation.

## Phase 0: identify the wrong claim

Read the last N assistant turn(s) (default 1, configurable via `--turns=N`). Extract the SPECIFIC claim that's wrong. State it back to the user in one line for verification.

If no specific claim is identifiable (e.g., the prior turn was a tool call with no assertions, or the user invoked `/wtf` after their own message), ask: **"which claim are you flagging?"** before proceeding. Don't fabricate a target.

If the user's `/wtf` message includes an inline note (`/wtf claimed the flag was --foo when it's --bar`), use the note as the claim identification and skip the verification step.

## Phase 1: classify the failure mode

Categorize the wrong claim into exactly one class:

| Class | Definition | Routing |
|---|---|---|
| `skill-bug` | A skill, script, or hook produced wrong output silently (the user discovered it manually) | Propose Edit + `/sync-skill-docs <skill>` |
| `kb-gap` | The claim contradicts what a knowledge-base / docs file says, OR the docs are missing the fact entirely | Propose a docs/knowledge-base edit (correction or addition) |
| `memory-rule` | A user-specific behavior or preference I should have known but missed | Propose a new memory entry |
| `claude-md-rule` | A generalizable normative rule that applies to multiple sessions / scopes | Propose a CLAUDE.md edit at the narrowest scope that still applies (global / project / mode) |
| `out-of-scope` | Genuine confusion, no durable artifact warranted | Log the sentinel anyway (for pattern detection) but skip artifact drafting |

The user can override the classification with `--class=<value>` if my inference is wrong.

## Phase 2: emit sentinel

Emit a single sentinel comment in the response, in this exact format:

```
<!-- META-WTF v=1 t=<ISO-8601-UTC> topic=<kebab-case-topic> classified=<class> claim="<one-line>" -->
```

Field rules:
- `v=1` — schema version; bump if format changes
- `t=` — UTC timestamp, ISO-8601 `YYYY-MM-DDTHH:MM:SSZ`
- `topic=` — kebab-case slug (1-4 words). Stable across sessions for the same recurring issue. Examples: `flag-name-drift`, `stale-default-value`, `api-version-confusion`, `wrong-file-path`
- `classified=` — one of `skill-bug` / `kb-gap` / `memory-rule` / `claude-md-rule` / `out-of-scope`
- `claim=` — verbatim one-line summary of the wrong claim; quote with double-quotes; escape internal quotes as `\"`

The sentinel must appear in the assistant response text (not in internal reasoning). It gets captured in the transcript JSONL by Claude Code's normal mechanism, where `/meta-patterns` will find it.

Pick `topic=` carefully — it's the **clustering key**. Two sentinels with the same `topic` across two sessions = one cluster surfaced by `/meta-patterns`. If unsure between two topic spellings, grep the transcript archive first for prior `META-WTF` sentinels and reuse the existing slug if topically similar.

## Phase 3: draft the corrective artifact

Per the classification, draft the candidate artifact:

- **skill-bug**: identify the file(s) + line(s) that produced wrong output; propose a unified diff
- **kb-gap**: identify the target docs / knowledge-base file; propose the section + content
- **memory-rule**: draft the memory entry per the memory format (frontmatter + body with Why / How to apply)
- **claude-md-rule**: draft the CLAUDE.md edit at the narrowest scope; quote the section header + proposed paragraph

Show the diff and gate on explicit `yes` before applying. Claude Code's interactive consent fires naturally on Write/Edit calls if the path is outside the auto-allow list.

## Phase 4: apply or park

- On `yes` → apply the edit. Commit if appropriate per the relevant write-discipline rules (one-commit-per-file, no-AI-attribution, etc.). Surface the commit SHA.
- On `no` → park as a todo with `[[wtf:<topic>]]` anchor for cross-reference back to the sentinel. Priority defaults to P3 (parking lot) unless the user specifies otherwise.

## Efficiency notes

- One sentinel emission per `/wtf` invocation; sub-100-char overhead in the response
- Classification happens at capture time when context is freshest; downstream `/meta-patterns` runs grep-only (no per-match LLM reasoning)
- Sentinel format is delimiter-free for the marker tag (`META-WTF`), so it greps cleanly whether JSON-escaped (`\"`) or raw (`"`) in the transcript JSONL

## Scalability notes

- Topic taxonomy is open — no central registry needed. Reuse prior topics by grepping the archive when unsure.
- Sentinel format is versioned (`v=1`); future fields can be added without breaking existing matches
- The taxonomy of `classified=` values is small and stable; new values require a coordinated update to `/meta-patterns` clustering logic

## Out of scope (deferred to v1+)

- `/gem` — positive sentinel for "Claude said something insightful, capture for future reference"
- `/landmine` — explicit "don't do X" marker
- `/eureka` — "we figured something out together; KB-shaped"
- Auto-derivation of `topic` from prior session topics (fuzzy match)
- Hook-based fallback for sessions where the user forgot to invoke `/wtf`

## Related

- `/meta-patterns` — cross-session sentinel analyzer (consumes WTF + future GEM/LANDMINE/EUREKA sentinels)
- `/meta-memory-audit` / `/meta-memory-promote` — downstream when classification routes to memory
