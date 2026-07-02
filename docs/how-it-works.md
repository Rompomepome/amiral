# How it works

## The three layers

**Layer 1 — Persistent memory (the policy).** `install.sh` copies the
repo's `CLAUDE.md` to `~/.claude/fable-lean-policy.md` and adds one
`@fable-lean-policy.md` import line to your global `~/.claude/CLAUDE.md`.
Claude Code reads it at every session start, in every project. It
teaches the orchestrator role, the fan-out discipline, and the
verification gates. It is deliberately model-agnostic: it applies even
in `sonnet-fast` mode.

**Layer 2 — Worker definitions (the agents).** Three markdown files in
`~/.claude/agents/`, each with YAML frontmatter declaring its model,
tools and effort:

- `implementer` (sonnet, full write access) — features against a plan
- `grunt` (haiku, effort: low, no Write) — mechanical bulk work
- `reviewer` (sonnet, read-only tools) — fresh-context review

The main agent reads the `description` field to decide when to
delegate — write descriptions like tool descriptions.

**Layer 3 — Launch profiles (the aliases).** The model choice lives
here, not in the policy. `fable-lean` sets
`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (highest precedence: a hard cost
ceiling whatever the orchestrator spawns) plus
`CLAUDE_CODE_EFFORT_LEVEL=xhigh`. `fable-fine` drops the env var so the
frontmatter routing takes over.

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
