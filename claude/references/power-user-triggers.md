# Power-user coaching — trigger catalog

Catalog of skills, commands, plugins, hooks, settings, and CLAUDE.md edits I can surface as `Power-user note:` footers. Expansion of `~/.claude/CLAUDE.md` § "Coach toward power-user fluency."

The inline rule defines *when* to emit a footer (skip if prompt was optimal; don't repeat within session). This catalog is the *what* — categorized triggers, with examples.

## When to emit

Surface a one-line `Power-user note:` footer when ANY of these hold:

1. **The user did manually what a Claude Code skill or slash command would automate.** Examples: hand-walking a search across docs/code → a search skill; hand-grepping for staleness → an audit/review skill; hand-querying a dashboard URL by hand → the relevant integration skill.
2. **The user asked a question a slash command answers.** Examples: "what does this skill do?" → `/<skill> -h`; "is this CLAUDE.md current?" → a CLAUDE.md auditor; "what should I automate here?" → an automation recommender.
3. **The user reached for a long generic CLI invocation when a wrapper/alias exists.** Examples: a repeated long `kubectl get ... -l ...` selector → a saved alias or function; a repeated multi-flag `git log` → an alias. (See `cli-fluency-catalog.md`.)
4. **The user repeated an action a hook would enforce.** Examples: re-permitting the same Bash command pattern → a `~/.claude/settings.json` permission allowlist or a permission-pruning skill; re-applying the same formatting after edits → a PostToolUse format-on-save hook; forgetting to branch before edit → a PreToolUse hook.
5. **The user's intent would be persistent enough to memo.** Examples: a stable behavioral preference → a `feedback_*.md` memory entry; a recurring shortcut → a custom slash command; a team-shareable rule → a project `.claude/` rule file; a global rule → a CLAUDE.md edit.
6. **The user reached for a routine that should be scheduled.** Examples: "remind me to check X tomorrow" → `/schedule`; "keep polling status every 5 min" → `/loop`.

## When to skip

- The prompt was already optimal (user invoked the right skill).
- I've already surfaced the same suggestion in this session.
- The suggestion is trivially well-known (e.g., reminding about `/help`).
- The skill/feature is one-off enough that installing it costs more than the saved keystrokes.
- The user is mid-flow on a critical task; a coaching note would derail attention. Save it for end-of-turn or next natural break.

## Catalog of footer-worthy capabilities

The specific skills installed vary per machine and per plugin set — type `/` to
browse what's available, `/plugin` for installed plugins, and
`ls ~/.claude/{skills,commands,agents}/` for user-level customizations. The
categories below describe the *shapes* of capability worth surfacing; substitute
the actual skill names present in your environment.

### Code review + dev workflow
| Capability shape | Surface when |
|---|---|
| Single-pass code review | reviewing a diff by hand without invoking a review skill |
| Multi-lens / deep review (correctness + security + architecture) | a change needs more than a single-lens pass |
| Security-only review | a branch-diff or dedicated security pass |
| Feedback-driven dev | pasted review comments / tickets to "fix this" |
| Simplify pass | "clean this up" on changed code |
| Docs authoring | "write a new doc / guide / README" or a major rewrite |
| Verify-the-change | "confirm this fix actually works" / run-and-observe |

### Claude Code harness itself
| Capability | Surface when |
|---|---|
| CLAUDE.md revise / improve | session generated stable rules worth promoting, OR a CLAUDE.md has dangling pointers / staleness / drift |
| Automation recommender | "what should I automate?" / new-repo onboarding |
| Config / hooks editor (`update-config`) | "from now on when X" / hook / permission request |
| Permission-prompt pruning (`fewer-permission-prompts`) | repeated permission prompts in the transcript |
| Keybindings help | "rebind X" / "change submit key" |
| Statusline setup | "configure status line" |
| `/loop`, `/schedule` | recurring task / cron-like need |

### Search / knowledge
| Capability shape | Surface when |
|---|---|
| Code search across indexed repos | "find where X is implemented" / "how does Y work" |
| Knowledge / doc search | hand-walking an internal doc system to find an answer |

### Persistence primitives
| Primitive | Surface when |
|---|---|
| Memory entry (`feedback_*.md`) | a stable user-specific preference Claude should remember |
| Custom slash command | a recurring prompt template the user types by hand |
| Project `.claude/` rules | a team-shareable convention |
| CLAUDE.md edit | a generalizable always-on rule |

## Format

```
Power-user note: <capability name> — <one-sentence why; what it would
have done that the manual path didn't>.
```

Example: `Power-user note: a doc-sync skill would catch the dangling cross-reference before commit instead of after.`

Keep to one line; the rule says one-line footer. Don't stack multiple notes in a single turn — pick the highest-value one.

## Anti-pattern

Silence on a clean candidate. The rule defaults to skip-when-unsure; the historical failure mode is over-applying the skip ("the user probably already knows that skill"). Resolution: when in doubt, emit. The cost of a one-line footer the user already knows is much lower than the cost of repeatedly not surfacing capabilities they would actually use.
