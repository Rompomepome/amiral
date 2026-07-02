# fable-lean

**Big brain, cheap hands.** Quota-optimized model routing for Claude Code: run a frontier model (Fable 5) as the *orchestrator* and delegate execution to cheaper workers (Sonnet / Haiku).

*Français ? Lisez le [README.fr.md](README.fr.md).*

![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.197%2B-white?style=flat&labelColor=555)
![License](https://img.shields.io/badge/license-MIT-white?style=flat&labelColor=555)
![Model routing](https://img.shields.io/badge/pattern-orchestrator%2Fworkers-white?style=flat&labelColor=555)

> [!TIP]
> Jump to [**How to Use**](#-how-to-use) if you just want the 2-minute setup.

---

## 🧠 The problem

Fable 5 is the most capable model in Claude Code — and the most expensive way to burn a usage window:

- Fable + `ultracode` has been reported to consume a **full 5-hour usage window in ~7 minutes** on a codebase-wide audit ([r/ClaudeAI](https://www.reddit.com/r/ClaudeAI/)).
- Fable in ultracode mode has been observed **spawning 7 parallel agents for a single small refactoring task** — disproportionate quota consumption vs. Opus on the same task ([anthropics/claude-code#66867](https://github.com/anthropics/claude-code/issues/66867)).
- Every subagent inherits the main model by default. Orchestrate with Fable naively and **every worker is also Fable**.

You don't need frontier-model intelligence to rename 40 imports. You need it to *plan* the rename and *verify* it happened.

## 💡 The pattern

![fable-lean architecture](assets/architecture.svg)

<details>
<summary>ASCII version</summary>

```
                          ┌─────────────────────────┐
                          │   FABLE 5  (xhigh)      │
                          │   plans · delegates ·   │
                          │   verifies · reviews    │
                          └───────────┬─────────────┘
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
   ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
   │ implementer       │  │ grunt             │  │ reviewer          │
   │ model: sonnet     │  │ model: haiku      │  │ model: sonnet     │
   │ writes features   │  │ mechanical bulk   │  │ fresh-context     │
   │ vs a valid plan   │  │ work, low effort  │  │ review, read-only │
   └───────────────────┘  └───────────────────┘  └───────────────────┘
```

</details>

Three levers, combined:

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** — hard-forces every subagent onto a cheap model, whatever Fable decides to spawn. Highest precedence in the [resolution order](https://code.claude.com/docs/en/sub-agents).
2. **Per-agent `model:` frontmatter** — fine-grained routing: Sonnet for real implementation, Haiku for mechanical work.
3. **A memory policy (`CLAUDE.md`)** — teaches the orchestrator to delegate, to *not* fan out 7 agents on a 1-agent task, and to verify (build/typecheck/lint) before claiming "done".

## 📦 What's inside

| Component | Location | What it does |
| --- | --- | --- |
| 🅐 **implementer** | [`.claude/agents/implementer.md`](.claude/agents/implementer.md) | Implements features against a validated plan. `model: sonnet`. Full write access. |
| 🅐 **grunt** | [`.claude/agents/grunt.md`](.claude/agents/grunt.md) | Mass mechanical work (renames, boilerplate, find/replace migrations). `model: haiku`, `effort: low`. |
| 🅐 **reviewer** | [`.claude/agents/reviewer.md`](.claude/agents/reviewer.md) | Fresh-context code review right after implementation. Read-only tools, prioritized report. |
| 🅢 **/plan-ship** | [`.claude/skills/plan-ship/SKILL.md`](.claude/skills/plan-ship/SKILL.md) | One command: plan → delegate → verify → review → summary. Never commits without your OK. |
| 📜 **Routing policy** | [`CLAUDE.md`](CLAUDE.md) | The persistent memory: orchestrator role, anti-fan-out discipline, mandatory verification. |
| ⚡ **Shell profiles** | [`shell/fable-aliases.sh`](shell/fable-aliases.sh) | `fable-lean`, `fable-fine`, `fable-ultra`, `sonnet-fast` — one word to launch each mode. |
| 🔧 **Installer** | [`install.sh`](install.sh) | Idempotent. Copies everything to `~/.claude/`, backs up your existing `CLAUDE.md`, never overwrites. |

This repo **dogfoods itself**: clone it, open Claude Code inside, and the routing config in `.claude/` is live.

## ⚡ How to Use

```bash
git clone https://github.com/YOUR_USERNAME/fable-lean.git
cd fable-lean
./install.sh

# load the aliases
echo 'source ~/.claude/fable-aliases.sh' >> ~/.zshrc && source ~/.zshrc

# make sure Claude Code is recent (Sonnet 5 needs v2.1.197+)
claude update
```

Then, in any project:

| Command | Brain | Workers | When |
| --- | --- | --- | --- |
| `fable-lean` | Fable 5 @ xhigh | **forced Sonnet** | 🏆 Daily driver. Max planning capability, capped execution cost. |
| `fable-fine` | Fable 5 @ xhigh | per-agent frontmatter (Sonnet/Haiku) | When you want Haiku doing the grunt work. |
| `fable-ultra` | Fable 5 + ultracode | forced Sonnet | Big audits **only**. Then type `/effort` → `ultracode`. 🔥 Quota incinerator. |
| `sonnet-fast` | Sonnet @ high | inherit | Everything that doesn't deserve Fable. |

Inside a session:

```
/plan-ship add JWT refresh-token rotation to the auth middleware
```

…and the orchestrator plans, hands the implementation to `implementer`, bulk edits to `grunt`, verification gates the result, and `reviewer` reads the diff with fresh eyes before you get a summary.

## ✅ Verify the routing actually works

**Do this once.** If `sonnet` isn't resolved as a subagent model on your version, workers silently fall back to the main model — i.e. Fable — and your quota bleeds anyway.

1. Launch `fable-lean` in a project.
2. Ask for something that delegates ("implement X using the implementer agent").
3. Check `/agents` or the transcript: workers must show **Sonnet**, not Fable.
4. If not: edit `~/.claude/fable-aliases.sh` and replace `sonnet` with the full model ID (e.g. `claude-sonnet-5`).

## 🧮 Why this saves real money

- Fable 5 is priced at **$10 / MTok input, $50 / MTok output** — the execution phase of a feature (dozens of file writes, test runs, retries) is where the tokens go.
- Subagent-heavy workflows can consume **~7× the tokens** of a single-thread session, since each worker holds its own context window.
- Routing workers to Sonnet/Haiku means the token-heavy phase happens at a fraction of the cost, while Fable only pays for what it's uniquely good at: planning, decomposition, judgment, final review.

Full math and sources: [docs/quota-math.md](docs/quota-math.md).

## 🛡️ Design principles

1. **The policy is model-agnostic.** Delegation discipline + verification gates are just good practice — they hold even in `sonnet-fast` mode. Model choice lives in the alias, not the policy.
2. **Anti-fan-out is explicit.** The policy caps parallel workers at 3–4 and states "a small refactor = 1 agent, not 7", directly countering the observed over-spawning behavior.
3. **"Done" means verified.** Build + typecheck + lint (+ tests when present) gate every completion claim. UI changes require render verification, not just green tests.
4. **Never destructive.** The installer backs up `CLAUDE.md`, imports via `@`-reference instead of overwriting, and is safe to re-run.
5. **No auto-commit.** The orchestrator never commits or pushes without an explicit human OK.

## 🗺️ Roadmap

- [ ] `verify.sh` templates per stack (Next.js, Python, Rust)
- [ ] Optional [Ralph-loop](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) integration: lean routing inside autonomous loops
- [ ] Plugin packaging for one-command install via marketplace
- [ ] Windows (PowerShell) profiles

## 🤝 Contributing

PRs welcome — especially real-world quota numbers (before/after), new worker agent definitions, and stack-specific policies. Open an issue with your use case first if it's a big change.

## 📄 License

[MIT](LICENSE)

---

*Inspired by the structure of [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice). Built from the official [subagents](https://code.claude.com/docs/en/sub-agents) and [model configuration](https://code.claude.com/docs/en/model-config) docs.*
