# Example 4 — fresh eyes after implementation (the reviewer)

**The request** (verbatim, paths stripped):

> Fresh-context adversarial review, final gate before staging. … v0.14.0
> is the UNSTAGED diff … You wrote none of it. Try to BREAK it; modify
> nothing; findings CRITICAL/HIGH/MEDIUM/LOW with repro or file:line;
> verdict ship / fix-first. Work only in mktemp homes/repos …

Fleet policy: after any real implementation, a `reviewer` reads the diff
with context it didn't write, before the work is called done. Distinct
from the corsaire — the reviewer prioritizes a whole diff; the corsaire
hunts one failure to the root.

**Triage → route**

- Post-implementation gate, must be a reader who didn't author the code →
  **`reviewer` agent**, read-only tools, `model: sonnet`.
- Returns a prioritized report; the admiral acts on it before staging.

**Measured cost** (`~/.amiral/butin.jsonl`, baseline Opus)

| | |
| --- | --- |
| Model actually used | Sonnet 5 |
| Real cost | **$3.66** |
| Same tokens at the Opus baseline | $18.30 |
| **Saved on this one task** | **$14.64** |

Review is a recurring cost — it happens after *every* implementation. Run
it on the frontier model by reflex and it adds up fast; routed to Sonnet
it's a fifth of that, every time, with no loss of the fresh-context
value that made it worth doing.
