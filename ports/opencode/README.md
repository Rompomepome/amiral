# amiral on OpenCode

OpenCode speaks 75+ model providers, which makes it the natural home for
the amiral pattern when you want the discipline on models other than
Claude. amiral does not ship a provider bridge (that would be a runtime
to maintain); instead it gives OpenCode the same worker policy through
the open AGENTS.md standard in [`../AGENTS.md`](../AGENTS.md).

## Setup

OpenCode reads `AGENTS.md` from your project root:

```bash
# from your project root
cp /path/to/amiral/ports/AGENTS.md ./AGENTS.md
```

That's the discipline in place: plan before multi-file work, keep trivial
edits inline, and gate "done" on a real build. Drop a `verify.sh`
(see [`../../templates/verify-nextjs.sh`](../../templates/verify-nextjs.sh))
so completion is machine-checked, not vibes.

## The brain/hands split on OpenCode

The amiral idea is: an expensive model plans and checks; cheap models do
the volume. OpenCode lets you pick the model per session, so you get the
same shape by choosing:

- **Planning / judgment:** a frontier model (GPT-5-class, Claude Opus,
  Gemini Pro — whatever you route through OpenCode).
- **Execution / bulk:** a cheaper model (a mini/flash tier).

The discipline in `AGENTS.md` tells the model to plan big and keep
execution lean, so most tokens land on the cheaper tier regardless of
which providers you wire up. Same pattern Anthropic measured for Claude
(see the repo's "Anthropic's own numbers"), applied to whatever OpenCode
can reach.

## What's portable and what isn't

Portable: the policy — plan/execute split, verification gate, the
matelot's "don't sprawl" rules. That's model-agnostic by construction.

Not included: an engine that auto-routes between providers mid-task.
OpenCode already owns provider selection; amiral doesn't duplicate it.
amiral is the discipline; OpenCode is the reach.
