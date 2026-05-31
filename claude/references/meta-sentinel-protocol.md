# Meta-sentinel protocol

Convention for emitting structured ground-truth signals into Claude Code
transcripts so cross-session pattern detection (`/meta-patterns`) can run on
deterministic grep targets instead of fuzzy natural-language classification.

The whole point: the LLM cannot reliably classify when it's wrong (if it could,
it wouldn't have been wrong). The user can, with a single keystroke. Sentinels
turn that low-friction signal into a durable, greppable artifact.

## Sentinel taxonomy

| Sentinel | Slash command | Meaning | Status |
|---|---|---|---|
| `META-WTF` | `/wtf [note]` | Claude said something wrong; capture the claim + classify the failure mode | **v0 — implemented** |
| `META-GEM` | `/gem [note]` | Claude said something novel/insightful; capture for future reference | v1 — deferred |
| `META-LANDMINE` | `/landmine [note]` | "Don't do X" — explicit anti-pattern marker, captured pre-emptively before next time | v1 — deferred |
| `META-EUREKA` | `/eureka [note]` | Collaborative insight worth keeping; engineer + Claude figured it out together | v1 — deferred |

The taxonomy is open — new sentinel types can be added without breaking
existing captures. The deferred types share the same emission/grep
infrastructure; only their classification logic and downstream routing
differ.

## Sentinel format

Standard v1 format (HTML comment, hidden from rendered markdown UI,
greppable in transcript JSONL even when JSON-string-escaped):

```
<!-- META-<TYPE> v=1 t=<ISO-8601-UTC> topic=<kebab> classified=<class> claim="<one-line>" -->
```

| Field | Required | Format | Notes |
|---|---|---|---|
| `META-<TYPE>` | yes | uppercase, delimiter-free | The grep anchor. Whitespace follows. |
| `v=1` | yes | integer | Schema version. Bump for breaking changes. |
| `t=` | yes | `YYYY-MM-DDTHH:MM:SSZ` | UTC. Unquoted. |
| `topic=` | yes | kebab-case, no spaces | Cluster key. Reuse existing topics when topically similar. |
| `classified=` | yes (WTF) / optional (others) | enum | See classification table below. |
| `claim=` | yes (WTF) / optional (others) | quoted string | One-line verbatim; escape internal `"` as `\"`. |

Additional fields can be added (e.g. `severity=`, `links=`) in a
future schema version; consumers must tolerate unknown fields.

## Classification taxonomy (for `META-WTF`)

| Class | When to use | Downstream routing |
|---|---|---|
| `skill-bug` | A skill, script, or hook produced wrong output silently — user discovered the gap manually | Edit the skill + re-sync its references |
| `kb-gap` | The claim contradicts a knowledge-base file, OR the KB lacks the fact entirely | KB correction or addition |
| `memory-rule` | A user-specific behavior or preference Claude should have known | New `feedback_*.md` memory entry |
| `claude-md-rule` | A generalizable normative rule Claude violated | CLAUDE.md edit at narrowest applicable scope |
| `out-of-scope` | Genuine confusion, no durable artifact warranted | Log only (still surfaces in pattern detection if recurring) |

## Grep contract

The marker tag (`META-WTF`, `META-GEM`, etc.) is **delimiter-free** so it
greps cleanly through JSON escaping. The trailing space after the marker
is part of the grep anchor — it disambiguates `META-WTF` from theoretical
`META-WTF-V2`-style suffixes.

Grep recipes:

```
# WTF only:        META-WTF<space>
# GEM only:        META-GEM<space>
# All sentinels:   META-(WTF|GEM|LANDMINE|EUREKA)<space>
```

Attribute parsing should be tolerant — JSON-escaped (`\"`) and
raw (`"`) attribute quote forms both extract correctly.

## Topic naming guidelines

`topic=` is the cluster key. Bad choices fragment patterns across artificial
boundaries; good choices reveal them.

**Good topic slugs:**
- specific, evergreen, future-greppable
- specific to a particular failure mode
- names the misconception
- names the tooling axis

**Bad topic slugs:**
- `bug` — too generic; everything is a bug
- `2026-05-20-fix` — date-anchored; defeats cross-session clustering
- single-resource — will never recur with the same resource
- vague — won't cluster with the related specific topic

Before picking a fresh topic, grep the transcript archive for prior topics:

```
rg -uu --no-line-number -o 'topic=[a-z0-9-]+' ~/.claude/projects | sort -u
```

If a prior topic captures the same shape of issue, reuse it. Topics are
case-sensitive; stay lowercase-kebab.

## Out of scope

- **Auto-detect sentinels from natural language.** Explicit slash-command
  is the convention. Fuzzy detection of "wrong" / "actually" / "no" has
  too many false positives. Engineers train themselves to use `/wtf`.
- **Hook-driven auto-capture.** A `UserPromptSubmit` hook could inject a
  reminder when the prompt looks correction-shaped, but writing sentinels
  remains user-explicit. Hooks observe; they don't decide.
- **Cross-machine sync.** Transcripts are per-machine. Multi-machine
  pattern detection is a separate problem.

## Related

- `/wtf` skill — sentinel emitter
- `/meta-patterns` skill — sentinel analyzer
- Global `~/.claude/CLAUDE.md` § "Capture-trigger discipline" — the
  natural-language fallback framework when the engineer didn't use `/wtf`
