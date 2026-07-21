# Example 1 — a real feature, delegated to the implementer

**The request** (verbatim, paths stripped):

> Implement v0.13.0 PART 2: the butin STATUSLINE for Claude Code.
> Authoritative spec: DESIGN-NOTES.md §1 (read it fully first) … Read
> before writing: DESIGN-NOTES.md, bin/amiral-butin, lib/butin/core.awk
> (NEVER modify it) …

A multi-file feature with a spec to honor, an existing calculator not to
touch, and a producer/cache/renderer split to build. This is exactly the
tier the policy sends to the `implementer`: real code across several
files, judgment about *how* it should work, but nothing the admiral needs
to write by hand.

**Triage → route**

- Not trivial (spans producer + cache + renderer, honors a written spec).
- Not mechanical (design judgment required).
- Real implementation → **`implementer` agent, `model: sonnet`.**
- The admiral planned it, delegated it, and verified the result — it did
  not write the bulk itself. The admiral doesn't row.

**Measured cost** (`~/.amiral/butin.jsonl`, baseline Opus)

| | |
| --- | --- |
| Model actually used | Sonnet 5 |
| Real cost | **$28.70** |
| Same tokens at the Opus baseline | $143.49 |
| **Saved on this one task** | **$114.79** |

The worker did the token-heavy execution at ~1/5 the frontier rate; the
brain only paid for planning and the final review. One task, one receipt,
anyone can re-price it from the same transcript.
