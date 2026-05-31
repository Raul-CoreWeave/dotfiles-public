---
name: meta-retro
description: Weekly apparatus retrospective orchestrator. Composes /meta-all (apparatus audit — inventory + context + rules + conflicts + memory + patterns) + skill-invocation deltas (week-over-week, from the transcript archive) + outstanding todos into a single weekly digest written to ~/.local/share/claude-meta/retro/<YYYY-WW>.md. Surfaces drift trends + emerging patterns before /meta-patterns catches them weeks later. Read-only (writes only the digest file). Triggers on "/meta-retro", "weekly retro", "weekly review", "week-in-review", "apparatus retrospective".
argument-hint: "[--week=<YYYY-WW>] [--no-write] [--lookback=N]"
---

# /meta-retro — weekly apparatus retrospective

Composes the apparatus self-audit with skill-usage data into a weekly rollup.
Surfaces trends + drift early; closes the gap between per-session audits and
the months-long horizon of `/meta-patterns`.

## Why this exists

Existing surfaces:
- **Per-session**: `/meta-all` snapshots apparatus state on demand.
- **Long-horizon (months)**: `/meta-patterns` clusters /wtf sentinels across
  sessions; surfaces patterns after enough samples accumulate.

The **weekly** horizon is missing. Trends like "CLAUDE.md grew 3% this week",
"skill X invocations dropped to zero", "/wtf sentinels for topic Y appeared
4 times" go unsurfaced until they accumulate to /meta-patterns-actionable
levels — by which point the trend is months old.

## Inputs

| Arg | Meaning |
|---|---|
| `--week=<YYYY-WW>` | Specific ISO week (default: current week) |
| `--no-write` | Print digest to chat; don't write the file |
| `--lookback=<N>` | Compare against N weeks ago (default: 1 — last week) for delta surfacing |
| `--dry-run` | Surface what each phase would query; apply nothing |

## Phases

### Phase 1 — apparatus snapshot (/meta-all)

Invoke `/meta-all --quiet` (skip per-phase chatter). Capture the structured
findings buffer:
- Inventory: file counts per persistence root + dangling refs + orphan untracked
- Context: CLAUDE.md scope sizes; total session-start token cost
- Rules: high-cite + zero-cite sections
- Conflicts: cross-scope overlaps
- Memory: promotion + demotion candidates
- Patterns: top recurring /wtf clusters

If `/meta-all` was already run this week, reuse its written report instead
of re-running.

### Phase 2 — skill invocation deltas

Run the transcript-archive grep:

```
bash ~/.claude/skills/meta-rules/scripts/grep-skill-invocations.sh --since 7d
```

This emits per-invocation NDJSON for every skill/command in the window
(built-ins excluded by default; `--include-builtins` to add them).

Compute week-over-week deltas (`--lookback=N` weeks). Surface:
- Top-5 most-invoked skills (this week)
- Top-5 invocation deltas (biggest gains and biggest drops vs prior week)
- New skills invoked for the first time
- Skills that went silent (invoked last week, zero this week)

### Phase 3 — repo activity (optional)

If the launch CWD is inside a git repo, surface this week's commit themes:

```
git -C <repo> log --since='7 days ago' --oneline
```

Synthesize into a few work-theme bullets — what kinds of work dominated
this week. Skip silently if not in a repo.

### Phase 4 — outstanding work

Read `~/.claude/todos/<category>.md` (all categories). Surface P1 + P2 items
that were open all week without progress.

### Phase 5 — synthesize digest

Write to `~/.local/share/claude-meta/retro/<YYYY-WW>.md` (unless `--no-write`;
`mkdir -p` the dir first):

```markdown
# Week <YYYY-WW> retrospective — <start-date> through <end-date>

## Apparatus
- <CLAUDE.md size deltas, new memory entries, new/modified skills>
- <dangling-refs / orphan-untracked findings from inventory>
- <high-cite + zero-cite rules>
- <new cross-scope conflicts>

## Skill invocation deltas vs <lookback> week(s) ago
- <top gainers + top droppers + first-time + went-silent>

## /wtf sentinels surfaced this week
- <new topic clusters from /meta-patterns; flag if cluster exceeded N=3 across sessions>

## Repo activity
- <commit themes for the week, if in a repo>

## Outstanding
- <P1 + P2 todos open all week>

## Action recommendations
- <auto-derived: "consider /meta-edit for the new orphan citation"; "consider
   acting on the recurring `<topic>` cluster">
```

### Phase 6 — surface in chat

Print the digest in the response. If `--no-write`, that's the only output.
Otherwise, also surface the file path so the engineer can read it later.

## Output contract

- Digest written to `~/.local/share/claude-meta/retro/<YYYY-WW>.md`
- Printed in chat
- Side-effect: timestamps `~/.local/share/claude-meta/last-meta-retro`
  (for future drift detection or a session-end footer)

## Composes with

- `/meta-all` — Phase 1 — apparatus audit
- `grep-skill-invocations.sh` (meta-rules) — Phase 2 — full transcript-grep
  for built-ins + user/project skills
- `/todo` — Phase 4 — outstanding action items

## Pitfalls

- **Don't run mid-week.** Designed for end-of-week. Mid-week deltas are
  noisy because the week's data isn't complete.
- **`/meta-all` is the expensive phase.** If it ran earlier in the week,
  reuse its output rather than re-running.
- **`/wtf` cluster surfacing requires history.** Early weeks return empty
  for the pattern bullet; that's correct.
- **Year-end / week-53 edge cases.** ISO week numbering treats week 53
  inconsistently; the file naming convention pins to `<YYYY>-<WW>` to avoid
  ambiguity.
