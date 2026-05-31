#!/usr/bin/env bash
# audit-memory.sh — deterministic helper for the /meta-memory-audit skill.
# Enumerates a Claude Code per-project memory directory, parses frontmatter,
# locates in-scope CLAUDE.md files, and detects self-disclosed reinforcers
# and dangling pointers. Emits a JSON manifest the LLM reasons over.
#
# Usage:
#   audit-memory.sh <memory_dir>
#
# memory_dir: path to ~/.claude/projects/<slug>/memory/ (must contain MEMORY.md)
#
# In-scope CLAUDE.md files default to the global scope plus any CLAUDE.md in
# the launch CWD's git root. Override by setting CLAUDE_MD_FILES to a
# colon-separated list of paths.

set -euo pipefail

MEMORY_DIR="${1:-}"
if [[ -z "$MEMORY_DIR" || ! -d "$MEMORY_DIR" ]]; then
    echo '{"error": "missing-memory-dir", "detail": "pass the memory directory as $1"}' >&2
    exit 1
fi

# In-scope CLAUDE.md files. Honors the symlink topology:
# ~/.claude/CLAUDE.md may symlink to ~/dotfiles/claude/CLAUDE.md.
# Default: global + any CLAUDE.md at the current git root.
if [[ -n "${CLAUDE_MD_FILES:-}" ]]; then
    IFS=':' read -r -a CLAUDE_MD_FILES <<< "$CLAUDE_MD_FILES"
else
    declare -a CLAUDE_MD_FILES=("$HOME/.claude/CLAUDE.md")
    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$GIT_ROOT" && -f "$GIT_ROOT/CLAUDE.md" ]]; then
        CLAUDE_MD_FILES+=("$GIT_ROOT/CLAUDE.md")
    fi
fi

REFERENCES_DIR="$HOME/dotfiles/claude/references"

# ---------- helpers ----------

# parse_frontmatter <file> — emit JSON of YAML frontmatter (top of file, between --- ---).
parse_frontmatter() {
    local file="$1"
    awk '
        /^---$/ { fm = !fm; next }
        fm { print }
    ' "$file" | python3 -c '
import sys, json
try:
    import yaml
    data = yaml.safe_load(sys.stdin) or {}
except Exception:
    # crude fallback if pyyaml unavailable: parse key: value pairs manually
    data = {}
    for line in sys.stdin:
        if ":" in line:
            k, _, v = line.partition(":")
            data[k.strip()] = v.strip()
print(json.dumps(data, ensure_ascii=False))
'
}

# body_first_500 <file> — first 500 CHARACTERS of post-frontmatter content
# (newlines collapsed). Uses Python for the slice so multibyte UTF-8 chars
# (— → ≥ etc.) don't get cut mid-codepoint. A `head -c 500` byte-slice would
# make downstream `json.dumps(sys.stdin.read())` choke on truncated UTF-8.
body_first_500() {
    local file="$1"
    awk '
        /^---$/ { count++; next }
        count >= 2 { print }
    ' "$file" | tr '\n' ' ' | python3 -c 'import sys; sys.stdout.write(sys.stdin.read()[:500])'
}

# detect_reinforcer <file> — emit "true" if the body self-discloses being a reinforcer/duplicate
detect_reinforcer() {
    local file="$1"
    if grep -qE -i 'reinforcer for (the )?(global )?CLAUDE\.md|duplicate of|expansion of (the )?inline rule|already in (global )?CLAUDE\.md' "$file"; then
        echo "true"
    else
        echo "false"
    fi
}

# detect_duplicate_line <file> — try to extract "lines N–M" or "line N" reference from the body
detect_duplicate_line() {
    local file="$1"
    # Look for patterns like "CLAUDE.md lines 35–37" or "CLAUDE.md line 59"
    local hit
    hit=$(grep -oE 'CLAUDE\.md lines? [0-9]+(–[0-9]+|\s*[-–]\s*[0-9]+)?' "$file" | head -1)
    if [[ -n "$hit" ]]; then
        # JSON-escape the value
        printf '%s' "$hit" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))'
    else
        echo "null"
    fi
}

# in_index <file_basename> — check if listed in MEMORY.md
in_index() {
    local name="$1"
    local index="$MEMORY_DIR/MEMORY.md"
    [[ -f "$index" ]] || { echo "false"; return; }
    if grep -qF "$name" "$index"; then
        echo "true"
    else
        echo "false"
    fi
}

# section_headers <file> — list ## headers as a JSON array
section_headers() {
    local file="$1"
    [[ -f "$file" ]] || { echo "[]"; return; }
    grep -E '^## ' "$file" | sed 's/^## *//' | python3 -c '
import sys, json
print(json.dumps([line.rstrip() for line in sys.stdin if line.strip()]))
'
}

# size_bytes <file>
size_bytes() {
    local file="$1"
    [[ -f "$file" ]] || { echo "0"; return; }
    wc -c < "$file" | tr -d ' '
}

# detect_dangling_pointers — emit JSON array of {claude_md, missing_path} entries.
# Looks for memory-file references in CLAUDE.md files that don't exist on disk.
detect_dangling_pointers() {
    local claude_md_list="$1"
    CLAUDE_MD_LIST="$claude_md_list" python3 <<'PYEOF'
import os, re, json, glob

claude_md_paths = [p for p in os.environ.get("CLAUDE_MD_LIST", "").split(":") if p]

# Patterns to detect referenced paths inside CLAUDE.md:
# - ~/.claude/projects/.../memory/feedback_X.md
# - ~/dotfiles/claude/references/X.md
ref_re = re.compile(r'`?(~/(?:\.claude|dotfiles)[^\s`)]+\.md)`?')

dangling = []
placeholder_re = re.compile(r"<[^>]+>")
for cmf in claude_md_paths:
    if not os.path.isfile(cmf):
        continue
    with open(cmf) as f:
        content = f.read()
    for m in ref_re.finditer(content):
        ref = m.group(1)
        # Skip paths containing any placeholder syntax (e.g. <n>, <name>,
        # <category>, <YYYY>, <domain>, <mode>, <repo>, <YYYY-MM-DD>).
        # These are documentation/spec paths, not real refs. <slug> kept
        # as a special case because its glob substitution is meaningful.
        if placeholder_re.search(ref) and "<slug>" not in ref:
            continue
        # Expand ~ and <slug> placeholders
        expanded = os.path.expanduser(ref)
        # If the path contains a <slug> placeholder, try to glob it
        if "<slug>" in expanded:
            globbed = glob.glob(expanded.replace("<slug>", "*"))
            if not globbed:
                dangling.append({"claude_md": cmf, "missing_path": ref})
        else:
            if not os.path.exists(expanded):
                dangling.append({"claude_md": cmf, "missing_path": ref})

print(json.dumps(dangling, ensure_ascii=False))
PYEOF
}

# ---------- emit JSON ----------

# Start JSON
printf '{\n'
printf '  "memory_dir": %s,\n' "$(printf '%s' "$MEMORY_DIR" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')"

# memory_files[]
printf '  "memory_files": [\n'
first=true
shopt -s nullglob
for f in "$MEMORY_DIR"/*.md; do
    bn=$(basename "$f")
    [[ "$bn" == "MEMORY.md" ]] && continue
    [[ "$first" == "true" ]] && first=false || printf ',\n'
    # Extract type from frontmatter (or filename prefix as fallback)
    fm=$(parse_frontmatter "$f")
    type_val=$(printf '%s' "$fm" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    metadata = data.get("metadata", {}) or {}
    print(data.get("type") or metadata.get("type") or "unknown")
except Exception:
    print("unknown")
')
    body_snippet=$(body_first_500 "$f" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
    reinforcer=$(detect_reinforcer "$f")
    dup_line=$(detect_duplicate_line "$f")
    indexed=$(in_index "$bn")

    printf '    {\n'
    printf '      "name": "%s",\n' "$bn"
    printf '      "type": "%s",\n' "$type_val"
    printf '      "frontmatter": %s,\n' "$fm"
    printf '      "body_first_500": %s,\n' "$body_snippet"
    printf '      "self_disclosed_reinforcer": %s,\n' "$reinforcer"
    printf '      "self_disclosed_duplicate_of": %s,\n' "$dup_line"
    printf '      "indexed_in_MEMORY_md": %s\n' "$indexed"
    printf '    }'
done
printf '\n  ],\n'

# claude_md_files[]
CLAUDE_MD_JOINED=""
printf '  "claude_md_files": [\n'
first=true
for cmf in "${CLAUDE_MD_FILES[@]}"; do
    [[ -f "$cmf" ]] || continue
    CLAUDE_MD_JOINED="${CLAUDE_MD_JOINED:+$CLAUDE_MD_JOINED:}$cmf"
    [[ "$first" == "true" ]] && first=false || printf ',\n'
    sb=$(size_bytes "$cmf")
    sh=$(section_headers "$cmf")
    printf '    {"path": "%s", "size_bytes": %s, "section_headers": %s}' "$cmf" "$sb" "$sh"
done
printf '\n  ],\n'

# references_files[]
printf '  "references_files": [\n'
first=true
if [[ -d "$REFERENCES_DIR" ]]; then
    for rf in "$REFERENCES_DIR"/*.md; do
        [[ -f "$rf" ]] || continue
        [[ "$first" == "true" ]] && first=false || printf ',\n'
        sb=$(size_bytes "$rf")
        printf '    {"path": "%s", "size_bytes": %s}' "$rf" "$sb"
    done
fi
printf '\n  ],\n'

# dangling_pointers[]
printf '  "dangling_pointers": '
detect_dangling_pointers "$CLAUDE_MD_JOINED"
printf '\n}\n'
