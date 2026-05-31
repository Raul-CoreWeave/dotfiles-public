---
description: Categorized list of Claude Code built-in slash commands — the ones owned by the harness (`/compact`, `/btw`, `/sandbox`, etc.) that can't be renamed, aliased, or symlinked. Verified against live `/help` output 2026-05-25 (Claude Code 2.1.150). Maintain by editing ~/dotfiles/claude/commands/util.md; re-paste `/help` whenever a new version ships.
---

Print the body below verbatim. The catalog is a snapshot of `/help` output from Claude Code 2.1.150 (2026-05-25). If the user asks about a command not listed, say so — don't invent entries. If the user notices drift (a new built-in appeared, an old one was removed), re-seed by pasting current `/help` and updating this file.

```
Claude Code built-in slash commands
====================================
Snapshot: 2026-05-25 (Claude Code 2.1.150)

Conversation control
  /clear                 start a new session with empty context; previous stays resumable
  /compact               free up context by summarizing the conversation so far
  /rename                rename the current conversation
  /exit                  exit the CLI
  /resume                resume a previous conversation
  /branch                create a branch of the current conversation at this point
  /rewind                restore code and/or conversation to a previous point
  /recap                 generate a one-line session recap now
  /background            send this session to the background; free the terminal

Account + model
  /login                 sign in with your Anthropic account
  /logout                sign out from your Anthropic account
  /model                 set the AI model for Claude Code (current: Opus 4.7 1M)
  /effort                set reasoning effort level
  /fast                  toggle fast mode (Opus 4.7 only — faster output)
  /advisor               configure the Advisor Tool (consult stronger model)
  /usage                 show session cost, plan usage, and activity stats
  /usage-credits         configure usage credits to keep working at limit

Workflow + code
  /plan                  enable plan mode or view current session plan
  /goal                  set a goal — keep working until condition is met
  /tasks                 list and manage background tasks
  /init                  initialize a new CLAUDE.md file with codebase docs
  /diff                  view uncommitted changes and per-turn diffs
  /context               visualize current context usage as a colored grid
  /copy                  copy Claude's last response (or /copy N for Nth-latest)
  /export                export current conversation to file or clipboard
  /review                review a pull request
  /security-review       security review of pending changes on current branch
  /autofix-pr            monitor and autofix issues with current PR
  /ultraplan             Claude Code on the web drafts a plan you can approve
  /ultrareview           multi-agent cloud review (~5-10 min, $5-25)
  /team-onboarding       create a teammate-onboarding guide from your usage

Diagnostics + status
  /doctor                diagnose and verify Claude Code install + settings
  /status                show version, model, account, API connectivity, tools
  /help                  show help and available commands
  /release-notes         view release notes
  /insights              generate a report analyzing your sessions
  /feedback              submit feedback, report a bug, share conversation

Settings + UI
  /config                open config panel
  /theme                 change the theme
  /color                 set the prompt bar color for this session
  /keybindings           open / create keybindings configuration file
  /terminal-setup        enable Option+Enter for newlines and visual bell
  /tui                   set terminal UI renderer (default | fullscreen)
  /statusline            set up Claude Code's status line UI
  /focus                 toggle focus view (prompt + tool summary + final)
  /voice                 toggle voice mode
  /sandbox               manage Bash sandbox (permissions, network, FS)

Multi-device + remote
  /desktop               continue current session in Claude Desktop
  /mobile                show QR code to download mobile app
  /teleport              resume a session from claude.ai
  /remote-control        control this session from your phone or claude.ai/code
  /remote-env            configure default remote environment for teleport
  /chrome                Claude in Chrome (beta) settings
  /ide                   manage IDE integrations + show status

Apparatus management
  /skills                list available skills
  /agents                manage agent configurations
  /plugin                manage Claude Code plugins
  /reload-plugins        activate pending plugin changes in current session
  /hooks                 view hook configurations for tool events
  /permissions           manage allow & deny tool permission rules
  /memory                edit Claude memory files
  /mcp                   manage MCP servers
  /add-dir               add a new working directory
  /install-github-app    set up Claude GitHub Actions for a repository
  /install-slack-app     install the Claude Slack app

Side / fun
  /btw                   ask a quick side question without interrupting flow
  /stickers              order Claude Code stickers
  /radio                 listen to Claude FM lo-fi radio
  /powerup               discover Claude Code features via quick lessons

Built-in skills (Claude-Code-shipped; appear in /help "Custom commands" section)
  These ship with Claude Code as default skills (typeable; appear in hint
  menu). Distinct from built-in commands above (which appear in /help
  "default commands") and from user/project/plugin skills (which appear
  with scope tags in the Custom commands section).

  /batch                 research+plan large-scale change; parallel worktree agents (5-30 PRs)
  /verify                verify a code change by running the app + observing
  /run                   launch and drive the project's app
  /run-skill-generator   author/improve the run-<unit> skill for a project
  /loop                  run a prompt or slash command on a recurring interval
  /schedule              create/manage scheduled remote agents (cron routines)
  /code-review           review current diff for correctness bugs (severity tunable)
  /claude-api            build/debug/optimize Claude API / Anthropic SDK apps
  /update-config         configure Claude Code harness via settings.json
  /fewer-permission-prompts  scan transcripts; add allowlist to .claude/settings.json
  /debug                 enable debug logging for this session
  /keybindings-help      customize keyboard shortcuts                  [unverified]

Notes
- Built-ins are owned by the Claude Code harness. They cannot be renamed,
  aliased, or symlinked. User commands can't proxy to them.
- For installed skills (user / project / plugin), type `/` and start typing —
  the hint menu narrows on fuzzy match. Plugin skills appear with
  `plugin:skill` prefix.
- `/help` IS the canonical source — but it has TWO sections that must
  both be read:
    1. "default commands" — built-in commands (the ones in this file's
       categories 1-8 above).
    2. "Browse custom commands" — built-in skills + user/project/plugin
       skills + MCP-registered slash commands. Scoped entries are tagged
       (project), (user), or (plugin-name) in parentheses at the end of
       the description. Untagged entries in this section are Claude-
       Code-shipped built-in skills (the category 9 list above).
  Scroll the dialog with arrow keys; `/help` doesn't work in `--print`
  mode so it must be invoked live and pasted.
- /skills lists only user-installable INSTALLED skills (a subset of
  /help's Custom commands). Useful for cross-checking scope tags +
  per-skill token costs, not for completeness.
- Tertiary cross-check (drift-detection only) — binary strings dump
  (word-boundary, NOT line-anchored — line-anchor misses everything
  embedded in error messages / help text / prose):
      strings $(readlink $(which claude)) \
        | rg -oN '\B/[a-z][a-z0-9-]{2,20}\b' | sort -u
```
