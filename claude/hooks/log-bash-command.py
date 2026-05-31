#!/usr/bin/env python3
"""PostToolUse Bash logger — atuin write.

Every Claude-side Bash tool call lands in atuin's history DB via
`atuin history start --author claude` + `atuin history end`. Captures
all dev work (git, rg, jq, gh, custom scripts) with no allowlist gate.
The `--author claude` tag distinguishes these rows from your typed
history; `--intent <description>` carries Claude's per-call description.

Net effect: `atuin search` surfaces what Claude ran alongside what you
typed, in one timeline — so you can audit, re-run, or learn from Claude's
shell work the same way you do your own.

CAVEAT: Claude Code's PostToolUse hook only fires on successful tool
calls (Bash exit 0). Failed Bash invocations bypass this hook entirely
— atuin records Claude-side calls as exit 0. Failure-pattern history
relies on your shell-side captures (atuin's native shell integration).

Wiring (settings.json):
    "PostToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command",
                     "command": "python3 ~/.claude/hooks/log-bash-command.py",
                     "timeout": 5 } ] }
    ]

Requires atuin on PATH (https://atuin.sh). If atuin is absent the hook
silently no-ops — safe to wire unconditionally.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys


# Redaction patterns. Run on cmd, stdout_tail, stderr_tail.
SCRUB_PATTERNS = [
    (re.compile(r"(--(?:password|token|secret|api-key|auth))([= ])\S+"), r"\1\2<redacted>"),
    (re.compile(r"\b([A-Z][A-Z_]*(?:TOKEN|PASSWORD|SECRET|KEY))=\S+"), r"\1=<redacted>"),
]


def scrub(s: str) -> str:
    if not s:
        return s
    for pat, repl in SCRUB_PATTERNS:
        s = pat.sub(repl, s)
    return s


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return  # silent: nothing to do if payload malformed

    if payload.get("tool_name") != "Bash":
        return

    tool_input = payload.get("tool_input") or {}
    cmd = tool_input.get("command") or ""
    if not cmd:
        return

    description = tool_input.get("description") or ""
    scrubbed_cmd = scrub(cmd)
    cwd = payload.get("cwd") or os.getcwd()
    duration_ms = payload.get("duration_ms") or 0

    # Atuin write — UNCONDITIONAL. Every Claude-side Bash call lands in
    # atuin history so it surfaces in interactive `atuin search` alongside
    # typed history. Tagged --author claude for filterability.
    write_to_atuin_minimal(scrubbed_cmd, cwd, duration_ms, description)


def write_to_atuin_minimal(cmd: str, cwd: str, duration_ms: int, description: str) -> None:
    """Write a single Claude Bash call to atuin's history DB.

    Called UNCONDITIONALLY for every Bash tool call (not just an allowlist)
    so dev work (git, rg, jq, gh, etc.) surfaces in interactive `atuin search`
    alongside typed history.

    Atuin's `--author` flag documents `claude` as a first-class value:
    https://atuin.sh — `atuin history start --author <AUTHOR>` is the official
    surface for external-agent history insertion (also used by GitHub Copilot
    integrations). The start/end pair is needed because atuin tracks
    duration + exit code post-execution; we have both at this point so we
    fire them back-to-back.

    Best-effort: any failure (atuin missing, slow, sync error, malformed
    response) is swallowed — must never break the hook.
    """
    try:
        cmd_args = ["atuin", "history", "start", "--author", "claude"]
        if description:
            cmd_args += ["--intent", description]
        cmd_args += ["--", cmd]

        start = subprocess.run(
            cmd_args,
            capture_output=True,
            text=True,
            timeout=2,
            cwd=cwd,  # atuin captures process CWD; align with the real call site
        )
        if start.returncode != 0:
            return
        atuin_id = start.stdout.strip()
        if not atuin_id:
            return

        # atuin's --duration is in NANOSECONDS, not milliseconds (matches the
        # underlying DB column). Convert from our ms unit.
        duration_ns = int(duration_ms) * 1_000_000
        subprocess.run(
            ["atuin", "history", "end",
             "--exit", "0",
             "--duration", str(duration_ns),
             atuin_id],
            capture_output=True,
            text=True,
            timeout=2,
            cwd=cwd,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass  # atuin missing / slow / unavailable — silent skip
    except Exception:
        pass  # any unexpected failure — never break the hook


if __name__ == "__main__":
    main()
