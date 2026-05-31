#!/usr/bin/env bash
# check-dangling-refs.sh — lint over the Claude Code persistence graph.
#
# Scans every markdown file across the persistence roots (CLAUDE.md scopes,
# memory dirs, todos, watchlists, reference catalog, skills, commands,
# agents) for references that no longer resolve.
#
# Reference types detected:
#   1. Broken markdown links     `[text](path)` where path doesn't exist
#   2. Broken @./ autoloads       (CLAUDE.md relative-imports)
#   3. Stale ~/... references     (tilde-prefixed paths in prose)
#   4. Unresolved [[wikilinks]]   (memory cross-links to missing slugs)
#
# Configuration: set META_INVENTORY_PROJECT_ROOT to add a project repo's
# .claude/ + docs to the scan; set META_INVENTORY_DOTFILES_ROOT for your
# versioned dotfiles tree (defaults to ~/dotfiles).
#
# False-positive suppression:
#   - skip lines inside fenced code blocks (``` ... ```)
#   - skip lines with <placeholder> syntax (<name>, <slug>, <domain>, etc.)
#   - skip URL schemes (http://, https://, mailto:, file://)
#   - skip command flags that look like paths (e.g. -o /tmp/foo)
#   - expand brace patterns ({a,b}) and treat as resolved if any variant exists
#   - skip tilde-paths in negative-example sentences ("do not use ~/foo/")
#
# Exit codes:
#   0 — no dangling refs
#   1 — usage error / script bug
#   2 — dangling refs found (for SessionStart-hook use)
#
# Usage: check-dangling-refs.sh

set -euo pipefail

DOTFILES_ROOT="${META_INVENTORY_DOTFILES_ROOT:-$HOME/dotfiles}"
PROJECT_ROOT="${META_INVENTORY_PROJECT_ROOT:-}"

# ---------- scan roots ----------
# Each line: a directory or file path to recurse into.
# Excluded: anything inside .git, node_modules, __pycache__, plugin caches.

ROOTS=(
    "$HOME/.claude/CLAUDE.md"
    "$DOTFILES_ROOT/claude/CLAUDE.md"
    "$HOME/.claude/projects"
    "$DOTFILES_ROOT/claude/memory"
    "$HOME/.claude/todos"
    "$HOME/.claude/watchlists"
    "$DOTFILES_ROOT/claude/references"
    "$HOME/.claude/skills"
    "$HOME/.claude/commands"
    "$HOME/.claude/agents"
)

# Add project-scoped roots when configured.
if [[ -n "$PROJECT_ROOT" ]]; then
    ROOTS+=("$PROJECT_ROOT/CLAUDE.md")
    for mf in "$PROJECT_ROOT"/CLAUDE.*.md; do
        [[ -e "$mf" ]] && ROOTS+=("$mf")
    done
    ROOTS+=(
        "$PROJECT_ROOT/docs"
        "$PROJECT_ROOT/.claude/agent-memory"
        "$PROJECT_ROOT/.claude/skills"
    )
fi

# Resolve each root to its real path (some are symlinks).
RESOLVED_ROOTS=()
for r in "${ROOTS[@]}"; do
    if [[ -e "$r" ]]; then
        # macOS readlink doesn't have -f; use python
        local_real=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$r")
        RESOLVED_ROOTS+=("$local_real")
    fi
done

# ---------- collect files ----------
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for root in "${RESOLVED_ROOTS[@]}"; do
    if [[ -f "$root" ]]; then
        # Inventory output docs quote stale paths as data; scanning them
        # self-flags the previous run's lint table as live references.
        case "$root" in *claude-arch-inventory*.md) continue ;; esac
        echo "$root" >> "$TMPFILE"
    elif [[ -d "$root" ]]; then
        find -L "$root" -type f -name '*.md' \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/__pycache__/*' \
            -not -path '*/.claude/plugins/cache/*' \
            -not -path '*/.claude/plugins/marketplaces/*' \
            -not -name '*claude-arch-inventory*' \
            2>/dev/null >> "$TMPFILE" || true
    fi
done

# Canonicalize each found path with realpath, then dedup. `find -L` outputs paths
# under the original (possibly symlinked) prefix; without canonicalization, the
# same on-disk file surfaces under multiple prefixes and gets scanned multiple times.
python3 -c '
import os, sys
seen = set()
out = []
with open(sys.argv[1]) as f:
    for line in f:
        p = line.strip()
        if not p:
            continue
        rp = os.path.realpath(p)
        if rp not in seen:
            seen.add(rp)
            out.append(rp)
with open(sys.argv[1], "w") as f:
    for p in sorted(out):
        f.write(p + "\n")
' "$TMPFILE"

# ---------- scan + classify ----------

# Build the list of all known memory slugs once (used for [[wikilink]] validation).
MEMORY_SLUGS=$(mktemp)
trap 'rm -f "$TMPFILE" "$MEMORY_SLUGS"' EXIT

for memdir in "$HOME"/.claude/projects/*/memory; do
    [[ -e "$memdir" ]] || continue
    find -L "$memdir" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null >> "$MEMORY_SLUGS"
done

# Also include the dotfiles memory source-of-truth tree, if present.
for memdir in "$DOTFILES_ROOT"/claude/memory/*; do
    [[ -d "$memdir" ]] || continue
    find -L "$memdir" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; 2>/dev/null >> "$MEMORY_SLUGS"
done

sort -u "$MEMORY_SLUGS" -o "$MEMORY_SLUGS"

# ---------- python scanner ----------

python3 - "$TMPFILE" "$MEMORY_SLUGS" <<'PYEOF'
import os, re, sys, json

files_list_path = sys.argv[1]
slugs_path = sys.argv[2]

with open(files_list_path) as f:
    files = [line.strip() for line in f if line.strip()]

with open(slugs_path) as f:
    memory_slugs = {line.strip() for line in f if line.strip()}

home = os.path.expanduser("~")

# --- regex patterns ---

# Markdown link target group — non-greedy, no spaces; skip URLs and anchors.
RE_MD_LINK = re.compile(r'\[(?P<text>[^\]\n]+)\]\((?P<target>[^)\s#]+)(?:#[^)]*)?\)')

# @./relpath autoloads (Claude Code CLAUDE.md import syntax)
RE_AT_AUTOLOAD = re.compile(r'(?<![A-Za-z0-9_])@(?P<target>\./[A-Za-z0-9._/-]+\.md)')

# ~/ tilde paths in prose (inside backticks).
# Matches `~/path/to/file.ext` and `~/path/to/file.ext § Section N` (path
# followed by optional whitespace + annotation text inside the same backtick).
RE_TILDE_PATH = re.compile(r'`(?P<target>~/[^`\s]+\.(?:md|sh|py|json|yaml|yml|toml))(?:\s+[^`]*)?`')

# ~/ tilde paths pointing to a directory (trailing slash). Same backtick
# convention; the on-disk check uses isdir() not exists().
RE_TILDE_DIR = re.compile(r'`(?P<target>~/[^`\s]+/)(?:\s+[^`]*)?`')

# [[wikilink]] cross-refs in memory
RE_WIKILINK = re.compile(r'\[\[(?P<slug>[A-Za-z0-9_-]+)\]\]')

# Placeholder syntax — if a target contains any of these, suppress.
# Both <angle-bracket> and ellipsis (...) forms are commonly used in prose
# examples (e.g. `~/.claude/projects/<slug>/memory/`, `~/.claude/.../memory/`).
RE_PLACEHOLDER = re.compile(r'<[A-Za-z0-9_-]+>|\.{3,}')

# Ambient + example paths — paths that legitimately don't exist on this
# machine. Two flavors share this list:
#   (a) paths documented as existing on remote / ML-training nodes (docs
#       reference them; lint shouldn't flag);
#   (b) documentation placeholder paths used as illustration in skill
#       SKILL.md, memory entries, CLAUDE.md examples — never resolve to
#       real files by design.
# Prefix-match against target. Keep this list small; refactor to external
# file if it grows past ~15.
AMBIENT_PATH_PREFIXES = (
    "~/.cache/torch/",       # PyTorch inductor + general torch cache (ML nodes)
    "~/.triton/cache/",      # Triton kernel cache (ML nodes)
    "~/.config/enroot/",     # Enroot container hooks (HPC nodes)
    "~/foo/",                # generic doc placeholder
    "~/scratch/",            # conceptual personal-namespace pointer
)

# Conditional-existence paths — conventional locations documented in CLAUDE.md
# scopes that materialize on first-use rather than at install time. The
# reference is correct routing; the path is just not instantiated yet.
# Different from AMBIENT (remote-machine paths) and from doc placeholders
# (illustrative `~/foo/`-style). Suppressing keeps the lint focused on
# genuinely stale references (renames, moved files, typos).
CONDITIONAL_PATH_PREFIXES = (
    "~/.claude/agents/",            # user-level agents dir; absent when count=0
    "~/.claude/skills-base/",       # alt name for ~/.claude/skills/ (per a routing convention)
    "~/.claude/watchlists/archive/", # created on first watchlist archival (aging rule)
)

# Brace-expansion patterns like {a,b,c} inside a path target. Requires at
# least one comma to distinguish from single-element `{x}` curly-brace usage
# that we don't try to expand. Matches `foo/{bar,baz}/`.
RE_BRACE_GROUP = re.compile(r'\{([A-Za-z0-9_.,/-]+,[A-Za-z0-9_.,/-]+)\}')

# Negative-example prose markers — when a tilde-path appears in a sentence
# that's explicitly telling the reader NOT to use it ("do not use ~/H100/",
# "never use ...", "incorrect", "wrong path"), suppress as a false-positive.
# Look back ~80 chars from the path match for one of these phrases.
RE_NEGATIVE_CONTEXT = re.compile(
    r"(don'?t use|do not use|never use|avoid using|not the correct|"
    r"incorrect|wrong path|wrong location|do NOT use)",
    re.IGNORECASE,
)

# "Use X not Y" / "X instead of Y" / "X rather than Y" structural pattern —
# when the path appears immediately after `not`, `instead of`, `rather than`,
# `vs`/`vs.`, it's being negatively exampled. Match against the few chars
# immediately preceding the path's opening backtick.
RE_USE_X_NOT_Y = re.compile(
    r"\b(?:not|instead of|rather than|vs\.?)\s*$",
    re.IGNORECASE,
)


def expand_braces(target, max_variants=128):
    """If target contains brace-groups like {a,b}/{c,d}, return all variants
    via iterative cartesian expansion. Returns None if no brace pattern.
    Handles N sibling groups; nested groups ({a,{b,c}}) are NOT supported
    (the regex character class doesn't allow nested braces). Caps the
    expansion at `max_variants` to keep degenerate cases bounded."""
    if not RE_BRACE_GROUP.search(target):
        return None
    variants = [target]
    while True:
        expanded_one = False
        next_variants = []
        for v in variants:
            m = RE_BRACE_GROUP.search(v)
            if not m:
                next_variants.append(v)
                continue
            expanded_one = True
            for part in m.group(1).split(','):
                next_variants.append(v.replace(m.group(0), part.strip(), 1))
                if len(next_variants) >= max_variants:
                    return next_variants
        variants = next_variants
        if not expanded_one:
            break
    return variants


def any_brace_variant_exists(target, must_be_dir=False):
    """For brace-expansion targets, return True if any variant exists on disk.
    Returns None if target has no brace pattern (caller does normal check)."""
    variants = expand_braces(target)
    if variants is None:
        return None
    check = os.path.isdir if must_be_dir else os.path.exists
    for v in variants:
        resolved = os.path.expanduser(v) if v.startswith('~') else v
        if check(resolved):
            return True
    return False


def is_negative_example(line, match_start):
    """True if the tilde-path appears in a negative-example sentence.
    Covers two patterns: (a) full-sentence markers like "do not use ~/X/"
    within ~80 chars before the path, or (b) "X not Y" / "X instead of Y"
    where Y is the path and 'not'/'instead of' appears immediately before."""
    prefix = line[max(0, match_start - 80):match_start]
    if RE_NEGATIVE_CONTEXT.search(prefix):
        return True
    if RE_USE_X_NOT_Y.search(prefix):
        return True
    return False

# All-caps template tokens (date/time placeholders) — YYYY, MM, DD, etc.
# Surrounded by non-alphanumerics or path separators.
RE_ALLCAPS_TOKEN = re.compile(r'(?:^|[/_.-])(?:YYYY|YY|MM|DD|HH|MIN|SS|TS|YEAR|MONTH|DAY|HOUR)(?:[/_.-]|$)')

# Glob characters — suppress (we don't expand globs)
RE_GLOB = re.compile(r'[*?\[\]]')

# URL schemes — suppress
RE_URL = re.compile(r'^(https?|mailto|file|ftp|data|tel|s3|gs|svn|git|ssh):', re.IGNORECASE)

# Path-like heuristic — must contain at least one slash OR a dot before an extension
RE_PATHLIKE = re.compile(r'[/.]')

def is_placeholder(target):
    if RE_PLACEHOLDER.search(target):
        return True
    if RE_ALLCAPS_TOKEN.search(target):
        return True
    if RE_GLOB.search(target):
        return True
    return False

def is_ambient(target):
    """True if target is an ambient path documented for remote / ML-training
    machines — not expected to exist on this machine."""
    return any(target.startswith(p) for p in AMBIENT_PATH_PREFIXES)

def is_conditional(target):
    """True if target is a conventional location documented in CLAUDE.md
    that materializes on first-use rather than at install time (user-level
    agents dir, watchlist archive, etc.)."""
    return any(target.startswith(p) for p in CONDITIONAL_PATH_PREFIXES)

def is_url(target):
    return bool(RE_URL.match(target))

def is_pathlike(target):
    """Filter out non-path link targets like [foo](url) where 'url' is literal placeholder text."""
    return bool(RE_PATHLIKE.search(target))

def resolve(target, source_file):
    """Resolve a link target to an absolute path. Return None if unresolvable."""
    if target.startswith('~'):
        return os.path.expanduser(target)
    if target.startswith('/'):
        return target
    # Relative path — resolve against source file's directory
    return os.path.normpath(os.path.join(os.path.dirname(source_file), target))

def strip_code_blocks(content):
    """Replace fenced code blocks with empty lines so they don't get scanned for refs."""
    out_lines = []
    in_fence = False
    for line in content.split('\n'):
        if line.strip().startswith('```'):
            in_fence = not in_fence
            out_lines.append('')  # placeholder
            continue
        if in_fence:
            out_lines.append('')
        else:
            out_lines.append(line)
    return '\n'.join(out_lines)

def strip_inline_code(line):
    """Remove inline `code` spans from a line so they don't trip path regex.
    EXCEPTION: tilde-paths are intentionally inside backticks (that's our trigger),
    so we keep the entire line for tilde-scan."""
    return re.sub(r'`[^`\n]*`', '', line)

# --- findings buckets ---

broken_md_links = []
broken_at_autoloads = []
stale_tilde_paths = []
unresolved_wikilinks = []

for src in files:
    try:
        with open(src, 'r', errors='replace') as f:
            content = f.read()
    except (IOError, OSError):
        continue

    stripped = strip_code_blocks(content)

    # Markdown links — scan over non-codeblock content, also remove inline `code`
    # so that example commands inside backticks don't generate false positives.
    for lineno, raw_line in enumerate(stripped.split('\n'), start=1):
        line = strip_inline_code(raw_line)
        for m in RE_MD_LINK.finditer(line):
            target = m.group('target')
            if is_url(target):
                continue
            if is_placeholder(target):
                continue
            if not is_pathlike(target):
                continue
            resolved = resolve(target, src)
            if resolved and not os.path.exists(resolved):
                broken_md_links.append({
                    "source": src,
                    "line": lineno,
                    "target": target,
                    "resolved": resolved,
                })

        # @./ autoloads
        for m in RE_AT_AUTOLOAD.finditer(line):
            target = m.group('target')
            if is_placeholder(target):
                continue
            resolved = resolve(target, src)
            if resolved and not os.path.exists(resolved):
                broken_at_autoloads.append({
                    "source": src,
                    "line": lineno,
                    "target": target,
                    "resolved": resolved,
                })

    # Tilde paths — scan the ORIGINAL content (not stripped) since these
    # are inside backticks by design. Both file refs (.md/.sh/etc.) and
    # directory refs (trailing slash) are checked.
    for lineno, line in enumerate(strip_code_blocks(content).split('\n'), start=1):
        # Skip checked-todo bullets — `- [x] ...` lines describe completed
        # cleanup and routinely cite past-state paths that no longer exist
        # (e.g. `Convert ~/.claude/skills/session/ → ~/.claude/commands/session.md`).
        if line.lstrip().startswith('- [x] '):
            continue
        for m in RE_TILDE_PATH.finditer(line):
            target = m.group('target')
            if is_placeholder(target) or is_ambient(target) or is_conditional(target):
                continue
            if is_negative_example(line, m.start()):
                continue
            brace_check = any_brace_variant_exists(target, must_be_dir=False)
            if brace_check is True:
                continue  # at least one brace variant resolves
            resolved = os.path.expanduser(target)
            if not os.path.exists(resolved):
                stale_tilde_paths.append({
                    "source": src,
                    "line": lineno,
                    "target": target,
                    "resolved": resolved,
                })
        for m in RE_TILDE_DIR.finditer(line):
            target = m.group('target')
            if is_placeholder(target) or is_ambient(target) or is_conditional(target):
                continue
            if is_negative_example(line, m.start()):
                continue
            brace_check = any_brace_variant_exists(target, must_be_dir=True)
            if brace_check is True:
                continue  # at least one brace variant resolves as a dir
            resolved = os.path.expanduser(target)
            if not os.path.isdir(resolved):
                stale_tilde_paths.append({
                    "source": src,
                    "line": lineno,
                    "target": target,
                    "resolved": resolved,
                })

    # Wikilinks — only flag in memory files (where [[slug]] is the convention)
    # because plain `[[X]]` could appear as bracketed text in other contexts.
    is_memory = ("/memory/" in src) or ("/claude/memory/" in src)
    if is_memory:
        for lineno, line in enumerate(stripped.split('\n'), start=1):
            for m in RE_WIKILINK.finditer(line):
                slug = m.group('slug')
                if slug not in memory_slugs:
                    unresolved_wikilinks.append({
                        "source": src,
                        "line": lineno,
                        "slug": slug,
                    })

# --- emit markdown report ---

total = len(broken_md_links) + len(broken_at_autoloads) + len(stale_tilde_paths) + len(unresolved_wikilinks)

def fmt_src(p):
    """Render absolute path with ~ for $HOME."""
    return p.replace(home, "~")

print(f"## 3. Dangling-refs lint")
print()
print(f"Scanned {len(files)} markdown files across the persistence graph.")
print(f"Total dangling refs: {total}")
print()

if not total:
    print("No dangling refs found.")
    sys.exit(0)

if broken_md_links:
    print(f"### Broken markdown links ({len(broken_md_links)})")
    print()
    print("| Source | Line | Target | Resolved |")
    print("|---|---|---|---|")
    for r in broken_md_links:
        print(f"| `{fmt_src(r['source'])}` | {r['line']} | `{r['target']}` | `{fmt_src(r['resolved'])}` |")
    print()

if broken_at_autoloads:
    print(f"### Broken `@./` autoloads ({len(broken_at_autoloads)})")
    print()
    print("| Source | Line | Target |")
    print("|---|---|---|")
    for r in broken_at_autoloads:
        print(f"| `{fmt_src(r['source'])}` | {r['line']} | `{r['target']}` |")
    print()

if stale_tilde_paths:
    print(f"### Stale `~/...` references ({len(stale_tilde_paths)})")
    print()
    print("| Source | Line | Target |")
    print("|---|---|---|")
    for r in stale_tilde_paths:
        print(f"| `{fmt_src(r['source'])}` | {r['line']} | `{r['target']}` |")
    print()

if unresolved_wikilinks:
    print(f"### Unresolved memory `[[wikilinks]]` ({len(unresolved_wikilinks)})")
    print()
    print("_Per global CLAUDE.md § Memory Hygiene: unresolved wikilinks mark memories worth writing later, not errors. Surface for review; don't auto-fix._")
    print()
    print("| Source | Line | Slug |")
    print("|---|---|---|")
    for r in unresolved_wikilinks:
        print(f"| `{fmt_src(r['source'])}` | {r['line']} | `[[{r['slug']}]]` |")
    print()

sys.exit(2)
PYEOF
