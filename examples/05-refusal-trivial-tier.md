# Example 5 — the admiral refused to delegate

The discipline is the product as much as the routing. Not every task
should be handed off — and knowing which ones shouldn't is the whole job.

**The request** (real, during the v0.15.2 doc pass)

> Two stale strings: a "6 markdown files" count that should read 7 (an
> agent was added since), and `.claude-plugin/plugin.json` still pinned at
> version `0.12.2` while the repo shipped `0.15.2`. Fix both.

**Triage → the admiral did it itself**

- A single-word change in one line, and one version string in one JSON
  field. **Trivial tier per fleet policy.**
- Delegating means: spawn a worker, load it with context, wait for a
  transcript, review the diff, verify — all to change two tokens. The
  hand-off costs more than the edit.
- So the admiral edited both directly, in place, and moved on. **No
  worker was spawned. No receipt was written.** That absence is correct —
  it is the policy working, not a gap in the measurement.

**"Measured cost"**

There isn't one, and that's the point. A refusal-to-delegate produces no
worker event in `~/.amiral/butin.jsonl` because no worker ran — the only
cost was the handful of the admiral's own tokens to make two small edits.
Both changes shipped in v0.15.2 (see `CHANGELOG.md`).

**Why this matters**

A router that delegates *everything* is as wasteful as one that delegates
nothing — it just moves the waste into orchestration overhead. amiral's
policy triages *down* as readily as it routes out: trivial edits inline,
mechanical bulk to the cheapest model, real features to a mid model,
risky work to an adversary. The savings in examples 1–4 are only honest
because the admiral also knows when the cheapest route is no route at all.
