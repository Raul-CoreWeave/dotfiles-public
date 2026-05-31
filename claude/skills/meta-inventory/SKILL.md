---
name: meta-inventory
description: Regenerate the Claude Code architecture inventory — enumerate primitives (skills, commands, agents, hooks, MCPs, plugins) across user-level + project-level scopes, plus the persistence roots (CLAUDE.md scopes, memory dirs, todos, watchlists, references). Optionally runs two lints across the persistence graph: dangling-refs (broken markdown links, broken @./ autoloads, stale ~/... references, unresolved memory [[wikilinks]]) and untracked-in-versioned-roots (orphan files in versioned repos like ~/dotfiles/ that were never `git add`ed). Writes a dated inventory doc under ~/.claude/meta-inventory/. Triggers on "/meta-inventory", "regenerate the architecture inventory", "what's installed", "audit my Claude Code setup", "what skills/hooks/MCPs do I have", "scan for dangling refs", "check for stale references", "check for orphan untracked files".
---

# /meta-inventory — Claude Code architecture inventory + persistence-graph lint

Two responsibilities: (1) **inventory** the primitives and persistence-root contents, and (2) **lint** the persistence graph for: (a) dangling references — broken links, broken autoloads, stale tilde-paths, unresolved wikilinks; (b) orphan-untracked files in known-versioned roots (e.g. `~/dotfiles/`) that were never `git add`ed — the pattern that bites when work lands via a symlink and the source-side commit gets forgotten.

Canonical spec for the persistence roots lives in `~/.claude/CLAUDE.md` § "Cross-Session Persistence". Canonical spec for "Picking a primitive" lives in `~/.claude/CLAUDE.md` § "Picking a primitive" — the gap-analysis phase classifies findings against that framework.

## Inputs

`$ARGUMENTS` is one of:

| Form | Meaning |
|---|---|
| (empty) | Run both inventory + lint, write the inventory doc, surface lint findings inline |
| `inventory` | Inventory only — skip lint |
| `lint` | Lint only — skip inventory write |
| `--dry-run` | Run both, print to stdout, do NOT write the doc |

## Phase 1 — Inventory

Run the deterministic data-gathering script:

```bash
~/.claude/skills/meta-inventory/scripts/meta-inventory.sh
```

Emits a markdown document on stdout with two top-level sections:
- **§ 1. Primitives currently installed** — user-level + project-level skills, commands, agents, hooks, MCPs, plugins. Counts inline. Hooks rendered as event/matcher/handler/purpose tables. Also includes a sub-section "Claude Code built-in slash commands" sourced from `~/.claude/commands/util.md` if present — the harness-binary built-ins (`/compact`, `/clear`, `/sandbox`, etc.) that don't live on the filesystem and would otherwise be invisible to a filesystem-walking inventory. Snapshot freshness is the maintainer's responsibility (re-paste `/help` when a new Claude Code version ships).
- **§ 2. Persistence roots** — CLAUDE.md scopes (with size + last-modified), memory directories (file count + last-modified), todos categories (file count + open/closed counts), watchlists (file count), and the reference catalog.

The script reads metadata from disk; it does NOT classify primitives as well-routed vs mis-routed (that's the LLM's job in Phase 3).

The script's project-scope discovery and any project-specific roots are configured at the top of `meta-inventory.sh` via the `PROJECT_ROOT` and adjacent variables — point them at the repo(s) you work in.

## Phase 2 — Lints

Skip if `$ARGUMENTS = inventory`. Two independent lints run as siblings; each
prints its own section and can be wired to its own SessionStart hook for the
at-session-start one-liner. Run both:

```bash
~/.claude/skills/meta-inventory/scripts/check-dangling-refs.sh
~/.claude/skills/meta-inventory/scripts/check-untracked-versioned.sh
```

### 2a — Dangling refs

Emits a markdown section listing dangling references grouped by type:
- **Broken markdown links** — `[text](path)` where `path` doesn't exist
- **Broken `@./` autoloads** — relative imports in CLAUDE.md files that don't resolve
- **Stale `~/...` references** — tilde-prefixed paths in prose that don't exist on disk; both file refs (e.g. `~/foo/bar.md`) and directory refs (trailing-slash, e.g. `~/foo/bar/`) are checked, and a path followed by an annotation inside the same backtick (`~/foo/bar.md § Phase 1.5`) is matched correctly
- **Unresolved `[[wikilinks]]`** — memory cross-links to slugs that aren't a memory file

False positives are suppressed for: code blocks (fenced or inline), lines containing `<placeholder>` syntax (`<name>`, `<slug>`, `<domain>`, `<repo>`, `<mode>`, `<YYYY>`, `<category>`) OR ellipsis placeholders (`~/.../foo/`), URL schemes (`http://`, `https://`, `mailto:`, etc.), self-referencing inventory output docs (`*claude-arch-inventory*.md` — they quote stale paths as data), and a small allow-list of ambient paths the script documents inline.

Exit code is non-zero if any dangling refs found. Can be wired into a SessionStart hook that surfaces a `[dangling-refs]` one-line summary at session start when findings exist.

### 2b — Untracked in versioned roots

Catches the orphan-untracked-file pattern: a file created via a symlink (e.g., a new skill / hook / memory entry written through `~/.claude/...` that resolves through to `~/dotfiles/...`) appears live to the running system but is invisible to the dotfiles repo's git unless someone remembers to `git add` it on the dotfiles side. Same pattern applies to any code repo where work-in-progress files can pile up untracked.

Scans `git ls-files --others --exclude-standard` per root (honors each repo's `.gitignore`). Only flags **untracked** files; modified files are explicit work-in-progress and not the concern here. The roots scanned are listed in the `ROOTS=(...)` array in the script — edit it to point at your versioned repos (defaults to `~/dotfiles/`).

Exit code is non-zero when orphans exist. Can be wired into a SessionStart hook that surfaces an `[untracked]` one-line summary at session start. Pairs with the global `CLAUDE.md` § "No orphan-untracked files in versioned roots" rule — the rule is the discipline at the action site; the hook is the backstop.

## Phase 3 — Gap analysis (LLM)

After both scripts run, reason over the output to produce a § "Gap analysis" section:

- **A. Mis-routed primitives** — anything failing the "Picking a primitive" decision tree (e.g., scripts-less skill always typed by user → should be slash command).
- **B. Underused skills** — anything with zero recent invocations; classify as *infrequently relevant* (keep) vs *forgotten / not discoverable* (surface or remove).
- **C. Missing primitives** — gaps with no current home (compare to in-flight todos).
- **D. Persistence-root anomalies** — categories with no recent activity, watchlists not posted in >30d, etc.

Recent-invocation data comes from a transcript-archive grep emitting NDJSON `{skill, session, ts, file}` per invocation (e.g. a `grep-skill-invocations.sh` helper alongside `/meta-rules`). Default `--since 90d`; pass `--include-builtins` to count `/clear`, `/rename`, etc. (excluded by default).

Recommended invocation for this phase, if you maintain such a helper:

```bash
~/.claude/skills/meta-rules/scripts/grep-skill-invocations.sh --since 90d \
  | jq -r '.skill' | sort | uniq -c | sort -rn
```

Cross-reference the count table against the Phase 1 installed-skills inventory to find skills with zero or near-zero recent invocations. Classify as *infrequently relevant* (keep) vs *forgotten / not discoverable* (surface or remove) — the script provides the data; the LLM-side reasoning classifies.

## Phase 4 — Write the doc

Skip if `$ARGUMENTS = lint` or `--dry-run`.

Path: `~/.claude/meta-inventory/<YYYY-MM-DD>-claude-arch-inventory.md`.

If the file exists, the prior content is replaced. The doc is regeneratable.

If the dated file does NOT exist, create it with header:

```markdown
# Claude Code architecture — inventory + lint

Date: <YYYY-MM-DD>
Scope: regenerated by /meta-inventory skill
```

Then append the three sections in order: Inventory (Phase 1 output), Lint findings (Phase 2 output), Gap analysis (Phase 3 prose).

## Phase 5 — Surface lints to user

If `check-dangling-refs.sh` exited non-zero, surface — *"<N> dangling refs found across <M> files; details in <path>"*. If `check-untracked-versioned.sh` exited non-zero, surface — *"<N> orphan-untracked files in <M> versioned roots; details in <path>"*. Don't auto-fix either — surface only. Dangling-ref fixes route through a KB-fix flow (KB-shaped) or manual Edit (memory / CLAUDE.md); untracked-file fixes are a manual `git add` / `git rm` / `.gitignore` extension on the owning repo.

## Output

Print the final inventory file's path + lint summary. Don't dump the full doc to chat — it's a multi-thousand-line file the user reads in their editor.
