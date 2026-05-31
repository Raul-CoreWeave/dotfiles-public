# dotfiles

Personal macOS dotfiles + Claude Code apparatus (global `CLAUDE.md`, skills,
hooks, references). Public, portable core — organization-specific scopes are
kept in a separate private overlay and are not part of this repo.

## Layout

```
CLAUDE.md / claude/CLAUDE.md   global, machine-portable Claude Code guidance
claude/hooks/                  SessionStart + doc-sync hooks
claude/plugins/                installed plugin manifest
claude/references/             tooling / fluency reference catalogs
config/                        starship, atuin
shell/                         zshrc.template, zprofile, gitconfig, ssh-config
Brewfile.personal              personal Homebrew bundle
tools/pipx.txt                 pipx tools
install.sh / bootstrap.sh      symlink installer + fresh-machine bootstrap
```

## Install

```sh
git clone https://github.com/<you>/dotfiles ~/dotfiles
cd ~/dotfiles && ./install.sh
```

`install.sh` symlinks tracked files into place (`~/.claude/CLAUDE.md`,
`~/.gitconfig`, `~/.zprofile`, `~/.ssh/config`, …). Source-of-truth lives here;
edit under `~/dotfiles/<module>/`, never the installed symlink. `~/.zshrc` is a
per-machine copy of `shell/zshrc.template` (not a symlink) — port changes back
by hand.

## Conventions

- Secrets never live in the repo (`.gitignore` blocks `.env` / `*.pem` /
  `*.key` / `*_token`); load tokens from a secret manager at shell startup.
- `claude/CLAUDE.md` is the global Claude Code behavior spec — start there to
  see the working-style, memory-hygiene, and primitive-picking conventions.
- Org/job-specific Claude guidance lives in a private `CLAUDE.<org>.md` overlay
  imported at the bottom of `claude/CLAUDE.md` on non-public machines; it is not
  in this repo by design.
