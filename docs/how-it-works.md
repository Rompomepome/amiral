# How it works

## The three layers

**Layer 1 — Persistent memory (the policy).** `install.sh` copies the
repo's `CLAUDE.md` to `~/.claude/amiral-policy.md` and adds one
`@amiral-policy.md` import line to your global `~/.claude/CLAUDE.md`.
Claude Code reads it at every session start, in every project. It
teaches the orchestrator role, the fan-out discipline, and the
verification gates. It is deliberately model-agnostic: it applies even
in `matelot` mode.

**Layer 2 — Worker definitions (the agents).** Five markdown files in
`~/.claude/agents/`, each with YAML frontmatter declaring its model,
tools and effort:

- `implementer` (sonnet, full write access) — features against a plan
- `grunt` (haiku, effort: low, no Write) — mechanical bulk work
- `reviewer` (sonnet, read-only tools) — fresh-context review
- `corsaire` (sonnet, read-only tools) — licensed adversary: pre-mortem
  attack on risky or vibe-coded changes
- `advisor` (your brain model, read-only) — the expensive brain consulted
  on demand by a cheaper executor for hard judgment calls; its model is
  pinned to your chosen brain by amiral-setup

The main agent reads the `description` field to decide when to
delegate — write descriptions like tool descriptions.

**Layer 3 — Launch profiles (the aliases).** The model choice lives
here, not in the policy. `amiral` sets
`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (highest precedence: a hard cost
ceiling whatever the orchestrator spawns) plus
`--effort xhigh`. `amiral-fine` drops the subagent env var so the
frontmatter routing takes over.

**First-run setup.** The very first `amiral` runs `amiral-setup` once: it
asks which plan you are on (Pro / Max / credits) and pins the best
in-plan brain to `~/.claude/amiral.env` (Pro -> Sonnet, Max -> Opus,
credits -> Fable). Every later run loads that file silently, so you type
one word and never choose a model again. Re-run `amiral-setup` to change
it. If you skip setup, the default brain is Opus (included on Max; Pro
serves Sonnet within-plan), workers on Sonnet.

## The /plan-ship workflow

A skill with `disable-model-invocation: true` (so it only runs when YOU
type it), following the pattern every major Claude Code workflow
converges on: Research -> Plan -> Execute -> Review -> Ship.

1. PLAN with the orchestrator (cheap: short, high-value tokens)
2. DELEGATE execution to workers (heavy tokens at Sonnet/Haiku price)
3. VERIFY with build/typecheck/lint gates
4. REVIEW with a fresh-context agent that didn't write the code
5. SUMMARIZE and stop before commit (human gate)

## Why fresh-context review matters

The reviewer agent didn't write the code, so it doesn't carry the
writer's assumptions. This catches more than asking the same context
window to grade its own output — one of the documented failure modes of
single-window agentic work.
