# Why routing workers saves real quota

## The cost structure

Fable 5 (June 2026): **$10 / MTok input, $50 / MTok output**, 1M context
window. Sonnet-class and Haiku-class models cost a fraction of that.

A typical feature has two phases with very different token profiles:

| Phase | Token profile | Needs frontier intelligence? |
| --- | --- | --- |
| Plan / decompose / judge | Short, dense, high-value | **Yes** |
| Implement / retry / test / lint loops | Long, repetitive, high-volume | Rarely |

The execution phase is where the tokens go: dozens of file writes, test
runs, error-fix retries. Paying frontier price for that phase is the
waste this repo removes.

## The multiplication factor

- Subagent-heavy workflows can consume roughly **7x the tokens** of a
  single-thread session, because each worker holds its own context
  window (community measurements, 2026).
- Fable 5 with ultracode has been observed spawning **7 parallel agents
  for a single small refactor** — see
  [anthropics/claude-code#66867](https://github.com/anthropics/claude-code/issues/66867).
  Same task on Opus 4.8: ~1M tokens / 33% of a quota window. On Fable:
  49% of the window.
- Community reports: Fable + ultracode + a codebase-wide audit prompt =
  a full 5-hour Max window consumed in **~7 minutes**.

Combine both effects (7x fan-out x frontier pricing) and naive Fable
orchestration is easily an order of magnitude more expensive than the
same work with routed workers.

## What the routing changes

With `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`:

- The orchestrator (Fable) only spends tokens on planning, delegation
  messages, verification, and review — the short, high-value phases.
- Every token-heavy execution loop runs on Sonnet (or Haiku for the
  grunt agent in `fable-fine` mode).
- The anti-fan-out policy caps parallelism at 3-4 workers, which is also
  the community sweet spot: beyond that you spend more merging summaries
  than you save parallelizing.

## Precedence (why the env var wins)

Subagent model resolution order (official docs):

1. `CLAUDE_CODE_SUBAGENT_MODEL` (environment) — **wins**
2. per-invocation model parameter
3. agent frontmatter `model:`
4. main conversation model (inherit)

`amiral` uses (1) as a hard cost ceiling. `fable-fine` drops the env
var so (3) takes over, letting `grunt` run on Haiku.

One caveat: organization `availableModels` allowlists are checked; a
value resolving to an excluded model silently falls back to inherit.
This is why the README insists you verify the routing once.
