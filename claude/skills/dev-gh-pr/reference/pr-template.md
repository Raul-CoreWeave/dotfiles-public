# PR body template — /dev-gh-pr Phase 5

This is the structural skeleton the LLM fills in during /dev-gh-pr Phase 5. It is NOT a verbatim template — the LLM must adapt the structure to match the repo's prior PR voice (inferred from `recent_prs` in the draft-pr-body.sh output).

## Required sections

```markdown
## Summary

<1–3 bullet points describing what changed and the motivation. Lead with the
"why" when non-obvious; one bullet per logical change. Mirror the repo's
prior PR voice (terse vs. paragraph) inferred from recent_prs.>

## Test plan

<Bulleted markdown checklist of how to verify the change. Required even for
docs-only PRs (testing-the-rendered-doc counts). Each item is independently
checkable.>

- [ ] <step 1>
- [ ] <step 2>
```

## Optional sections (include only when applicable)

```markdown
## Known limitations

<Only if /dev-gh-pr Phase 3 reached "Ignore and proceed" with Medium+ findings.
One line per accepted finding, with a brief rationale.>

- <finding>: <one-line rationale, e.g., "taste-divergent, not in scope">
```

```markdown
## Linked tickets

<Only if the branch name or commit subjects reference a tracking ticket or
issue. Lead with the ticket/issue key + URL.>

- owner/repo#<issue>: <one-line summary>
- <TRACKER-1234>: <one-line summary>
```

## Hard rules — applied unconditionally

1. **No Claude / AI authorship attribution.** No "Co-Authored-By: Claude", no "🤖 Generated with [Claude Code]", no equivalents. Strip any such trailer the engineer's local PR template might inject by default.
2. **No phase numbers, step IDs, or internal-design vocab.** "Per /dev-gh-pr Phase 5" is for the SKILL.md, not the PR. The PR audience is reviewers who haven't read the skill internals.
3. **Body length matches change size.** A 3-line bugfix doesn't need a 30-line PR body. A 500-line refactor probably does. Don't pad.
4. **Plain English title.** Match the repo's commit-style for the title (inferred from voice_sample): imperative bare ("Add X") vs conventional ("feat: add X"). When mixed, ask the engineer.

## Anti-examples

```markdown
<!-- BAD: phase reference, internal vocab -->
## Summary
- Per /dev-gh-pr Phase 5, this PR consolidates the simplify+deep-review pipeline...

<!-- BAD: Claude attribution -->
Co-Authored-By: Claude <noreply@anthropic.com>

<!-- BAD: padded body for a one-line change -->
## Summary
This PR introduces a new approach to handling the typo in the README...
## Test plan
- [ ] cat README.md and verify the typo is gone
- [ ] git log shows the commit
- [ ] CI passes
```

## Good examples (mirroring observed repo voices)

### Conventional-style commit repo

```markdown
## Summary
- Add `retry-with-backoff` helper so transient HTTP 5xx responses are retried up to 3 times with jittered exponential backoff
- Wire the helper into the API client's request path; preserve existing per-call timeout behavior

## Test plan
- [ ] Run the unit suite; verify the new backoff test passes
- [ ] Point the client at a flaky local server; confirm it recovers from a single injected 503
- [ ] Confirm a non-retryable 400 still fails fast (no backoff loop)
```

### Imperative-bare repo

```markdown
## Summary
- Exclude generated snapshot files from the bulk-rename recipe; without this filter the find/replace step would rewrite frozen provenance snapshots.

## Test plan
- [ ] Run the new recipe against a known multi-referrer file; verify only active files surface
- [ ] Round-trip rename a candidate file and assert `git diff --stat` is empty after reversal
```
