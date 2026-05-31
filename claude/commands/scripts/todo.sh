#!/usr/bin/env bash
# todo.sh — implementation of the /todo slash command.
#
# Invoked from ~/.claude/commands/todo.md (a thin shim that just runs
# this script). Also directly invokable from the shell:
#   ~/.claude/commands/scripts/todo.sh list
#   ~/.claude/commands/scripts/todo.sh add foo bar
#   ~/.claude/commands/scripts/todo.sh done 3
#
# Spec: ~/.claude/CLAUDE.md § "Cross-Session Todos".
#
# Storage layout — one markdown file per category at
# $TODO_DIR/<category>.md. Default category resolution: first existing of
# [work, personal], else "work".
#
# This file used to live inline in the slash-command markdown body, which
# shipped ~5k tokens to the LLM on every invocation. Extracting to a
# standalone script means the slash command body shrinks to ~50 tokens
# and Claude Code's roundtrip on `/todo list` drops dramatically.

set -eo pipefail
set +H   # disable history expansion — `!` chars in [[ ! -f ]] / *[!...]* patterns

TODO_DIR="${TODO_DIR:-$HOME/.claude/todos}"
mkdir -p "$TODO_DIR"

# Use $TMPDIR-aware mktemp form so we never write to /var/folders/.../T/
# when called via Claude Code's Bash tool (which sandboxes that path).
# `mktemp -t <prefix>` honors TMPDIR on both macOS BSD and GNU coreutils.
_mktmp() { mktemp -t todo.XXXXXXXX; }

# ─── Helpers ────────────────────────────────────────────────────────────────

# Default category — first existing of [work, personal], else "work".
pick_default() {
  local c
  for c in work personal; do
    [[ -f "$TODO_DIR/$c.md" ]] && { echo "$c"; return; }
  done
  echo "work"
}

# Validate category name (single segment, [a-z0-9_-]+) per CLAUDE.md spec.
validate_category() {
  [[ "$1" =~ ^[a-z0-9_-]+$ ]] \
    || { echo "ERROR: invalid category '$1' — must match [a-z0-9_-]+" >&2; exit 2; }
}

# Ensure file exists with required headers.
ensure_file() {
  local cat="$1" file="$TODO_DIR/$cat.md"
  if [[ ! -f "$file" ]]; then
    printf '# %s todos\n\n## Open\n\n## Closed\n' "$cat" > "$file"
  fi
  grep -q '^## Open' "$file" || printf '\n## Open\n' >> "$file"
  grep -q '^## Closed' "$file" || printf '\n## Closed\n' >> "$file"
  echo "$file"
}

# Emit all open items globally, one per line, tab-separated: <file>\t<raw-line>.
# Iteration order — alphabetical filesystem-glob category order, then
# P1→P2→P3→untagged per category, file order within bucket. Stable so list,
# done, and trash agree on indices. The OUTPUT-LINE position (1-based) IS
# the global index.
_enumerate_open() {
  local f
  for f in "$TODO_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local open
    open=$(awk '/^## Open/,/^## Closed/' "$f" | grep -E '^- \[ \]' || true)
    [[ -z "$open" ]] && continue
    {
      grep -F '[P1]'        <<< "$open" || true
      grep -F '[P2]'        <<< "$open" || true
      grep -F '[P3]'        <<< "$open" || true
      grep -Ev '\[P[123]\]' <<< "$open" || true
    } | while IFS= read -r ln; do
      [[ -z "$ln" ]] && continue
      printf '%s\t%s\n' "$f" "$ln"
    done
  done
}

# ─── list ───────────────────────────────────────────────────────────────────
# Renders items with stable global indices [N] (P1→P2→P3→untagged per category,
# alphabetical category order) and blank-line spacing between items. Indices
# match what done/trash consume — `done 3` always means the same item as
# `[3]` in the most recent list output, regardless of whether you ran
# default, `list <cat>`, or `list all`.
cmd_list() {
  local arg="${1:-}"
  local filter=""
  if [[ "$arg" == "all" ]]; then
    filter="*"
  elif [[ -n "$arg" ]]; then
    validate_category "$arg"
    filter="$arg"
  else
    filter="$(pick_default)"
  fi

  local n=0 prev_cat="" shown=0
  while IFS=$'\t' read -r file line; do
    n=$((n + 1))
    local cat
    cat=$(basename "$file" .md)
    if [[ "$filter" != "*" && "$cat" != "$filter" ]]; then
      continue
    fi
    if [[ "$cat" != "$prev_cat" ]]; then
      printf '## %s\n\n' "$cat"
      prev_cat="$cat"
    fi
    # Strip "- [ ] " checkbox prefix; the [N] index replaces it visually.
    local stripped="${line#- \[ \] }"
    printf '[%s] %s\n\n' "$n" "$stripped"
    shown=$((shown + 1))
  done < <(_enumerate_open)

  if [[ $shown -eq 0 ]]; then
    echo "(no open items)"
  fi
  return 0
}

# ─── add ────────────────────────────────────────────────────────────────────
# Args: [@category] [P1|P2|P3] <text>  — canonical order; flags in any
# position are accepted (trailing flags also parsed correctly, e.g.
# `todo add 'fix the thing' P2 @home` works the same as
# `todo add @home P2 'fix the thing'`).
#
# Standalone-token rule: a flag is only extracted when it's its own
# shell arg (`P2` as a whole word, `@home` as a whole word). Embedded
# tokens inside the text body stay in the text — `add 'P2 release notes'`
# keeps "P2 release notes" intact because the shell passes it as one arg.
# Second P-token or second @-token degrades to text (one of each wins).
cmd_add() {
  local cat="" prio=""
  local -a text_args=()
  local arg maybe_cat
  for arg in "$@"; do
    case "$arg" in
      @*)
        maybe_cat="${arg#@}"
        case "$maybe_cat" in
          *[!a-z0-9_-]*|"")
            text_args+=("$arg") ;;            # not a valid category form → text
          *)
            if [[ -n "$cat" ]]; then
              text_args+=("$arg")              # second @-token → text
            else
              cat="$maybe_cat"
            fi ;;
        esac ;;
      P1|P2|P3)
        if [[ -n "$prio" ]]; then
          text_args+=("$arg")                  # second P-token → text
        else
          prio="$arg"
        fi ;;
      *)
        text_args+=("$arg") ;;
    esac
  done
  local text="${text_args[*]}"

  [[ -z "$text" ]] && { echo "ERROR: no text supplied — usage: /todo add [@<category>] [P1|P2|P3] <text>" >&2; exit 2; }
  [[ -z "$cat" ]] && cat="$(pick_default)"
  validate_category "$cat"
  [[ -z "$prio" ]] && prio="P2"

  local file
  file=$(ensure_file "$cat")
  local date
  date=$(date +%Y-%m-%d)
  local line="- [ ] [$prio] ($date opened) $text"

  # Insert under "## Open" — appends to end of Open section.
  local tmp
  tmp=$(_mktmp)
  awk -v line="$line" '
    BEGIN { in_open=0; inserted=0 }
    /^## Open/ { print; in_open=1; next }
    in_open && /^## / && !inserted {
      print line
      print ""
      in_open=0
      inserted=1
    }
    { print }
    END {
      if (in_open && !inserted) print line
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"

  printf 'added → %s/%s.md [%s] %s\n' "$TODO_DIR" "$cat" "$prio" "$text"
}

# ─── done / trash (shared close logic) ──────────────────────────────────────
# Args: <verb> <N|substring>
#   verb: "closed" (work completed) | "trashed" (item obsolete/dropped)
# Pure-digit needle → global-index lookup via _enumerate_open. Anything else →
# fixed-string substring search across all open items. On multi-match, lists
# candidates with their indices so the user can re-run with the number.
# Both verbs move from Open to Closed; CLAUDE.md § "Cross-Session Todos" forbids
# hard-delete ("history of dropped vs done is useful for retrospectives") — the
# distinction lives in the close-action verb on each closed line.
_close_item() {
  local verb="$1"; shift
  local needle="$*"
  [[ -z "$needle" ]] && { echo "ERROR: index or substring required — usage: /todo done|trash <N|substring>" >&2; exit 2; }

  local file="" line=""

  if [[ "$needle" =~ ^[0-9]+$ ]]; then
    local entry
    entry=$(_enumerate_open | sed -n "${needle}p")
    [[ -z "$entry" ]] && { echo "ERROR: no open item at index ${needle}" >&2; exit 3; }
    IFS=$'\t' read -r file line <<< "$entry"
  else
    local matches_file
    matches_file=$(_mktmp)
    local n=0
    local f l
    while IFS=$'\t' read -r f l; do
      n=$((n + 1))
      if [[ "$l" == *"$needle"* ]]; then
        printf '%s\t%s\t%s\n' "$n" "$f" "$l" >> "$matches_file"
      fi
    done < <(_enumerate_open)

    local match_count
    match_count=$(wc -l < "$matches_file" | tr -d ' ')

    if [[ "$match_count" -eq 0 ]]; then
      rm -f "$matches_file"
      echo "ERROR: no open item matches '${needle}'" >&2; exit 3
    fi
    if [[ "$match_count" -gt 1 ]]; then
      echo "ERROR: multiple matches — re-run with index N or narrow the substring:" >&2
      local idx ff ll stripped
      while IFS=$'\t' read -r idx ff ll; do
        stripped="${ll#- \[ \] }"
        printf '  [%s] %s\n' "$idx" "$stripped" >&2
      done < "$matches_file"
      rm -f "$matches_file"
      exit 4
    fi

    local _idx
    IFS=$'\t' read -r _idx file line < "$matches_file"
    rm -f "$matches_file"
  fi

  local closed_date
  closed_date=$(date +%Y-%m-%d)

  local closed_line
  closed_line=$(printf '%s\n' "$line" | sed -E "s|^- \[ \] (\[P[123]\]) \(([0-9-]+) opened\)|- [x] \1 (\2 opened → ${closed_date} ${verb})|")

  local tmp
  tmp=$(_mktmp)
  grep -vxF -- "$line" "$file" > "$tmp" || true
  printf '%s\n' "$closed_line" >> "$tmp"
  mv "$tmp" "$file"

  printf '%s → %s\n        %s\n' "$verb" "$file" "$closed_line"
}

cmd_done()  { _close_item "closed"  "$@"; }
cmd_trash() { _close_item "trashed" "$@"; }

# ─── dispatch ───────────────────────────────────────────────────────────────
sub="${1:-list}"
[[ $# -gt 0 ]] && shift

case "$sub" in
  list)  cmd_list  "$@" ;;
  add)   cmd_add   "$@" ;;
  done)  cmd_done  "$@" ;;
  trash) cmd_trash "$@" ;;
  *)     echo "usage: todo [list [<category>|all] | add [@<category>] [P1|P2|P3] <text> | done <N|substring> | trash <N|substring>]" >&2; exit 2 ;;
esac
