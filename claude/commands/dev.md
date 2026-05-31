---
description: Categorized index of dev-workflow slash commands — build/run/verify, PR + review, parallel + batch execution, Claude Code apparatus management (settings, hooks, permissions), code-search, and authoring (skills, docs, API). Mostly Claude-Code-shipped built-in skills (un-renameable). Maintained by editing ~/dotfiles-public/claude/commands/dev.md.
---

Print the body below verbatim. The catalog covers dev-workflow slash commands across built-in skills, user skills, and plugin skills. If the user asks about a command not listed, say so — don't invent entries.

```
Dev-workflow slash commands
===========================

Build / run / verify
  /run                   launch + drive the project's app
  /run-skill-generator   author/improve the run-<unit> skill for a project
  /verify                verify a code change works in the running app
  /debug                 enable debug logging for this session

Parallel + batch + scheduled
  /batch                 plan large-scale change; parallel worktree agents (5-30 PRs)
  /loop                  run a prompt/slash-command on a recurring interval
  /schedule              create/manage scheduled remote agents (cron routines)

PR / review (built-ins, then plugins, then orchestrator)
  /review                review a pull request (built-in command, via /help)
  /security-review       security review of pending changes (built-in command)
  /code-review           review current diff for correctness (built-in skill)
  /code-review:code-review            plugin variant — review a pull request
  /deep-review:deep-review            multi-lens (correctness+sec+arch+history)
  /feedback-driven-dev:feedback-driven-dev  full feedback-to-PR workflow
  /dev-gh-pr                 PR-prep orchestrator: preflight → simplify → deep-review
                         → triage → feedback-driven-dev → PR draft

Code search
  /sourcegraph:searching-sourcegraph  Sourcegraph-indexed codebase search

API / SDK development
  /claude-api            build/debug/optimize Claude API / Anthropic SDK apps

Authoring (skills, docs, CLAUDE.md)
  /skill-creator:skill-creator        create/modify/measure skill performance
  /docs:docs                          author technical docs end-to-end
  /claude-md-management:claude-md-improver       audit + improve CLAUDE.md files
  /claude-md-management:revise-claude-md         update CLAUDE.md from session
  /sync-skill-docs                    enforce skill ↔ doc-reference sync

Apparatus / settings management
  /update-config         configure Claude Code harness via settings.json
  /fewer-permission-prompts  scan transcripts; allowlist to .claude/settings.json
  /keybindings-help      customize keyboard shortcuts (chord bindings)  [unverified]

Session state + setup
  /remember:remember                  save session state for clean continuation
  /claude-code-setup:claude-automation-recommender   analyze codebase + recommend
                                                     hooks/agents/skills/plugins

Notes
- Most entries here are Claude-Code-shipped built-in skills — they can't
  be renamed, aliased, or symlinked. Plugin skills carry the plugin:
  prefix; user-installable skills (sync-skill-docs, dev-gh-pr) don't.
- See /util for harness-built-in commands (clear, compact, plan, agents,
  hooks, permissions, etc.).
- See the meta-* skills (meta-all, meta-inventory, meta-rules, meta-memory-audit,
  …) for apparatus self-audit + memory-hygiene.
- /code-review (built-in skill) and /code-review:code-review (plugin
  command) coexist: the built-in scans the current diff at tunable
  effort; the plugin reviews a PR (broader scope).
```
