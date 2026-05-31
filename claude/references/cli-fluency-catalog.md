# CLI fluency coaching — zsh idioms + modern tool catalog

Catalog of zsh idioms, modern CLI replacements, and one-liner patterns I can surface as `Shell tip:` footers. Expansion of `~/.claude/CLAUDE.md` § "Coach toward command-line and zsh fluency."

## Format

```zsh
# Shell tip: <one-sentence what + why>
<command>
```

Always in a fenced `zsh` code block (renders monospace, copy-pastable). Use the preferred modern tools per the "Preferred CLI Tools" section of global CLAUDE.md — `rg` not `grep -r`, `fd` not `find`, etc. Combine with `Power-user note:` as separate footers when both apply (one footer per type, max).

## When to emit

1. **Multi-command snippet has a one-liner equivalent.** User chained `find … | xargs grep …` where `rg --type` or `rg -g '<glob>'` does it in one call.
2. **Generic POSIX tool where a modern alternative is installed.** `grep -r` → `rg`; `find -name` → `fd`; `sed -i` → `sd`; `cat` → `bat`; `ls -la` → `eza -lh --git`; `ps aux | grep` → `procs <name>`; `du -sh *` → `dust`; `df -h` → `duf`; `top` → `btm`; `curl` → `xh`; `cd <long path>` → `z <hint>` (zoxide); `nslookup` → `doggo`; `traceroute` → `mtr`; `ping` → `gping`; `scp` → `rsync -aP`; `du | sort` → `ncdu`.
3. **zsh idiom available for the manual operation.** Examples:
   - Loop over files matching pattern → `for f in **/*.json(N); do …` (`**/*` recursive glob, `(N)` qualifier = silent on no-match).
   - Bulk rename → `zmv '(*).txt' '$1.md'`.
   - Re-run previous with substitution → `^old^new` or `!!:gs/old/new/`.
   - Repeat last argument → `!$` or `<Esc>.`.
   - Process substitution → `diff <(cmd1) <(cmd2)`.
   - Parameter expansion: `${var:gs/old/new/}`, `${var:t}` (tail), `${var:h}` (head), `${var:r}` (remove ext), `${var:e}` (ext).
   - Glob qualifiers: `(N)` nullglob, `(.)` regular files only, `(/)` dirs only, `(om[1])` order-by-mtime first, `(L+1M)` >1MB.
4. **User installed a one-shot that should be an alias/function.** E.g., they typed `git log --oneline -20 --graph --all` → suggest a `gloga` alias.
5. **User reached for a portable POSIX form when zsh has it built-in.**

## When to skip

- The user's command is already optimal.
- The user has already run the command (suggesting the alternative after-the-fact is condescending; reserve for "next time" framing only when high-value).
- The tip would be trivially well-known (don't suggest `ls` exists).
- The prompt isn't shell-expressible (a chat message, a doc question).

## Catalog

### Modern tool replacements

| Old | New | Why |
|---|---|---|
| `grep -r 'pat' .` | `rg 'pat'` | parallel, gitignore-aware, faster |
| `grep -rl` | `rg -l` | same |
| `find . -name '*.go'` | `fd -e go` or `fd '\.go$'` | gitignore-aware, parallel |
| `find . -type f -newer X` | `fd --newer X` | same |
| `sed -i 's/x/y/g' file` | `sd 'x' 'y' file` | sane regex, no backslash hell |
| `cat file` | `bat file` (alias `cat`) | syntax highlight, line numbers |
| `ls -la` | `eza -lha --git` (alias `ll`/`la`) | git status, icons, sane defaults |
| `ps aux | grep X` | `procs X` | tree view, colorized |
| `du -sh *` | `dust` | tree, colored, sorted |
| `df -h` | `duf` | tabular, colored, filtered |
| `top` | `btm` (alias OK) | mouse, scrollable, GPU |
| `curl -sL url` | `xh url` | JSON-aware, syntax highlight |
| `cd ~/long/path` (typed often) | `z hint` | zoxide; learn from history |
| `nslookup host` | `doggo host` | parallel, JSON option |
| `traceroute host` | `mtr host` | live, packet loss column |
| `ping host` | `gping host` | live graph |
| `scp -r src dst` | `rsync -aP src dst` | resumable, progress |
| `du | sort | head` | `ncdu .` | interactive |
| `jq` on huge files | `jaq` | faster on cold JSON |

### zsh idiom quick-reference

**Globbing qualifiers** (suffix glob with `(...)`):
- `(N)` — nullglob: empty if no match (vs error)
- `(.)` — regular files only
- `(/)` — directories only
- `(@)` — symlinks only
- `(om[1])` — order by mtime, take first (newest)
- `(L+1M)` — size > 1 MB; `(L-1M)` for < 1 MB
- `(mh-24)` — modified within last 24 hours
- Combine: `**/*.json(.NL+1M)` = all `.json` files, regular, nullglob, > 1MB.

**Parameter expansion**:
- `${var:t}` — tail (basename)
- `${var:h}` — head (dirname)
- `${var:r}` — remove last extension
- `${var:e}` — extension only
- `${var:gs/foo/bar/}` — global substitute (sed-style)
- `${(L)var}` / `${(U)var}` — lowercase / uppercase
- `${(j:,:)array}` — join array with `,`
- `${(f)$(cmd)}` — split command output on newlines

**History expansion** (one of the highest-leverage zsh features):
- `!!` — last command
- `!$` — last arg of last command
- `!*` — all args of last command
- `!n` — command N from history
- `!:gs/old/new` — last command with substitution
- `^old^new` — quick last-cmd substitution

**zmv** — bulk rename with glob patterns:
```zsh
autoload -U zmv
zmv '(*).txt' '$1.md'           # *.txt → *.md
zmv '(**/)(*).py' '$1${2:l}.py' # lowercase all .py files recursively
```

**Process substitution**:
- `diff <(cmd1) <(cmd2)` — diff outputs without temp files
- `vim <(curl url)` — open command output in vim
- `<(cmd) >(cmd)` — read from / write to a subprocess

## Format examples

Tip after a `find ... | xargs grep ...` chain:

```zsh
# Shell tip: rg with --type / -g handles this in one call, parallel + gitignore-aware
rg --type=yaml 'some_setting'
```

Tip after a manual `for f in $(find ...)`:

```zsh
# Shell tip: zsh recursive glob + qualifier — no subshell, no word-splitting hazards
for f in **/*.json(N.); do echo "$f"; done
```

Tip after the user typed a long path twice:

```zsh
# Shell tip: zoxide learns from history; `z` jumps by hint after first cd
z myproject   # → /Users/you/path/to/myproject
```

## Anti-pattern

Suggesting a shell tip when the user is mid-debugging a real issue — derails attention. Save for end of turn, after the primary task lands. Same for chaining tips: pick the single highest-leverage one, not three.
