---
name: surface changes made outside the current repo
description: Always surface to the user when an edit is being made outside the current working repo, and state the absolute path. Group the recap by location at end-of-turn when changes spanned multiple places.
type: feedback
---
When making or about to make changes outside the current working repo (CWD's git root), always surface the location explicitly. State the absolute path so the user can navigate or audit. Don't quietly cross-write across repos / dotfiles / user-global state.

**Why:** Work spans many locations (code repos for project work, ~/dotfiles/ for versioned config sources, ~/.claude/ for global Claude state, ~/.claude/projects/<slug>/memory/ for auto-memory). In focus mode the user sees only the final text message of each turn — progress narration between tool calls is invisible. If a turn writes to ~/.claude/projects/.../memory/*.md *and* ~/dotfiles/* *and* some other code repo, the user cannot reconstruct from the final text alone where the artifacts landed unless I explicitly say so. Multi-location confusion compounds across sessions and makes audit / rollback / dotfiles-port impossible.

**How to apply:**

1. **Before writing or editing a file outside the current repo,** state where and why in user-visible text. Format: "Editing `<absolute path>` — <which location-class this is> (current repo / a different code repo / your dotfiles / user-global Claude state / etc.)." Single sentence is enough; no need to belabor.

2. **Treat these locations as "external" relative to any current-repo work** and always surface:
   - `~/.claude/**` — user-global Claude state (CLAUDE.md, settings.json, settings.local.json, skills/, agents/, plugins/, projects/<slug>/memory/, debug/, keybindings.json)
   - `~/dotfiles/**` — versioned config sources (the user edits source under `dotfiles/<module>/`, symlinks reflect it; never edit the symlink target directly)
   - Any other code repo when working from inside a different one
   - System files outside `$HOME` (e.g., `/Library/Application Support/...`)
   - Anything explicitly outside the user's CWD's git root

3. **For routine in-repo edits** (CWD is some repo and you're editing files inside that repo), no special callout — the user expects in-repo work without narration.

4. **At end-of-turn, when changes spanned multiple locations,** include a brief recap grouped by location class. Format:

   > **Files touched:**
   > - In `<current repo>` (relative paths): `<file1>`, `<file2>`
   > - In `~/.claude/projects/<slug>/memory/`: `<file3>`
   > - In `~/dotfiles/<module>/`: `<file4>`

   Skip the recap for single-location turns — it's only valuable when the user couldn't otherwise reconstruct what landed where.

5. **For destructive cross-location operations** (rm under `~/.claude/`, `~/dotfiles/` symlink target overwrites, edits to other repos' branches), confirm before acting per the existing "executing actions with care" principle. The transparency rule above is necessary but not sufficient — surfacing isn't a substitute for permission on risky moves.

6. **Never cross-write silently to:**
   - `~/.claude/settings.json` / `settings.local.json` — these affect every Claude Code session; always announce.
   - `~/dotfiles/**` — sync sources for every machine that runs `install.sh`; always announce.
   - `~/.gitconfig` (which is a symlink to `~/dotfiles/shell/gitconfig`) — git config changes apply to every repo on the machine; always announce per the existing git-safety protocol.
   - Files outside `$HOME` — almost certainly not what the user wants without explicit ask.

The principle: **the user should never be surprised by an edit's location.** If the path isn't obviously where the conversation has been focused, surface it.
