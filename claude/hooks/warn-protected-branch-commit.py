#!/usr/bin/env python3
"""
PreToolUse:Bash hook — warn when a git commit is about to land on a protected
branch (main/master) of any repository. Warn-only; never blocks the commit.

Encodes the "branch before you commit" convention as a tool-call observer so
it fires even when you (or Claude) forget. The warning is a systemMessage, not
a deny — the commit always proceeds.

Optional scoping: set PROTECTED_BRANCH_ROOTS to a colon-separated list of
directory prefixes to limit the warning to repos under those roots (e.g.
"~/work:~/src"). Unset → warn for every repo.

Wiring (settings.json):
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command",
                     "command": "python3 ~/.claude/hooks/warn-protected-branch-commit.py",
                     "timeout": 5 } ] }
    ]
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROTECTED = ("main", "master")


def scope_roots():
    raw = os.environ.get("PROTECTED_BRANCH_ROOTS", "").strip()
    if not raw:
        return None  # no scoping → warn for every repo
    return [Path(os.path.expanduser(p)).resolve() for p in raw.split(":") if p]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if payload.get("tool_name") != "Bash":
        return 0

    cmd = payload.get("tool_input", {}).get("command", "")
    if not cmd or not re.search(r"\bgit\s+commit\b(?!-)", cmd):
        return 0

    # Resolve the repo dir from `git -C <dir>`, a leading `cd <dir> &&`, or cwd.
    repo_dir = None
    m = re.search(r"\bgit\s+-C\s+(\S+)", cmd)
    if m:
        repo_dir = os.path.expanduser(m.group(1))
    else:
        m = re.match(r"\s*cd\s+(\S+)\s*&&", cmd)
        if m:
            repo_dir = os.path.expanduser(m.group(1))
    if repo_dir is None:
        repo_dir = os.getcwd()

    try:
        repo_dir = Path(repo_dir).resolve()
    except (OSError, RuntimeError):
        return 0

    roots = scope_roots()
    if roots is not None:
        if not any(_is_relative_to(repo_dir, r) for r in roots):
            return 0

    try:
        result = subprocess.run(
            ["git", "-C", str(repo_dir), "branch", "--show-current"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        branch = result.stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return 0

    if branch in PROTECTED:
        user = os.environ.get("USER", "yourname")
        msg = (
            f"⚠️  About to commit on '{branch}' of {repo_dir}. "
            f"Convention: commit on a personal branch first. "
            f"Suggested: `git switch -c {user}/<topic>` "
            f"(this is a warning, not a block — commit will proceed)."
        )
        print(json.dumps({"systemMessage": msg}))

    return 0


def _is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    sys.exit(main())
