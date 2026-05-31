---
description: Print the current Claude Code session ID and the absolute path to the JSONL transcript on disk.
---

Run this bash command and print the output verbatim, no surrounding commentary:

```bash
if [[ -z "$CLAUDE_CODE_SESSION_ID" ]]; then
  echo "not inside a Claude Code session"
else
  path="$(find ~/.claude/projects -name "$CLAUDE_CODE_SESSION_ID.jsonl" 2>/dev/null | head -1)"
  printf 'session: %s\npath:    %s\n' "$CLAUDE_CODE_SESSION_ID" "$path"
fi
```

Notes:
- `$CLAUDE_CODE_SESSION_ID` is set by the harness in every Claude Code session.
- Transcripts live at `~/.claude/projects/<project-slug>/<session-id>.jsonl`, where the slug is the launch CWD with `/` substituted by `-`. The `find` form above is slug-agnostic.
- Equivalent terminal-side shell function: `claude-session` (defined in `~/.zshrc` and `~/dotfiles/shell/zshrc.template`). Use whichever is more convenient.
