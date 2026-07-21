# Example 3 — multi-file correctness work, delegated

**The request** (verbatim, paths stripped):

> The butin report attributes routing savings amiral did NOT cause. Live
> backfill surfaced 9 subagent types. Only 5 are amiral's (implementer,
> grunt, reviewer, corsaire, advisor). Four (general-purpose, Explore,
> claude-code-guide, frontend-specialist) come from Claude Code itself …
> The headline "net saved" currently sums ALL worker agents, so it
> credits amiral [with routing it never performed] …

An accounting-correctness change across the calculator, the report, the
statusline cache, the badge, and a manifest — with tests. Real logic,
multiple files, a clear plan to execute against.

**Triage → route**

- Multi-file logic with a correctness contract → real implementation.
- **`implementer` agent, `model: sonnet`**, against a validated plan.
- Followed by a fresh-context `reviewer` (see [example 4](04-reviewer-fresh-context.md))
  before it was called done.

**Measured cost** (`~/.amiral/butin.jsonl`, baseline Opus)

| | |
| --- | --- |
| Model actually used | Sonnet 5 |
| Real cost | **$4.47** |
| Same tokens at the Opus baseline | $22.35 |
| **Saved on this one task** | **$17.88** |

The point of example 1 and this one together: the 5:1 gap isn't a
one-off on a big task. It repeats on every routed unit of work, large or
small, because the worker rate is the worker rate.
