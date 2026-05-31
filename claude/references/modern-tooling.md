# Modern Tooling Reference

Full preference tables with fallback guidance, caveats, and configuration
recommendations. The condensed rules live in `~/.claude/CLAUDE.md`; this file
has the detail for edge cases.

## Preferred CLI Tools — Full Table

| Prefer | Over | Why | When to fall back |
|--------|------|-----|-------------------|
| `rg` | `grep` | Faster, recursive by default, respects `.gitignore`, smart-case | POSIX scripts meant to run elsewhere; piping into tools that expect GNU-grep flags; intentionally searching ignored/hidden files (use `rg -uu` instead) |
| `fd` | `find` | Faster, intuitive syntax, gitignore-aware, parallel | Complex `-mtime`/`-newer`/`-perm` predicates `fd` doesn't support; chained `-exec` with shell substitutions; portable scripts |
| `sd` | `sed -i` | Simpler regex, no backslash-escape soup, atomic writes | Stream pipelines (`sd` is file-oriented); GNU sed feature you actually need (`-e` chains, addresses) |
| `bat` | `cat` | Syntax highlighting, line numbers (`--paging=never` already aliased) | Piping raw bytes into another tool — use `cat` (or `bat -p` for plain output) |
| `eza` | `ls` | Git status column, tree mode, better defaults | Scripts that parse output (don't parse `ls`, but if forced, use raw `ls`) |
| `procs` | `ps` | Tree view, colorized, friendlier filters | Existing `ps`-flagged commands in muscle memory or scripts |
| `delta` | `git diff` / `diff` | Side-by-side, syntax-aware | CI logs or piped artifacts that need raw unified diff |
| `dust` | `du` | Visual size tree, sane sort | Need exact byte counts piped into another tool (`du -b`) |
| `duf` | `df` | Colorized table, filters overlay/snap noise, sane defaults | Scripts that parse `df` output; need a specific column `duf` doesn't expose |
| `btm` | `top` | Better TUI, history graphs, mouse | Headless / scripted contexts (use `ps`/`procs` instead — neither `btm` nor `top` belongs there) |
| `xh` | `curl` | HTTPie-style ergonomic syntax (`xh GET url key==val`), single static binary, fast startup | Anything that needs `curl`-exact flags (`--cacert`, `-H` ordering, binary upload, `--resolve`); environments where a corporate CA bundle is wired for `curl` |
| `tldr` | `man` | Quick task-oriented examples | `tldr` does not replace `man` — use `man` for the authoritative reference |
| `zoxide` (`z`) | `cd` | Frecency jumps to recently visited dirs | First-time dirs or absolute paths |
| `fzf` | manual filtering | Interactive fuzzy filter for any line-based input | Non-interactive / scripted contexts |

**Caveats:**

1. **Dedicated Claude Code tools (Read, Edit, Write, Grep) take priority over Bash for their respective operations** per the system prompt. `rg` is for shell-only situations where the Grep tool doesn't fit (e.g., piping into another shell command); it does not replace the Grep tool.
2. **`rg` and `fd` skip `.gitignore`d and hidden files by default.** When the intent is to search inside `.git/`, `node_modules/`, or any ignored path, add `-uu` (rg) or `--no-ignore --hidden` (fd) — otherwise the search silently misses matches.
3. **For portable shell scripts that may run on CI runners or other machines, use POSIX commands (`grep`, `find`, `sed`).** Modern alternatives are local-dev luxuries; don't bake them into committed scripts unless they are explicitly part of the target environment.
4. **When in doubt, run the traditional command** — it is universally understood, ubiquitous in docs, and won't surprise the user.

## Modern Git Practices — Full Table

| Prefer | Over | What it does | When to fall back |
|--------|------|--------------|-------------------|
| `git switch <branch>` | `git checkout <branch>` | Switch branches — that's all it does | Switching to a tag/commit (detached HEAD) — `git switch --detach <ref>` works, but `git checkout <ref>` is shorter for one-offs |
| `git switch -c <branch>` | `git checkout -b <branch>` | Create + switch | — |
| `git switch -` | `git checkout -` | Toggle to previous branch | — |
| `git restore <file>` | `git checkout -- <file>` | Discard working-tree changes | — |
| `git restore --staged <file>` | `git reset HEAD <file>` | Unstage without touching working tree | When you also need to move HEAD (use `git reset` with intent) |
| `git restore --source=<ref> <file>` | `git checkout <ref> -- <file>` | Pull a single file from another commit | — |
| `git push --force-with-lease --force-if-includes` | `git push --force` | Refuses to overwrite if remote moved or if it would drop commits you haven't fetched | **Never** on `main`/`master`/protected branches; always require explicit user confirmation per the system prompt |
| `git stash push -m "msg"` | `git stash save -m "msg"` | `save` is deprecated | — |
| `git rebase --autostash` | manual `stash`/`rebase`/`stash pop` | Stashes uncommitted work, rebases, restores | When you want a named stash to keep around |
| `git fetch --prune` | `git fetch` | Drops stale remote-tracking refs | — |
| `git branch --sort=-committerdate` | unsorted `git branch` | Recently-touched branches first | — |
| `git worktree add <path> <branch>` | stash + branch switch | Parallel branch in a sibling directory, no context loss | Single-branch sessions |

**Configuration that pays for itself** (suggest to user; don't apply without consent):
- `git config --global pull.rebase true` — linear history by default
- `git config --global rebase.autostash true` — eliminates the manual stash dance during pull/rebase
- `git config --global push.autoSetupRemote true` — first push of a new branch works without `-u origin <name>`
- `git config --global rerere.enabled true` — Git remembers how you resolved a conflict and re-applies it
- `git config --global fetch.prune true` — auto-prune stale remote refs on every fetch

**Caveats:**

1. **Scripts, CI, hooks, and aliases parsing git output** — don't replace `git checkout` with `git switch` in committed code without verifying every consumer. The two share most behavior but their output formats differ in edge cases.
2. **External tutorials, runbooks, vendor docs** still default to `checkout`/`reset`. When pasting a snippet into a comment or message, leave it as written rather than rewriting silently.
3. **Force pushing** — the system prompt already requires explicit user confirmation for any force push. `--force-with-lease --force-if-includes` is the safer mechanic but does not waive that confirmation.
4. **Per-repo conventions still win.** Modern command choices don't change commit message style — match whatever the repo already uses (conventional commits with scope, imperative present tense without prefix, etc.).

## Modern Docker & Kubernetes — Full Table

**Docker / Compose:**

| Prefer | Over | Why | Fallback |
|--------|------|-----|----------|
| `docker compose ...` | `docker-compose ...` | v1 (Python) was EOL June 2023; v2 plugin is faster, official, ships with modern Docker installs. | A pinned legacy CI image still on v1 |
| `docker buildx build` (default builder now) | classic `docker build DOCKER_BUILDKIT=0` | BuildKit caching, multi-stage parallelism, `--platform linux/amd64,linux/arm64` | Rare legacy-builder-only features |
| `docker container prune` / `docker image prune -a` / `docker system prune --volumes --filter "until=24h"` | manual `docker rm $(docker ps -aq)` etc. | Targeted, scriptable, filterable | — |

**kubectl:**

| Prefer | Over | Why | Fallback |
|--------|------|-----|----------|
| `kubectl events --for <kind>/<name>` (1.27+) | `kubectl get events --field-selector involvedObject.name=...` | Sorted by event time, native `--watch`, scoped to a resource | Clusters older than 1.27 |
| `kubectl debug node/<node> --image=<img>` (1.25+) | nsenter via SSH | Ephemeral debug pod with host PID/net namespaces, works without node SSH | When a tool isn't in any debug image |
| `kubectl apply --server-side` | `kubectl apply` (client-side) | Field-level ownership, no `last-applied-configuration` annotation bloat, plays nicely with controllers | First adoption may need `--force-conflicts` once |
| `kubectl get -o jsonpath=` / `-o go-template=` for simple extraction | `kubectl get -o json \| jq ...` for shell pipelines | One process, no jq dep, no quoting hell — but jq wins for non-trivial transforms | Complex transforms → pipe to `jq`/`yq` |
| `kubectl explain <kind>.<field> --recursive` | grepping API docs | Authoritative schema for the connected cluster | — |
| `k9s` | repeated `kubectl get` loops | TUI dashboard for live exploration | Scripts |
| `kubectx` / `kubens` | `kubectl config use-context ...` / `kubectl -n ...` | One-keystroke context/namespace switches | Scripts (use explicit `--context` and `--namespace` flags) |

**Don't use:** `kubectl --record` (deprecated since 1.12), `kubectl run` for production workloads, `kubectl rolling-update` (long removed).

**Caveat:** Modern subcommands need a recent server. Run `kubectl version` first if unsure — managed/remote clusters can be on older minor versions.

## Data & Network Tooling — Full Table

| Prefer | Over | Why | Fallback |
|--------|------|-----|----------|
| `jq` / `jaq` | `python -c "import json"` shell pipelines | Purpose-built; `jaq` is a Rust port that's faster but slightly behind on filter coverage — use `jq` for full compatibility, `jaq` when speed matters and the filter is simple | Complex transforms requiring real code → use Python |
| `yq` (Mike Farah's Go version) | shell `awk`/`sed` on YAML, or Python `pyyaml` one-liners | Native YAML; jq syntax; converts YAML↔JSON↔TOML. Verify it's the Go version (`yq --help` shows `eval`/`eval-all`), NOT the Python `yq` wrapper | Real code for non-trivial transforms |
| `dasel` | one-tool-per-format | One binary, format auto-detect via extension or `-r json`/`-r yaml` | Format-native tool when transforms are non-trivial — `jq`/`yq` have deeper feature sets |
| `dig +short <name>` / `doggo <name>` | `nslookup` | `nslookup` is interactive-mode oriented and noisy; `dig +short` is one line; `doggo` adds color and JSON output (`--json`). `dog` was archived upstream — use `doggo`. | Anything that already works |
| `mtr <host>` | `traceroute` | Continuous probe with per-hop loss/jitter — far more diagnostic for networking triage | Single-shot path discovery |
| `gping <host>` | `ping` | Multi-host side-by-side latency graph | Scripted RTT collection |
| `netstat -anv` / `lsof -i` on macOS | (Linux `ss -tnlp` doesn't exist here) | macOS-native equivalents | — |
| `rsync -aP` | `scp` | Resumable, partial-file delta, progress, preserves attrs | Single small file over interactive ssh |
| `ncdu` | `du \| sort -rh \| head` | Interactive disk-usage navigator | One-shot byte counts |

## Modern Language Toolchains — Full Table

**Python:**

| Prefer | Over | Why | Fallback |
|--------|------|-----|----------|
| `uv` | `pip` / `pip-tools` / `poetry` / `virtualenv` | Single tool, ~10–100× faster, lockfiles, project + script + tool installs. | Repos with an existing `poetry.lock` or `requirements.txt` workflow you don't own — match their conventions |
| `uv run script.py` (with PEP 723 inline `# /// script` metadata) | `python -m venv && pip install && python script.py` | One-shot scripts with declared deps, no env soup | — |
| `uv tool install <pkg>` | `pipx install <pkg>` | Same role, faster | Repos where pipx is in the docs |
| `ruff` | `flake8` + `black` + `isort` + `pyupgrade` | One tool, ~100× faster; `ruff format` replaces black, `ruff check --fix` covers the rest | Repos pinned to specific black/flake8 versions in pre-commit |
| `pyright` | `mypy` | Faster, what FastAPI/Pydantic ecosystems target, better incremental performance on large codebases | Repos with an existing `mypy.ini` / `[tool.mypy]` config — match the repo |
| `pyproject.toml` (PEP 621) | `setup.py` / `setup.cfg` | Standard, declarative | Maintaining a legacy package |
| `hatchling` build backend (in `pyproject.toml`) | `setuptools` | Clean PEP 517/621 builds, sane defaults, pairs with `uv` | Existing `setuptools` builds — don't switch backends mid-project |

**Modern Python conventions** (apply to new code; don't retrofit committed repos without consent):

- **`src/` layout** — new packages should be laid out as `project/src/<pkg>/__init__.py` with `tests/` as a sibling, not the flat `project/<pkg>/__init__.py`. The `src/` layout prevents accidental imports from CWD shadowing the installed package and is the default that `uv init --package` produces.
- **Lockfiles are mandatory.** Commit `uv.lock` (or `poetry.lock`, etc., if the repo predates uv); CI installs with `uv sync --locked` / `--frozen-lockfile` equivalents — never an unpinned resolve. "works on my machine" is not acceptable.
- **Type hints on new code.** PEP 484 hints are expected on function signatures and public APIs. Enables `pyright` checks, FastAPI/Pydantic patterns, and safer refactors. Don't backfill an untyped legacy module just to silence the checker — that's a separate, scoped change.
- **Don't suggest `rye`.** It was a popular Astral-precursor but was archived in favor of `uv`. Anything `rye` did, `uv` does — and `uv` is what the ecosystem consolidated on.

**Node.js:** If a repo needs Node seriously, prefer `pnpm` or `bun` over `npm` (faster, content-addressable store, ~½ disk usage), `npm ci` / `pnpm install --frozen-lockfile` in CI, and `fnm` over `nvm` for version switching. Don't introduce a `pnpm-lock.yaml` into a repo that already has `package-lock.json` without consent.

**Go:**

| Prefer | Over | Why | Fallback |
|--------|------|-----|----------|
| `go work` (1.18+) | manual `replace` in committed `go.mod` | Local multi-module workspaces without dirtying `go.mod` | Single-module repos |
| `go test -race ./...` | `go test ./...` | Race detector catches concurrency bugs; near-free in CI | Benchmarks (`-race` distorts timings) |
| `golangci-lint run` | individual linters | One tool, consistent config | — |

## Package Management Principles

The same handful of rules apply across every ecosystem — Python, Node, Go, Rust, Helm, system tooling. Per-ecosystem commands live in "Modern Language Toolchains" and "Modern Docker & Kubernetes"; this section captures the cross-cutting discipline.

### Universal rules

1. **Commit lockfiles. Always.**
   - Python: `uv.lock` (or `poetry.lock` if pre-existing)
   - Node: `pnpm-lock.yaml` / `bun.lock` / `package-lock.json`
   - Go: `go.sum` (committed alongside `go.mod`)
   - Rust: `Cargo.lock` (binaries; libraries can skip)
   - Helm: `Chart.lock`

   No lockfile = "works on my machine" = unacceptable for any committed repo.

2. **CI installs from the lockfile — never resolves fresh.**
   - Python: `uv sync --locked`
   - Node: `pnpm install --frozen-lockfile` / `bun install --frozen-lockfile` / `npm ci`
   - Go: `go build` (verifies via `go.sum` automatically; do not run `go mod tidy` in CI)
   - Rust: `cargo build --locked`
   - Helm: `helm dep build` (uses `Chart.lock`) before install

   A CI that resolves fresh each run ships a different artifact every run.

3. **One package manager per ecosystem per repo.** Never both `package-lock.json` AND `pnpm-lock.yaml`. Never both `uv.lock` AND `poetry.lock`. When in doubt about an existing repo, look at what's committed and what CI runs — match it.

4. **Pin runtime / toolchain versions explicitly.**
   - Python: `.python-version` (uv reads this and downloads the interpreter automatically) or `[tool.uv] python = "..."` in `pyproject.toml`
   - Node: `.nvmrc` / `.node-version` (read by `fnm`, `nvm`, `volta`)
   - Go: `toolchain` directive in `go.mod` (Go 1.21+) — Go fetches the right toolchain itself
   - Rust: `rust-version` field in `Cargo.toml`, or `rust-toolchain.toml`

   "Use whatever is on PATH" is not reproducible.

5. **Don't introduce or swap package managers without consent.** Same caveat as the CLI tools and Git sections — switching `pip` → `uv`, `npm` → `pnpm`, or `setuptools` → `hatchling` in a committed repo affects every contributor and every CI runner. Suggest, don't silently change.

### System-level (macOS dev machine)

| Tool | When to use | Why |
|------|-------------|-----|
| `brew` | Default for everything system-level | Standard macOS package manager; don't fight it |
| `Brewfile` (`brew bundle dump` → commit; `brew bundle install` → restore) | Tracking dev-machine tool parity, onboarding a new laptop | Reproducible system tooling, idempotent, checks into git |
| `mise` (formerly `rtx`) | Multi-language repos that need pinned Python + Node + Go versions from one config (`.mise.toml`) | Single binary, faster than `asdf`. Optional — `uv` already handles Python interpreters, `fnm` handles Node, `go.mod` toolchain handles Go. Only worth adopting if you actively juggle 3+ runtimes per repo. |
| `nix` / `devbox` / `flox` | Hermetic per-project environments | Heavy lift for the value. Skip unless the team explicitly adopts. |

### Helm (k8s package management)

For any repo that ships Helm charts:
- **Commit `Chart.lock`** — `helm dep update` writes it; treat it like any other lockfile.
- **Run `helm dep build` (or `helm dep update`) explicitly** before `helm install` / `helm template` — predictable, debuggable.
- **Prefer OCI registry charts** (`oci://registry.example.com/charts/foo`) over ChartMuseum / raw Helm repo URLs — OCI is the upstream default now and standardizes on container-registry auth.

### Caveats

- **Lockfiles can drift across platforms.** `uv.lock` and `pnpm-lock.yaml` are platform-aware (different wheels for darwin-arm64 vs linux-amd64). When CI fails on a wheel that's not in your local lock, regenerate the lockfile in CI's environment, don't just delete and re-resolve locally.
- **`go mod tidy` is a developer command, not a CI command.** CI should fail loudly if `go.mod` / `go.sum` would change after `tidy` (`go mod tidy -diff` works in 1.23+); never silently fix it.
- **For airgapped environments, vendoring may still be required.** `go mod vendor`, `pip download --dest`, `npm pack` — confirm before assuming a target host has internet egress.

## Cross-Cutting Caveats

These apply to all of the "modern" sections above (CLI Tools, Git, Docker/Kubernetes, Language Toolchains, Data/Network):

1. **Don't introduce a new tool into a committed repo without consent.** Switching `pip` → `uv`, `docker-compose` → `docker compose`, `npm` → `pnpm`, or `git checkout` → `git switch` in a Dockerfile / Makefile / CI workflow / runbook affects every contributor and every CI runner. Suggest, don't silently swap.
2. **CI runners and remote nodes often don't have the modern variant.** GitHub Actions images are reasonably modern, but a minimal debug image or a PXE-booted environment may not. Default to the traditional command in deploy-target scripts unless the modern tool is explicitly provisioned.
3. **Verify before recommending an unverified flag.** If a modern flag (`kubectl events --for`, `git restore --source`, `uv tool install`) is going into a command you'll suggest to the user, run `--help` to confirm syntax on the local version.
