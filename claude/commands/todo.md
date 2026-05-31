---
description: Manage cross-session todos under ~/.claude/todos/<category>.md. Subcommands — list (open items by priority, numbered with stable global indices), add (with inferred or explicit P1/P2/P3 + @category), done (mark completed; accepts index N or substring), trash (mark obsolete/dropped without doing; accepts index N or substring). Both done and trash move to Closed; neither hard-deletes (CLAUDE.md spec requires history of done-vs-dropped). Spec in ~/.claude/CLAUDE.md § "Cross-Session Todos".
---

Run the script below and print its output verbatim, with no surrounding commentary. If it exits non-zero, print the stderr. If `$ARGUMENTS` is empty, the script defaults to `list`.

```bash
set -f; bash "$HOME/.claude/commands/scripts/todo.sh" $ARGUMENTS
```

`set -f` disables shell globbing for the substituted args — without it, priority literals like `[P2]` get treated as char-class globs and trigger `nomatch` errors before bash sees them.

The implementation lives in `scripts/todo.sh` (sibling subdir, out of the slash-command namespace so it doesn't pollute `ls ~/.claude/commands/`). This markdown body is intentionally tiny so the slash-command prelude that ships into the LLM's context per invocation stays under ~50 tokens — the old inline-script form shipped ~5k tokens every time and made `/todo list` feel sluggish.
