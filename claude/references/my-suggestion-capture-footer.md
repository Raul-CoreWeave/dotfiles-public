# My-suggestion capture — footer format (detailed spec)

Catalog content referenced from global `~/.claude/CLAUDE.md` § "Interaction and Reasoning Guidelines" → "Name CLAUDE.md rules descriptively in chat" and the "My-suggestion capture (Rule B)" framework in global `~/.claude/CLAUDE.md` § "Cross-Session Persistence" → "Capture-trigger discipline."

## Footer shape

When surfacing my-suggestion capture candidates at the end of a response, use this framing — not "Surfaced items (Rule B):".

```
Items I noticed during this turn (per global CLAUDE.md "my-suggestion capture" rule):

1. `<item>` — ~Nmin, `<conflict>`. **Recommended: <routing>** (<one-line why>).
2. `<item>` — ~Nmin, `<conflict>`. **Recommended: <routing>** (<one-line why>).
3. `<item>` — ~Nmin, `<conflict>`. **Recommended: undecided** — <one-line tradeoff>; defer to you.

Reply: `apply recommendations for all` (or `apply recommendations for N`), or override per item — `numbers (run now)` / `chain N` (integrate) / `parallel N` (spawn) / `park N` (P3) / `Pn N` (priority n=1|2) / `skip`.
```

## Per-item recommendation discipline

The original footer punted every item to the user's judgment. That's bad ergonomics when I've already formed an opinion. **Always include a recommendation line per item**, except when the trade-off is genuinely 50/50 — then mark `Recommended: undecided` and name the trade-off briefly so the user has the same information I'm balancing.

Format of the recommendation:

- `**Recommended: <routing>** (<one-line why>)` — bolded routing, brief justification in parens. Routing is one of the six types (run / chain / parallel / park / Pn / skip).
- The "why" is ~1 sentence, sometimes shorter. Examples:
  - "small, contained, would unblock the next chain" → `run`
  - "blocks on a teammate's response; nothing for me to do solo right now" → `park P2`
  - "design-thread, not actionable today" → `park P3`
  - "outside the scope of what I should act on here" → `skip`
- When undecided: `Recommended: undecided — <one-line tradeoff>`. Don't fake decisiveness.

## Bulk-accept syntax

The user can scan all recommendations once and reply with:

- `apply recommendations for all` — accept my recommendations on every item.
- `apply recommendations for N` (or `apply recommendations for N, M`) — accept for specific items; others dropped silently.
- Per-item override: use the six-type syntax (`run N`, `park N`, `Pn N`, etc.) to override my recommendation on item N.
- `skip` — drop all candidates (overrides any recommendation).

Bulk-accept paths exist because re-typing N decisions when I already made them correctly is friction. Reserve per-item override for cases where my recommendation was wrong or the user wants different prioritization.

## Footer-format details

- Always include all six per-item response types defined by the global rule, one example each, plus the bulk-accept option. Don't abbreviate — the full vocabulary is small enough to render inline and makes the choice surface obvious.
- The bare-numbers option needs the explicit "(run now)" qualifier; without it, the reader has to know-by-convention that bare numbers mean "execute item N." Past failure: footer started with "Reply with numbers, …" — opaque.
- Don't duplicate `P1 N` and `P2 N` as separate examples — the slash separator in "P1 N / P2 N" was meant to show "either syntax works," but reads as redundant. Use `Pn N` with a parenthetical "(priority n=1|2)" — one syntactic example, one clarification.
- Six per-item types: `numbers (run now)` / `chain N` (integrate into current chain) / `parallel N` (spawn background agent) / `park N` (parking-lot todo, default P3) / `Pn N` (parking-lot todo with explicit priority) / `skip` (drop the candidates).
- Bulk-accept types: `apply recommendations for all` / `apply recommendations for N` — accept my recommendation(s) without re-specifying the routing.

## Related

- Global `~/.claude/CLAUDE.md` § "Cross-Session Persistence" → "Capture-trigger discipline" → Rule B (my-suggestion capture) — defines *when* the footer fires.
- Global `~/.claude/CLAUDE.md` § "Interaction and Reasoning Guidelines" → "Name CLAUDE.md rules descriptively in chat" — defines *how* the footer is labeled (don't leak internal numbering).
