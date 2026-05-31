#!/usr/bin/env python3
"""
PreToolUse:Bash hook — warn when a `git commit`'s staged changes touch a
project skill or global Claude Code skill home, prompting the engineer to run
/sync-skill-docs <skill> before landing the commit.

Skill home patterns detected:
  .claude/skills-base/<X>/   — alternate skills dir name (per a routing convention)
  .claude/skills/<X>/        — per-repo skills directory
  claude/skills/<X>/         — dotfiles source-of-truth (~/dotfiles/claude/skills/)
  claude/skills-base/<X>/    — defensive

Rationale: a contribution rule requires cross-layer doc sync as part of any
skill change. Compliance tends to drift when the rule lives only as prose; the
warning at the commit moment is the deterministic nudge. Sibling: /sync-skill-docs.

Warn-only — never blocks the commit. Engineer's call whether sync was already
run in a prior session, or whether the staged changes are doc-only and don't
need a sync pass.
"""
import json
import os
import re
import subprocess
import sys

SKILL_PATH_RE = re.compile(r"(?:^|/)\.?claude/skills(?:-base)?/([^/]+)/")


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
        result = subprocess.run(
            ["git", "-C", repo_dir, "diff", "--cached", "--name-only"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return 0
    if result.returncode != 0:
        return 0

    skills = []
    seen = set()
    for path in result.stdout.splitlines():
        m = SKILL_PATH_RE.search(path)
        if m:
            name = m.group(1)
            if name not in seen:
                seen.add(name)
                skills.append(name)

    if not skills:
        return 0

    skill_list = ", ".join(f"`{n}`" for n in skills)
    suggestions = "\n".join(f"  /sync-skill-docs {n}" for n in skills)
    msg = (
        f"⚠️  Staged changes touch skill home(s): {skill_list}. "
        f"If you haven't yet, run before committing:\n{suggestions}\n"
        f"(warning only — commit will proceed; per team-rules/contribution-discipline.md §1)"
    )
    print(json.dumps({"systemMessage": msg}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
