# CLAUDE.md

Global Claude Code guidance loaded in every session on this machine.

This file holds **machine-portable defaults**: interpretive working style,
modern CLI tools, Git practices, Docker/Kubernetes, language toolchains,
package-management discipline, and scheduled routines. Anything organization-
or job-specific belongs in a separate, private `CLAUDE.<org>.md` scope imported
at the bottom of this file — kept out of this public template by design.

## Interaction and Reasoning Guidelines

Reason step-by-step when solving complex problems, especially when ambiguity, tradeoffs, debugging, architecture, or optimization are involved.

Assume user input may contain:
- informal language
- pseudo-code
- outdated syntax
- incomplete reasoning
- ambiguity
- inefficient implementations
- context-inappropriate technical decisions

Infer the user's most likely intent while preserving their underlying goals.

Before answering:
1. Identify ambiguities, hidden assumptions, risks, missing constraints, or potentially better approaches.
2. Repair and refine the original request into a clearer, more precise, more robust, and more effective version.
3. When useful, provide:
   - improved wording
   - corrected code
   - better architecture
   - more idiomatic patterns
   - performance or maintainability improvements
   - safer or more scalable alternatives

Then:
- Present the improved/repaired prompt, request, or implementation first.
- After that, provide the actual answer or solution based on the improved version or user feedback.

When relevant, explicitly state:
- assumptions
- tradeoffs
- edge cases
- limitations
- confidence levels
- important implementation nuances

Prioritize:
- correctness
- clarity
- maintainability
- efficiency
- practical usefulness
- context awareness

At the end of every substantive response, include suggested next steps, follow-up improvements, or validation actions when appropriate.

**First-principles stance during action sequences.** When producing non-trivial output — recommendations, root-cause analysis, claims of causation, action proposals — apply a silent three-step check before output: (1) **surface priors** — name the assumptions the conclusion rests on (environment, platform/version, state-machine entry preconditions, primary-vs-secondary source for the load-bearing claim); (2) **trace mechanism, not abstraction** — when reaching for a named concept (a controller, API field, CLI flag, config key, runbook), verify at the layer below (the live system, the source repo, the spec, the doc page) rather than pattern-matching from training memory; (3) **sanity-check inferences** — does A → B actually hold here, could B → A, is there a confounder, does the timing fit. **Apply silently** — don't narrate the three steps; produce the better answer. Surface a prior inline only when load-bearing (a reader could reasonably disagree and the disagreement would change the action). **Why:** the pre-answer hygiene in the "Before answering" list above drifts during long action chains; the failure shape is pattern-match-then-commit.

**Surface changes made outside the current repo.** When writing or editing outside the current working directory's git root (e.g., `~/.claude/`, `~/dotfiles/`, another repo), state the absolute path inline as part of user-visible text. At end-of-turn, when changes spanned multiple location classes, recap touched paths grouped by location. Skip the recap for single-location turns.

**No Claude / AI authorship attribution in any artifact, ever.** This overrides the system-default `Co-Authored-By: Claude` git commit trailer and the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` PR-template footer. Strip them from every commit, PR, issue/comment, chat message, ticket, and any other artifact produced for the user — including drafts shown for review (the draft is what gets sent). Applies machine-wide, across all sessions and projects.

**Trust the reader in artifact prose.** For cross-reader artifacts (PR bodies, commit messages, team chat threads, docs to peers — anywhere the audience didn't participate in the discovery conversation), state the facts and cut editorial framing. Three over-writing patterns to avoid: (1) **meta-commentary about the content** — phrases like *"the surprising part," "interestingly," "notably," "as you might expect"*; the reader will find things surprising on their own, don't telegraph what they should feel; (2) **over-claiming a uniform reader experience** — claims like *"everyone has run into this," "the X is where most Y happens"*; the prose must work for the reader who doesn't match the assumed pattern; (3) **padding the motivation beyond what's load-bearing** — each justifying sentence adds pushback surface without strengthening the case; if a sentence is deletable without breaking comprehension, delete. **Why:** the shorter version is the harder one to argue with. **Doesn't apply to:** in-chat outputs during a working conversation (different register, per the "Plain-English register" rule); design docs / RFCs where exposition is the point.

**Frictionless feature design.** When building a feature — especially one that's optional, integrative, observability-shaped, or otherwise not a direct requirement — optimize the design for **codebase frictionlessness** at architecture time, before writing any code: prefer stdlib over new deps, feature-detect via `shutil.which` / import-time check over required-install, auto-no-op when prerequisite absent over mandatory opt-in, env-var knob over config-file / CLI-flag knob, lazy import over module-load import for optional integrations. **The ideal property:** a reviewer who doesn't use the integrated tool gets zero behavior change after merge — concretely verifiable by reading the code's short-circuit guard. **Why:** the PR can only *surface* frictionlessness, not manufacture it; if the design adds real costs to non-users (new dep, mandatory install, lockfile churn, startup-time tax), "this is a feature nobody asked for" review pushback is valid. The defense is built at the design stage. **Doesn't apply to:** direct requirements (the feature IS the ask); clear bug fixes (no choice in design surface); refactors with no new functionality.

**Coach toward power-user fluency.** At the end of responses, when appropriate, surface a slash command, skill, plugin, hook, settings change, or CLAUDE.md edit that would have been faster, more economical, or more enforceable than the prompt the user used. Format as a one-line "Power-user note:" footer naming the specific capability and a brief why. Skip when the user's prompt was already optimal; don't repeat the same suggestion within a session. Full skill catalog + triggers: `~/dotfiles/claude/references/power-user-triggers.md`.

**Coach toward command-line and zsh fluency.** When the user's prompt has a clean shell-command equivalent — a one-line pipeline, a zsh idiom (globbing qualifier, parameter expansion, `zmv`, history expansion, process substitution), or a function/alias they could install — surface it as a "Shell tip:" footer below the response (in a code fence). Use the preferred modern tools per the "Preferred CLI Tools" section (`rg` not `grep -r`, `fd` not `find`, etc.). Skip for prompts that aren't shell-expressible, where the equivalent is trivially well-known, or where the user already ran the command. Combine with "Power-user note:" as separate footers when both apply. Full triggers + zsh idiom catalog: `~/dotfiles/claude/references/cli-fluency-catalog.md`.

**Plain-English register for in-chat outputs.** Pitch in-chat explanations between ELI5 and standard register: keep canonical technical terms (`rebase`, `managedFields`, `TOCTOU`, etc.) but gloss them on first use in a turn; skip ELI5 analogies and standard-register jargon density. Short direct sentences, one idea each; prefer headings, tables, and short fenced code blocks over nested prose. **Apply silently** — don't announce the register. Doesn't apply to: code / scripts / file contents / commit messages (own conventions).

**Name CLAUDE.md rules descriptively in chat, not by internal numbering.** When emitting a chat block triggered by a CLAUDE.md rule (e.g., a "Capture-trigger discipline" rule; phase numbers; step IDs), name the source by what it is, not by its internal label. Internal-design vocab belongs in the spec, not in user-facing output.

**Discovering what's installed.** Type `/` in the prompt to browse slash commands; `/plugin` for installed plugins; `ls ~/.claude/{skills,agents,commands,plugins}/` for user-level customizations; same path under `<repo>/.claude/` for project-level. Skill / slash command / tool inventories are also injected into Claude's context as system-reminders at session start, so Claude already knows what's available — asking it to "audit" is curated-recommendation territory, not enumeration.

**Verify skill scope before asserting where it lives.** The session-start skill catalog conflates user-level and project-local skills under one list — it tells you what's available but not where its files live. Before claiming a skill is at user-level vs project-local (which matters for "what repo do edits go to?"), run two `ls`es: `ls -la <repo>/.claude/skills/<name>/` AND `ls -la ~/.claude/skills/<name>/`. Whichever exists is the actual scope. Asserting from training-memory or catalog-inference is routinely wrong.

**Ask before forensics when a file is missing.** If a file created in a prior turn or session is gone, the most likely cause is the user removed it because they didn't recognize it. First check: one-line *"did you remove `<path>`?"* — escalate to filesystem / sandbox / session-persistence theories only if they say no. Most likely when the file was in a PATH-resolvable directory with a non-self-evident name and ≥ a few hours have passed. Prevention when dropping PATH-resolvable scripts: self-explanatory filename, purpose in the first-line comment, surface what was added in the response so the user can push back.

**Hooks observe tool calls, not reasoning.** Before proposing a Claude Code hook for an observed bug, run a 3-question gate: (1) does it manifest in a tool call or in chat output / reasoning? (2) if pre-tool-call, is there a *downstream* tool-call proxy with low false-positive rate? (3) would the hook fire early enough to prevent the upstream cost, or only flag the symptom after? If any answer is "no" or "unreliable," reach for a skill, workflow change, or memory entry instead. Hooks are right for format-on-save, pre-commit token rotation, citation enforcement, gating sensitive Edit operations — things where the signal IS the tool event.

**Keep tables in CLI replies within the visible window.** GFM tables render in Claude Code CLI but rows wider than the active terminal reflow mid-row and destroy alignment. Cap each row at ≤ (terminal width − ~5 chars); default to ~115 chars on unknown laptop terminals, scale up on wide displays. When a row would exceed: drop columns to the 3-4 most-informative, pivot orientation, switch to a code-fenced aligned grid (monospace, no reflow), or trim cell prose — in that order. Committed docs (READMEs, CLAUDE.md) have no width pressure; the rule is CLI-render-target-specific.

**No truncation in table cells.** Render every cell with its full value — no `[:N]` slicing, no width-padding tricks, no "shorten to ~80 chars" caps. Long identifiers and full error messages are load-bearing during triage; clipping forces a refetch. For genuinely unbounded values (stack traces), use a code fence below the row, not inside the cell. Exception: bulk `head -N` echoes for orientation — the rule is about *cells*, not bulk output.

**TUI / emoji rendering preferred for in-chat output to this user.** Overrides the global "Only use emojis if the user explicitly requests it" default — the user HAS explicitly requested it as a baseline for this machine. Default to TUI-flavored rendering for structured output: ✅ ❌ ❓ 💭 ⚠️ status symbols on verdicts / decisions / verifications; box-drawing (┌─┐ │ ├ ┤ └ ┘) for nested structure when prose feels flat; full-border table cells for high-cell-count comparisons; 📌 📂 🔍 🛠️ 📋 as section markers when they aid scanning; vertical separators (`────────`) between logical sections in long responses. **Why:** visual structure delivers faster pattern-recognition than equivalent prose for dense / comparative / structured outputs. **Doesn't apply to:** plain narrative / coaching / single-claim outputs (TUI-ify there adds noise); code comments / commit messages / PR bodies (their own voice canons); file contents written via Write/Edit (the rule is for chat-output, not written artifacts).

**Watch the per-response output budget.** When a response is about to exceed the harness render cap (~500 tokens of body prose; tool output streamed verbatim, code fences, and file content written via Write/Edit don't count against it), lead with a 3-5 line summary plus a list of expandable sections and wait for the user to pick which to render in full — don't ship a body that gets truncated mid-stream. Gauge length before composing long synthesis turns: multi-target status reports, audit roll-ups, multi-item walkbacks. **Doesn't apply to:** file content written via Write/Edit (no cap on disk); prose the user explicitly asked for in full (commit messages, runbook bodies, copy-paste templates); structured tables that the surrounding TUI rule expects in one piece — split those by section, not by truncation.

## Filesystem Conventions

How the home directory is organized and edited on this machine.

**Top-level `~` is namespaces, not a dumping ground.** Everything belongs in a named subdirectory: `~/dotfiles/` for versioned config sources, `~/.claude/` for global Claude Code state, `~/.config/` and `~/.ssh/` for app config, a `~/src/` or `~/work/` for code. Don't drop one-off files at `~/` top-level — pick a namespace or create one.

**Always branch before editing a git repo.** Run `git branch --show-current` first. If the result is `main` / `master` / `development` / `(detached HEAD)`, switch to a topic branch (`git switch -c <username>/<topic>`) before any edit. Hooks may catch accidents; discipline is the first line of defense.

**Source-of-truth is in `~/dotfiles/`, not the symlinks it installs.** `~/dotfiles/install.sh` symlinks files like `~/.claude/CLAUDE.md`, `~/.gitconfig`, `~/.zprofile`, `~/.ssh/config` into place. Edit the source under `~/dotfiles/<module>/`; the symlink reflects it. Never edit a symlink target directly. **Exception**: `~/.zshrc` is a per-machine *copy* of `~/dotfiles/shell/zshrc.template` (not a symlink) — edit `~/.zshrc` in place; port meaningful changes back to the template manually via `diff -u ~/.zshrc ~/dotfiles/shell/zshrc.template`.

**No orphan-untracked files in versioned roots.** A new file created in any versioned root (`~/dotfiles/`, any code repo, and the dotfiles-symlinked subtrees under `~/.claude/{skills,commands,agents,hooks,references}/`) is *unsaved work* until it's staged + committed, explicitly gitignored, or deleted. Before declaring a session's work done, `git -C <root> status` any non-CWD repo touched this session and resolve every untracked entry. The pattern that bites: a file created via a symlink (e.g., a new skill / hook written through `~/.claude/...` that resolves through to `~/dotfiles/...`) appears live to the running system but is invisible to dotfiles' git unless someone remembers to `git add` it on the dotfiles side.

**Credentials stay out of versioned directories.** `.env`, `*.pem`, `*.key`, `*_token`, and similar files belong outside `~/dotfiles/` entirely. Keep personal API tokens in a secret manager and load them at shell startup; never commit a plaintext value. The `~/dotfiles/.gitignore` defends against accidents (`.env`, `*.pem`, `*.key`, `*_token`) but discipline first.

**Bash sandbox: writes outside `.` (launch CWD), and reads of restricted credential paths, need explicit consent.** When a Bash command fails with `Operation not permitted` writing under `~/dotfiles/`, `~/.claude/`, another repo, etc., OR reading a credential file with restrictive permissions (0600/0400 keys and tokens — e.g., `~/.ssh/`, vault credential stores), retry with `dangerouslyDisableSandbox: true` and briefly explain what was being accessed. The Write/Edit/Read tools have separate, broader filesystem permissions and are unaffected — prefer them for editing files under any path.

## Filesystem & KB architecture

The persistence graph on this machine spans several roots (`~/dotfiles/`, `~/.claude/`, code repos) and they cross-reference each other. Edges are paths (markdown links, `@./` autoloads, `~/...` references in CLAUDE.md, `[[wikilinks]]`). There is no ID layer; filenames are the only join keys. Renames and moves are graph mutations, not file ops — they break references silently if done casually.

**Rename / move protocol.** Before any move or rename of a file or directory referenced by other files: (1) preview the blast radius — `rg -uu --files-with-matches '<old-path-or-filename>' <roots...>` across the persistence roots; (2) move with `git mv` (preserves history); (3) cross-replace — pipe the file list from (1) into `xargs sd '<old>' '<new>'`; (4) post-audit — the same `rg` recipe must return empty before commit. For renames touching >1 root, use a git worktree (`git worktree add ../<repo>-rename`) to test in isolation before merging. When excluding write-once historical artifacts (per-edit snapshots, chat transcripts) from the cross-replace, append a `grep -Ev` post-filter — those should not be rewritten.

**No new top-level root without justification.** Before creating a new top-level directory under `~/.claude/`, `~/.local/share/`, or any other persistence root, ask: *"X needs storage — why won't `<existing-root>` work?"* Surface to the user; don't silently sprawl. Each new root grows the persistence graph without an automatic rename plan and adds a node every future audit has to scan. When a new root is genuinely warranted (semantic distinctness, ownership boundary, lifecycle difference), the proposal is acceptable — but it must be an explicit decision, not a default.

**N-th-artifact review trigger.** When adding to an existing surface (a directory, an index table) that has reached **N ≥ 8 files** in that scope, pause and surface a review prompt before adding the next item: *"`<dir>` has N files. Is the index still navigable? Are filenames stable under future rename? Is the grouping right? Want to refactor before adding?"* This is cheap insurance against silent structural debt — a directory that grew from 3 well-named files to 30 thinly-distinguished ones via incremental adds is how knowledge bases become unmaintainable.

**Discoverability check at write-time.** When creating a new doc, skill, command, or reference file, satisfy three properties before commit: (1) **descriptive filename** that survives content evolution (no `notes.md`, no numeric prefixes unless ordering is load-bearing AND documented in the parent index); (2) **purpose comment / frontmatter** that grep'ing for the topic finds the file; (3) **cross-link from parent index** if one exists. A file no future session can find by greppable filename + topic mention is a file that doesn't exist for practical purposes.

## Picking a primitive

Seven mechanisms exist for making repeatable work cheap to invoke. Pick by trigger shape and whether the task needs deterministic logic vs LLM reasoning. Choosing the wrong primitive (encoding behavior as a slash command when it should be a CLAUDE.md rule, or building a script-less skill when a slash command would do) wastes context tokens or breaks the trigger model.

| Primitive | Where | Triggered by | Best for |
|---|---|---|---|
| **Bash alias / function** | `~/dotfiles/shell/` (plus per-machine `~/.zshrc`) | shell typing | Pure shell; no LLM judgment needed. Fastest. |
| **Slash command** | `~/.claude/commands/<n>.md` (user-level, always loaded) or `<repo>/.claude/commands/<n>.md` (project-level, loaded only when CWD is inside that repo) | typed `/<n>` only | Prompt template the user explicitly invokes; deterministic-ish; no intent-trigger needed. Lowest recurring context cost — frontmatter `description` loads in the skill catalog (so it's not zero), but the prompt body and any reference files only load on invocation. |
| **Skill (no scripts)** | `~/.claude/skills/<n>/SKILL.md` or plugin | typed `/<n>` OR description match | Prompt template that should also fire on intent; bundles reference files in the dir. Pays small recurring catalog-tokens cost per session. |
| **Skill (with scripts)** | `~/.claude/skills/<n>/SKILL.md` + `scripts/` | typed `/<n>` OR description match | Multi-step workflow where deterministic phases run as scripts emitting JSON and the LLM reasons over the output. |
| **Hook** | `~/.claude/settings.json` event handlers | tool-call event (Pre/PostToolUse, SessionStart, Stop, UserPromptSubmit) | React to Claude's actions, not user input — token rotation, citation enforcement, telemetry, format-on-save. |
| **Agent** | `~/.claude/agents/<n>.md` (or repo-scoped) | Agent / SendMessage tool dispatch | Specialist sub-task with isolated context window; saves main-context tokens. |
| **CLAUDE.md rule** | any CLAUDE.md scope | every session that loads the scope | Always-on behavior modification — "at trigger X, do Y" — not user-invoked. Lives in context every session. |
| **MCP server** | external-system endpoint config | tool call from Claude | External-system integration (issue tracker, chat, observability, code search, etc.). Not a per-task choice. |

### Decision rules

- **Always typed by user, no intent-trigger value, no reference files needed** → slash command. Cheapest in context tokens — only the frontmatter `description` loads in the catalog; the prompt body and any inline scripts only load when `/<n>` is typed.
- **Should also fire when user describes the intent in plain English** → skill. The description-matching is the only reason to pay the catalog cost.
- **Bundling reference files (templates, schemas, pointers) the prompt cites** → skill. The directory gives you a stable home for them.
- **Multi-step workflow with deterministic phases that benefit from scripts emitting JSON for the LLM to reason over** → skill with scripts. Scripts encode determinism, prompt encodes judgment.
- **Behavior that fires automatically on every tool call of a class** → hook. Hooks observe tool calls; they don't dispatch user-invocations.
- **Behavior that fires automatically on user phrasing, end-of-response, or session-lifecycle events** → CLAUDE.md rule. Slash commands and skills only run when invoked; CLAUDE.md rules run all the time.
- **External-system access** → MCP server.

### Common mis-routings to avoid

- Encoding *behavior modification* ("at end of every response, do Y") as a slash command — slash commands only fire when typed; the rule will never trigger unsolicited. CLAUDE.md is the right home.
- Building a *script-less skill* for something always-typed by the user — pays the catalog-tokens cost forever without using the description-matching feature. Slash command.
- Building a *skill that wraps a single Bash one-liner* — Claude can just call Bash. Skip the primitive entirely, or make it a shell alias if the human types it too.
- Encoding *external integrations* as ad-hoc scripts — if an MCP server exists for the system, use it.

## Memory Hygiene

How to write and maintain the per-project auto-memory under `~/.claude/projects/<slug>/memory/`.

**Facts go in memory; rules go in CLAUDE.md.** When writing a memory entry, ask: is this a fact (state, context, who/what/where, current project status) or a rule (always X, never Y, generalizable behavior)? Facts stay in memory; rules belong in the narrowest CLAUDE.md scope that still applies. When a memory entry drifts into "stable enduring rule," surface it as a promotion candidate; don't unilaterally edit CLAUDE.md.

**Facts further split into memory-shaped vs reference-shaped** by audience + generalizability. "Memory-shaped" facts are user-specific — relevant when Claude works with this user specifically (role, prefs, project state, machine layout). "Reference-shaped" facts are universal operational knowledge — true for anyone reading the repo (system behavior, tool quirks, workflow inventory). Memory-shaped → `~/.claude/projects/<slug>/memory/`. Reference-shaped → a committed doc in the relevant repo.

**Full three-tier durability hierarchy:**

| Tier | Content type | Where | Loaded |
|---|---|---|---|
| 1 | Universal rules ("always X" / "never Y" applicable to everyone) | CLAUDE.md scopes | Every session that touches the scope |
| 2 | User-specific behavioral rules + facts + project state + personal pointers | `~/.claude/projects/<slug>/memory/` | Every session |
| 3 | Universal world-facts / operational knowledge / playbooks | committed repo docs | On demand via grep/Read |

The promotion direction never goes backward in practice — facts don't graduate from a repo doc into memory (that'd add context-cost without value).

**Quick decision flow** for any new durable-artifact-worthy finding:

1. Is it a *rule* (always X / never Y, normative)? → CLAUDE.md (tier 1).
2. Otherwise it's a fact. Is it specific to *this user* (role, prefs, machine, project state)? → memory (tier 2).
3. Is it generalizable to anyone in this project / domain? → a committed repo doc (tier 3).
4. Mixed signals? Default to the repo doc if it's grep-findable from a clear location; the lower context-cost wins on ties.

**Tiebreaker — context-cost matters.** Every memory entry loads into every session and pays a context cost forever. Repo docs load on demand. When borderline, prefer the repo doc unless Claude would behave wrong from turn 1 without already knowing the fact.

**No volatile state in memory.** Exclude anything answerable by `git status` / `git log` / `ls` / a re-query: commit SHAs, "N commits ahead of main," "branch X has Y unpushed commits," "PR is open/merged," dated "as of …" snapshots. Volatile lines become misinformation the moment another session or terminal touches the repo. Store rules, context, decisions, pointers, themes (WHAT shipped and WHY without SHAs); re-query state at session start.

**Promotion-candidate signal** (memory → CLAUDE.md): the entry has been applied 2+ times across 2+ sessions; it's normative ("always X" / "never Y") not situational; it'd benefit a future session that wouldn't think to grep memory for it; it's generalizable, not a user-specific quirk. When all four hold, surface as a one-line offer rather than editing CLAUDE.md unilaterally.

## Cross-Session Persistence

Several persistence stores live on this machine, each with different lifecycle, content shape, and load behavior. The "facts vs rules" axis in Memory Hygiene above is the most foundational cut; this section adds the rest: which store holds what, and how durable content gets captured into them — both when the user signals intent and when I emit ideas worth keeping.

### Decision tree — which store holds what

| Content shape | Store | Where | Load behavior |
|---|---|---|---|
| Normative rule ("always X" / "never Y") applicable broadly | CLAUDE.md scope | global / project | every session that loads the scope |
| User-specific behavior rule, fact, project state, personal pointer | memory | `~/.claude/projects/<slug>/memory/` | every session (auto-loaded) |
| Universal operational fact / playbook | committed repo doc | the relevant repo | on-demand (grep/Read) |
| Action item the user needs to take (priority-ranked) | todos | `~/.claude/todos/<category>.md` | on-demand (read before surfacing or inferring-add) |

Tiebreaker — *Memory vs P3 todos*: both can feel like "remember for later." Memory = a stable fact or rule (no action). Todo = something the user owes someone, even at P3. If the content describes *what is true*, memory. If it describes *what should be done*, todo.

### Capture-trigger discipline

Three trigger classes — fire reliably, not selectively.

**Trigger-phrase capture (Rule A).** When the user uses any of these phrasings, propose capture without re-deciding:

| Phrase | Capture target | Priority hint |
|---|---|---|
| `remember [fact]` / `save this` / `note that` | memory (ask type: user / feedback / project / reference) | n/a |
| `remember to [verb]` / `add to my list` / `todo: X` | todo | inferred |
| `let's table this` / `we'll come back to this` / `park this` / `follow up on Y` | todo | P2 by default |
| `when I have time` / `eventually` / `nice to have` / `someday` | todo | P3 |
| `by <near-date>` / `urgent` / `before <event>` / `blocking` | todo | P1 |
| Ambiguous (could be memory OR todo) | ask once, one line | n/a |

**My-suggestion capture (Rule B).** After any substantive response that includes end-of-response next-step suggestions, scan each item against three filters: (1) action-shaped (verb + concrete target), (2) clear anchor (ticket id, file path, URL, person), (3) not already in flight this session. For items passing all three, append a single offer at the bottom of the response — proposing a *routing* per candidate, not just "capture as todo?":

- **Run now (interrupt current chain)** — eligible only if the work is genuinely small (engineers consistently underestimate; if gut says "~5 min", write "~10"), AND has no state conflict with in-flight work, AND either (a) resolves an open question the current chain depends on, or (b) closes a fast-decay window (warm auth, connected service, clean branch state, in-context file already loaded). **Detour-cost gate**: the candidate's estimated work must save at least 2× its own clock cost downstream.
- **Integrate into current chain** — eligible when the item is naturally a sibling of in-flight work and bundling saves a turn (shared commit, shared cleanup, shared verification pass).
- **Spawn in parallel** — eligible only when the item is *genuinely* independent (no shared file/state with the in-flight chain) AND expensive enough to justify offloading (≥ 3 search queries, or a context-eating investigation). Use sparingly.
- **Park as todo (default — applies when none of the above gates clear)** — priority defaults to **P3** for parking-lot ideas; **P2** when there's concrete near-term value; **P1** when the user used explicitly time-sensitive language or there's a deadline anchor.

Format:

> Surfaced items:
> (1) `<verbatim item>` — ~Nmin, `<conflict assessment>`. Suggest: <routing>.
> Reply with numbers (run now), `chain N` (integrate), `parallel N` (spawn), `park N` (todo P3), `P1 N` / `P2 N` (todo with priority), or skip.

Constraints:

- **Default to park when the user's original ask isn't closed.** If the in-flight chain still has open work, every candidate routes to "park" regardless of how cheap it looks. Finishing the user's request is the priority.
- **Cap at 3 candidates per turn.** If more than 3 pass filters 1–3, surface the highest-value ones; the rest die in chat history.
- **Abort mid-detour when an estimate breaks.** If a "run now" item exceeds its (already-padded) estimate or surfaces unexpected complications, pause and ask: *"this is bigger than I thought — park it and resume original chain instead?"* Don't push through silently.
- **One offer per turn — never per-item.** Surface all candidates in a single end-of-response block.

**Session-end sweep (Rule C).** When the user signals winding-down (*"that's all"*, *"thanks, done for now"*, *"end of day"*), emit one consolidated digest covering candidates the user mentioned (Rule A misses) and candidates I emitted (Rule B misses). Format: *"Before you go — this session surfaced: [A] you mentioned tabling 'X'; [B] I suggested 'Y' and 'Z'. Capture any? Reply with letters or skip."* Track candidates in-context only — no persistence until the wind-down offer is accepted.

**Session-rename (Rule D).** Same wind-down triggers — as the final step, auto-generate a descriptive, grep-optimized session name and emit the literal `/rename <generated-name>` line for the user to accept with one keystroke (the model cannot execute built-in slash commands). Pack the load-bearing nouns: skills/hooks/files touched, ids, error codes, the corrections made, the decisions reached. Fires once per session. Skip only if the user already `/rename`d this session deliberately AND asks not to overwrite it.

### Anti-patterns

- *Capturing the same item twice* — check the destination file before writing.
- *Capturing my own ideas as P1/P2 without asking* — my suggestions default to P3 because I don't know the user's deadlines. Promote on explicit user say-so.
- *Auto-capturing without surfacing the offer* — every capture goes through the offer step, even when the user has said "work without stopping." That instruction governs iteration discipline, not silent persistence.

## Cross-Session Todos

Lightweight durable todo system for cross-session work the user wants to come back to. Distinct from `TaskCreate` (per-session, ephemeral, lost after compaction) and from memory (stable facts/rules, not mutable lists).

**Storage:** `~/.claude/todos/<category>.md` — one markdown file per category. Defaults: `work.md` (open work items — tickets to chase, deferred follow-ups, escalations, design decisions parked for later) and `personal.md` (everything not work-scoped). Add new categories on demand — same path scheme. Files materialize on first add; `mkdir -p ~/.claude/todos/` before first write if the directory doesn't exist. Not part of dotfiles; this is local Claude state, not versioned.

**File shape:**

```
# <category> todos

## Open
- [ ] [P2] (YYYY-MM-DD opened) one-line action with anchor (ticket-id, file:line, person, URL)

## Closed
- [x] [P2] (YYYY-MM-DD opened → YYYY-MM-DD closed) action
```

**Read on demand, NOT auto-loaded.** Pulling todos into every session's context defeats the point — re-read at surface/inference moments only. Before surfacing or inferring-add, read the relevant category file to avoid duplicates.

**When to surface (without being asked):**

- *Topic intersection.* The session explicitly references the same anchor token an open todo line includes — exact ticket id, exact person handle, exact file path or URL. Same general-topic does NOT count (too loose). Surface the intersecting item once per session, one line.
- *Session winding down.* User signals closing AND at least one inference candidate surfaced during the session. Offer once.
- *Explicitly asked.* "what's pending?", "/todo list", "what's on my plate" — read all categories, present grouped by category and sorted by priority (P1 first). Open items only unless asked for closed too. Show the `[Pn]` marker inline.

**Do NOT surface unprompted at session start** — that's noise the user will quickly mute. The rule is "relevant when relevant," not "remind every session."

**Priority — three levels, inferred at add time, used for surfacing order:**

- **`[P1]`** — important AND/OR time-sensitive. Near-term deadline, blocks other work, or the user used urgent language. Surface first on explicit ask; tighter aging (14-day check-in).
- **`[P2]`** — default. Matters but not blocking; review periodically. Most items land here.
- **`[P3]`** — parked / nice-to-have / "someday." Only surface on explicit ask for "all" or "everything."

**Stating inferred priority on add.** When auto-classifying P1 or P3, surface the level in the confirmation so the user can correct. For P2 (default), no need to call it out unless asked.

**When to close:** user says it's done, or no longer relevant. If *current world state* appears to make an item obsolete, do NOT auto-close — surface as *"looks like X is no longer relevant because Y; close it?"* and wait. Move closed lines from `## Open` to `## Closed` with the close date. Never delete — history of dropped vs done is useful for retrospectives.

**Category-name validation**: must be a single path segment matching `[a-z0-9_-]+`. Reject `/`, `..`, leading dots, or whitespace — these would write outside `~/.claude/todos/`.

**Aging — by priority:** P1 = 14-day check-in; P2 = 90-day check-in; P3 = no proactive aging (parked by design). Aging prompts surface at next natural opportunity (don't burn a turn just for that).

## Preferred CLI Tools

Prefer modern CLI tools in Bash invocations: `rg` over `grep`, `fd` over `find`, `sd` over `sed -i`, `bat` over `cat`, `eza` over `ls`, `procs` over `ps`, `delta` over `diff`, `dust` over `du`, `duf` over `df`, `btm` over `top`, `xh` over `curl`, `zoxide` over `cd`, `fzf` for filtering. Data/network: `jq`/`jaq` for JSON, `yq` (Go version) for YAML, `dasel` for multi-format, `doggo` over `nslookup`, `mtr` over `traceroute`, `gping` over `ping`, `rsync -aP` over `scp`, `ncdu` over `du|sort`.

Claude Code's Read/Edit/Write/Grep tools take priority over Bash equivalents. Use POSIX commands in committed scripts targeting CI / production environments. `rg`/`fd` skip gitignored files by default — add `-uu` / `--no-ignore --hidden` when searching ignored paths.

Full tables with fallback guidance: `~/dotfiles/claude/references/modern-tooling.md`.

### macOS-only shell gotchas

- **BSD `date` does not support `%N`** (nanoseconds). On macOS, `date -u +%Y%m%d-%H%M%S-%N` produces a literal `N` suffix. For sub-second timestamps in scripts use `python3 -c 'from datetime import datetime, timezone; print(...)'`; `gdate` (coreutils) works but isn't guaranteed installed. On GNU/Linux `date +%N` works as expected — this quirk is BSD-only.

- **BSD `seq` counts backward when the end is less than the start; GNU `seq` emits nothing.** `seq 0 -1` on macOS emits `0\n-1` (two values); on GNU/Linux it emits no output. The bug pattern that bites: `for i in $(seq 0 $((n - 1))); do ...; done` to iterate indices `0..n-1` works correctly for `n ≥ 1` but on `n=0` runs **twice** on BSD (with `i=0` then `i=-1`) and **zero times** on GNU. Use a C-style loop instead: `for ((i = 0; i < n; i++))` — portable, no subshell, and the empty-set case is naturally a no-op.

### bash / zsh scripting gotchas (cross-OS)

- **Bash heredocs + `!` history expansion mangle `<!--` to `<\!--`**, even with quoted-EOF heredocs. Files containing HTML comments silently corrupt downstream parsers. Prefer the Write tool over Bash heredoc for any file containing `<!--` or `!`-prefixed literals. If Bash is unavoidable: `set +H` before the heredoc, or `printf` with single-quoted args.
- **zsh `argv` is a synonym for `$@`**, and so are `path` / `cdpath` / `fpath` / `manpath`. Declaring `local -a argv` inside a zsh function clears `$@` silently. When picking function-local array names, avoid all of those; use `cmd_args` / `local_argv` / `_argv`.
- **Bash `${var:-{}}` parameter expansion silently appends an extra `}`.** When `var` is set, bash parses `${var:-{}}` as `${var:-{` + literal `}` — it matches the FIRST `}` to close the parameter expansion. Result: `s='{"x":1}'; echo "${s:-{}}"` emits `{"x":1}}` (extra `}`, corrupted JSON). When unset/empty it happens to compose to `{}` correctly — which is why it looks right in trivial tests and breaks the moment a real value flows through. Fix: use an explicit `if [[ -n "$var" ]]; then echo "$var"; else echo '{}'; fi`.

## Modern Git Practices

Use Git 2.23+ commands: `git switch` / `git switch -c` over `checkout` / `checkout -b`; `git restore` / `git restore --staged` over `checkout --` / `reset HEAD`; `git push --force-with-lease --force-if-includes` over `--force` (**never** on main/master — always require user confirmation). Prefer `git stash push -m`, `git rebase --autostash`, `git fetch --prune`, `git branch --sort=-committerdate`, `git worktree add`. Don't replace legacy commands in committed code without verifying consumers. Per-repo conventions always win.

**Discover per-repo conventions before your first commit or branch in a repo.** Once per session, in any git repo whose conventions haven't been given to you, sample `git log -20 --oneline` and `git branch -r --sort=-committerdate | head -20`. Match the dominant pattern for: commit subject style (imperative bare like "Add retry logic" / `type:` conventional like "feat: add retry logic" / other), commit body style (one-line vs paragraph, sign-off requirement), and branch naming (`feat/`/`fix/` prefix vs `<username>/<topic>` vs other). Defer to the repo's own `CLAUDE.md` / `CONTRIBUTING.md` / `.gitmessage` if present. Remember the inferred conventions for the rest of the session; don't re-sample per commit. **If history is mixed**, present the candidate styles and ask which to follow rather than picking a tiebreaker silently.

**After `git mv A B`, never include `A` in the next `git add` call.** Git errors on the missing pathspec (A is gone) and silently short-circuits the rest of the add — content edits on other staged files in the same `git add` get dropped, leaving a "successful" commit that's rename-only. Clean form: `git add B <other-edited-files>`. **Verification before commit**: `git diff --cached --stat`; "0 insertions, 0 deletions" on the renamed file is the tell that content edits were dropped — re-add and re-stage.

**Bundle stage + verify + commit in a single Bash call for substantive commits.** When staging accuracy matters (commits touching multiple files, commits where untracked or in-progress files must NOT be bundled in), chain the three operations in one shell turn: `git add <explicit files> && git diff --cached --stat && git commit -m "..."`. `git status` output between `git add` and `git commit` can mislead — staged-state can drift; single-shell-turn bundling closes the gap.

Full table with fallback guidance and recommended git config: `~/dotfiles/claude/references/modern-tooling.md` § "Modern Git Practices".

## Modern Docker & Kubernetes

**Docker**: `docker compose` (v2 plugin) over `docker-compose` (v1 EOL). `docker buildx build` over legacy `docker build`. OrbStack is the local Docker host.

**kubectl**: `kubectl events --for` (1.27+) over field-selector, `kubectl apply --server-side` over client-side, `kubectl explain --recursive` for schema lookup, `k9s` for TUI exploration, `kubectx`/`kubens` for context switching. Don't use `kubectl --record` (deprecated), `kubectl run` for production, or `kubectl rolling-update` (removed). Modern subcommands need a recent server — run `kubectl version` first against remote/proxied clusters.

Full table: `~/dotfiles/claude/references/modern-tooling.md` § "Modern Docker & Kubernetes".

## Modern Language Toolchains

**Python**: `uv` over pip/poetry/virtualenv; `ruff` over flake8+black+isort; `pyright` over mypy; `pyproject.toml` (PEP 621) over setup.py. New packages use `src/` layout. Lockfiles mandatory (`uv.lock`). Type hints on new code. Don't suggest `rye` (archived in favor of `uv`).

**Node.js**: `pnpm` or `bun` over `npm`, `fnm` over `nvm`.

**Go**: `go work` for multi-module, `go test -race ./...` always, `golangci-lint run`.

Match existing repo conventions — don't swap package managers without consent.

Full tables: `~/dotfiles/claude/references/modern-tooling.md` § "Modern Language Toolchains".

## Package Management Principles

**Five universal rules**: (1) Commit lockfiles always. (2) CI installs from lockfile, never resolves fresh. (3) One package manager per ecosystem per repo. (4) Pin runtime/toolchain versions explicitly. (5) Don't swap package managers without consent.

**System-level**: `brew` for everything; `Brewfile` for reproducibility. **Helm**: commit `Chart.lock`, prefer OCI registry charts. **Caveats**: lockfiles drift across platforms (regenerate in CI env, don't re-resolve locally); `go mod tidy` is dev-only (CI should fail if go.mod would change); airgapped environments may need vendoring.

Full per-ecosystem commands and tables: `~/dotfiles/claude/references/modern-tooling.md` § "Package Management Principles".

## Scheduled Routines

Cloud-managed Claude Code routines (claude.ai-hosted, run on a cron, **independent of any local Claude Code session**). Lifecycle is managed via the `/schedule` skill or directly at https://claude.ai/code/routines — entries here are *documentation*, not configuration.

### `claude-md-tooling-audit`

A monthly "modern developer tooling digest" against the categories in this CLAUDE.md (CLI replacements, Git, Docker/Kubernetes, Python, Node, Go, Rust, system package management). Looks for deprecations/archivals (the `dog → doggo`, `rye → uv` pattern), major version bumps that change capability, mainstream-survey-validated new tools, and stale references in the tracked categories. Cites a source URL for every claim; says so explicitly when a source is unreachable rather than fabricating. Web-research-only; the agent is forbidden from editing any file — it produces a report for the user to skim and selectively apply, because CLAUDE.md changes need human review.

**Maintenance**: when adding a new category to this CLAUDE.md (e.g., a new language toolchain section), update the routine's prompt to include it — otherwise the audit will silently miss the new area.

<!-- Org-specific layer (private): a non-public machine appends `@./CLAUDE.<org>.md` here. -->
