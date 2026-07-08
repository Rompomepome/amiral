# Landscape: where amiral sits

Honest positioning against what exists (June 2026). Spoiler: amiral is
deliberately the smallest thing on this page.

## The heavyweights

**Ruflo (ex claude-flow)** — the most-adopted community orchestrator:
250,000+ lines of TypeScript plus Rust WASM kernels, hive-mind queen/
worker topology, Raft/BFT consensus, 87+ native MCP tools. Impressive
claims (75% API cost savings, 30-50% token reduction). Two catches:
it is a *platform you adopt*, and it is **API-only — blocked on Pro/Max
subscriptions since April 2026**. If you pay for a Claude subscription,
Ruflo's cost savings are not available to you at all.

**ClaudeFast Code Kit** — 18 specialized agents plus a /team-plan
pipeline. A layer above orchestration. Great if you want opinionated
specialists; heavy if you want a routing pattern.

**Claude Octopus** — different philosophy: fan a task out to up to 8
*different* models (Claude, GPT, Gemini, local...) and gate on 75%
consensus. Solves "models grading their own homework" across vendors.
Complementary to amiral, not competing.

**Maestro** — lightweight multi-role division of labor inside Claude
Code. Closest in spirit to amiral; focuses on roles, not on quota
routing or verification gates.

## The built-ins

**opusplan** — Claude Code's native hybrid: Opus in plan mode, Sonnet
in execution. The right instinct, minimal control: no Fable brain, no
per-worker specialization, no policy, no verification discipline. There
is no `fableplan` — amiral is effectively that, plus gates.

**Agent Teams (experimental)** — peer sessions that communicate.
Orthogonal: amiral routes *within* one session's delegation tree.

## The measurement layer

**ccusage** — the community CLI for reading Claude Code's local usage
data. Not an orchestrator; it is how you *measure* any of the above.
amiral's [BENCHMARKS.md](../BENCHMARKS.md) protocol is built on it.

## Where amiral fits

| | Ruflo | Code Kit | amiral |
| --- | --- | --- | --- |
| Footprint | 250k+ LOC platform | 18-agent kit | **7 markdown files** |
| Primitives | Custom engine + MCP | Custom agents | **Native Claude Code only** |
| Works on Pro/Max subscription | ❌ API only | ✅ | ✅ |
| Survives CC updates | Depends on engine | Mostly | **Yes — it's just config** |
| Verification gates | Pipeline-level | Partial | **Policy + optional hook** |
| Learning curve | Days | Hours | **Minutes** |

amiral's bet: for most solo devs and small teams, the 80% of the value
(frontier planning, cheap execution, verified results) needs none of
the machinery. When you genuinely need swarm topologies and consensus
protocols, graduate to Ruflo — and take the amiral policy with you.
