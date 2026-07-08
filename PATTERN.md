# The amiral pattern — a CLI-agnostic spec

**Expensive brain plans and verifies. Cheap hands execute. Done means
verified.** This document describes the pattern independently of any
tool, so you can implement it in whatever agentic CLI you use. This
repo is the **Claude Code reference implementation**; the pattern
itself belongs to no vendor.

## Prior art (credit where due)

This pattern was not invented here:

- **Aider's architect/editor mode** (`aider --architect`) pairs a
  strong reasoning model for planning with a cheaper editor model for
  applying changes — the two-tier split, proven in production for years.
- **Roo Code's mode system** separates Architect / Orchestrator / Code
  roles with per-mode model selection.
- **Claude Code's `opusplan`** does Opus-plans / Sonnet-executes
  natively, without worker specialization.

amiral's contribution is the *complete* expression on Claude Code:
routing + specialized workers + anti-fan-out policy + verification
gates + a doctor for the silent failure modes.

## The pattern, formally

1. **Two tiers.** A BRAIN model (frontier-class) and one or more HANDS
   models (mid/small-class). The brain never does bulk execution; the
   hands never make architecture decisions.
2. **The brain's contract:** understand, decompose into independent
   units, write a *verifiable* plan (explicit done-criteria), delegate,
   then judge results against the criteria — not against vibes.
3. **The hands' contract (the matelot discipline):** execute exactly
   the plan, flag ambiguity instead of inventing, verify mechanically
   (build/typecheck/lint/tests) before reporting done, report concisely.
4. **Fan-out discipline:** parallel hands only for genuinely
   independent units (disjoint files); cap at 3-4; a small task = 1
   worker, not 7.
5. **Verification is structural,** not aspirational: a machine-runnable
   gate (`verify.sh` exit 0) defines "done". Where the harness supports
   it, enforce with a hook; where it doesn't, the brain re-runs the gate
   itself before accepting.
6. **Two wirings, one idea.** Orchestrator: the brain plans and fans
   out to workers (best when work parallelizes). Advisor: a cheap
   executor runs the loop and consults the brain only on hard judgment
   calls (best for long single-threaded work). Both keep most tokens on
   the cheap tier; pick per task, not per religion.
7. **An adversarial pass before risk:** for changes touching auth,
   money, user input or data, a pre-mortem attacker (fresh context,
   read-only) assumes the shipped feature already failed and hunts the
   cause — before users do.
8. **A human gate before irreversibility:** no commit/push/deploy
   without explicit approval.

## Implementation map per CLI

| CLI | Brain/hands routing | Portable discipline | Verification gate |
| --- | --- | --- | --- |
| **Claude Code** | ✅ Full native: `CLAUDE_CODE_SUBAGENT_MODEL` + per-agent `model:` frontmatter (this repo) | `CLAUDE.md` (installed by amiral) | `SubagentStop` hook (this repo, opt-in) |
| **Aider** | ✅ Native: `aider --architect --model <brain> --editor-model <hands>` | reads `AGENTS.md` → drop [`ports/AGENTS.md`](ports/AGENTS.md) | brain re-runs `verify.sh` (no hook layer) |
| **OpenCode** | ✅ Per-agent model in agent config (75+ providers) | reads `AGENTS.md` | plugin/scripting layer |
| **Roo Code** | ✅ Per-mode model selection (Architect/Orchestrator/Code) | reads `AGENTS.md` | mode rules |
| **Codex CLI** | ⚠️ Manual: one session as brain (plan), spawn/exec with a cheaper `-m` for execution | reads `AGENTS.md` natively | `AGENTS.md` "programmatic checks" convention |
| **Gemini CLI** | ⚠️ Manual: model flag per session | `GEMINI.md`, or point `contextFileName` at `AGENTS.md` | manual |
| **No routing at all** | 🧭 *You* are the amiral: plan in a frontier chat, execute in the cheap CLI, run `verify.sh` yourself | `AGENTS.md` | manual |

Legend: ✅ the CLI can route models itself · ⚠️ two-session manual split
· 🧭 degraded but real — the discipline still pays.

## What is deliberately NOT here

No adapters, no wrapper binary, no per-CLI code to maintain. The
implementation stays Claude Code; the *discipline* travels as prose
([`ports/AGENTS.md`](ports/AGENTS.md)). Tool-specific port writeups are
welcome as community PRs into `ports/`.
