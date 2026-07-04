# ⚓ amiral

**The admiral doesn't row.** Orchestrator/worker model routing for Claude Code: an expensive brain (Fable 5, Opus) plans, delegates and verifies — cheap hands (Sonnet, Haiku) do the token-heavy execution.

*Français ? Lisez le [README.fr.md](README.fr.md).*

![CI](https://github.com/Rompomepome/amiral/actions/workflows/ci.yml/badge.svg)
![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.197%2B-white?style=flat&labelColor=555)
![License](https://img.shields.io/badge/license-MIT-white?style=flat&labelColor=555)
![Pattern](https://img.shields.io/badge/pattern-orchestrator%2Fworkers-white?style=flat&labelColor=555)

> [!TIP]
> Jump to [**How to Use**](#-how-to-use) for the 2-minute setup — installer or plugin, your pick.

---

## 🧠 The problem

Frontier models in Claude Code are the fastest way to burn a usage window:

- Fable + `ultracode` has been reported to consume a **full 5-hour usage window in ~7 minutes** on a codebase-wide audit.
- Fable in ultracode mode has been observed **spawning 7 parallel agents for a single small refactoring task** ([anthropics/claude-code#66867](https://github.com/anthropics/claude-code/issues/66867)).
- Every subagent inherits the main model by default. Orchestrate with a frontier model naively and **every worker bills at frontier price**.

You don't need frontier intelligence to rename 40 imports. You need it to *plan* the rename and *verify* it happened. The admiral commands the fleet; the admiral doesn't row.

## 💸 The July 7 cliff (why this matters right now)

Anthropic's [official redeployment terms](https://www.anthropic.com/news/redeploying-fable-5): Fable 5 is included in Pro/Max/Team plans (up to 50% of weekly limits) **only through July 7, 2026**. From July 8, every Fable token is billed through **usage credits at $10/$50 per MTok** — and there is no automatic fallback: if credits aren't enabled, access simply stops.

This changes the economics from *quota hygiene* to *direct money*:

- **Fable brain (credits) + cheap hands** — amiral minimizes brain tokens *by construction*; you pay frontier price only for planning, judgment and review. This is the pattern's strongest use case yet.
- **`AMIRAL_BRAIN=opus amiral`** — the pure-subscription fleet: Opus brain stays inside your plan, zero credits needed.
- Hands are cheaper than ever: Sonnet 5 launched at **$2/$10 intro pricing through Aug 31**.

Either way, the fleet sails. That's what `AMIRAL_BRAIN` is for.

## 💡 The pattern

![amiral architecture](assets/architecture.svg)

Three levers, combined:

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** — hard-forces every subagent onto a cheap model, whatever the brain decides to spawn. Highest precedence in the [resolution order](https://code.claude.com/docs/en/sub-agents).
2. **Per-agent `model:` frontmatter** — fine-grained routing: Sonnet for real implementation, Haiku for mechanical work.
3. **A memory policy (`CLAUDE.md`)** — teaches the orchestrator to delegate, to *not* fan out 7 agents on a 1-agent task, and to verify (build/typecheck/lint) before claiming "done".

## ⛵ Model-agnostic by design

The brain is **configurable, not hardcoded** — because models get suspended (Fable already was, once), renamed, and superseded:

```bash
amiral                      # brain = fable (default), hands = sonnet
AMIRAL_BRAIN=opus amiral    # same fleet, Opus brain — one env var, zero edits
AMIRAL_HANDS=claude-sonnet-5 amiral   # pin an exact worker model ID
```

The pattern outlives any single model. That's the point.

## 📦 What's inside

| Component | Location | What it does |
| --- | --- | --- |
| 🅐 **implementer** | [`agents/implementer.md`](agents/implementer.md) | Implements features against a validated plan. `model: sonnet`. Full write access. |
| 🅐 **grunt** | [`agents/grunt.md`](agents/grunt.md) | Mass mechanical work (renames, boilerplate, migrations). `model: haiku`, `effort: low`. |
| 🅐 **reviewer** | [`agents/reviewer.md`](agents/reviewer.md) | Fresh-context review right after implementation. Read-only tools, prioritized report. |
| 🏴 **corsaire** | [`agents/corsaire.md`](agents/corsaire.md) | Licensed adversary: pre-mortem attack on risky or vibe-coded features — assumes it already failed in production, works backward to every cause. Read-only, hostile, concrete. |
| 🅢 **/plan-ship** | [`skills/plan-ship/SKILL.md`](skills/plan-ship/SKILL.md) | One command: plan → delegate → verify → review → summary. Never commits without your OK. |
| 📜 **Routing policy** | [`CLAUDE.md`](CLAUDE.md) | Persistent memory: orchestrator role, anti-fan-out discipline, mandatory verification. |
| ⚡ **Fleet profiles** | [`shell/`](shell/) | `amiral`, `amiral-fine`, `amiral-ultra`, `matelot` — bash/zsh **and** PowerShell. Safe permission defaults. |
| ✅ **verify.sh template** | [`templates/verify-nextjs.sh`](templates/verify-nextjs.sh) | Machine-verifiable "done" gate (typecheck + lint + build). |
| 🔌 **Plugin manifests** | [`.claude-plugin/`](.claude-plugin/) | Install as a native Claude Code plugin — no scripts to run. |
| 📊 **Benchmark protocol** | [`BENCHMARKS.md`](BENCHMARKS.md) | Reproducible A/B/C measurement protocol + community results table. |
| 🌍 **Portable pattern** | [`PATTERN.md`](PATTERN.md) + [`ports/AGENTS.md`](ports/AGENTS.md) | The CLI-agnostic spec and the matelot discipline in the AGENTS.md standard — usable by 25+ non-Claude tools. |
| 🩺 **amiral doctor** | [`bin/amiral-doctor`](bin/amiral-doctor) | One command to check install, version, and routing config — catches the silent-fallback quota bleed. |
| 🪝 **Verification hook** | [`hooks/`](hooks/) + [docs/hooks.md](docs/hooks.md) | Opt-in `SubagentStop` gate: workers can't finish while `./verify.sh` fails. Policies ask; hooks enforce. |

This repo **dogfoods itself**: clone it, open Claude Code inside, and the routing config in `.claude/` is live (CI keeps it in sync with the canonical `agents/` and `skills/`).

## ⚡ How to Use

### Option A — Plugin (native, auto-updates)

```
/plugin marketplace add Rompomepome/amiral
/plugin install amiral@amiral-marketplace
```

Gets you the agents and `/amiral:plan-ship`. Then add the shell profiles (the plugin system doesn't manage shell rc files):

```bash
curl -fsSL https://raw.githubusercontent.com/Rompomepome/amiral/main/shell/amiral-profiles.sh -o ~/.claude/amiral-profiles.sh
echo 'source ~/.claude/amiral-profiles.sh' >> ~/.zshrc && source ~/.zshrc
```

### Option B — Installer (everything, including the global policy)

```bash
git clone https://github.com/Rompomepome/amiral.git && cd amiral
./install.sh
echo 'source ~/.claude/amiral-profiles.sh' >> ~/.zshrc && source ~/.zshrc
claude update   # Sonnet 5 needs v2.1.197+
```

**Windows (PowerShell):** run `./install.sh` from Git Bash or WSL, then add `. "$HOME\.claude\amiral-profiles.ps1"` to your `$PROFILE`.

> [!NOTE]
> Profiles ship with Claude Code's **default permission prompts** — safe by default. Want fewer prompts? Read [docs/permissions.md](docs/permissions.md) for the full speed/safety spectrum (allowlists, `acceptEdits`, and why we don't ship YOLO mode).

### The fleet

| Command | Brain | Workers | When |
| --- | --- | --- | --- |
| `amiral` | `$AMIRAL_BRAIN` @ xhigh | **forced `$AMIRAL_HANDS`** | 🏆 Daily driver. Max planning capability, capped execution cost. |
| `amiral-fine` | `$AMIRAL_BRAIN` @ xhigh | per-agent frontmatter (Sonnet/Haiku) | When you want Haiku on the grunt work. |
| `amiral-ultra` | `$AMIRAL_BRAIN` + ultracode | forced `$AMIRAL_HANDS` | Big audits **only**. Then `/effort` → `ultracode`. 🔥 Quota incinerator. |
| `matelot` | — | `$AMIRAL_HANDS` @ high | Everything that doesn't deserve the brain. The matelot discipline itself is [portable to 25+ tools](ports/AGENTS.md). |

Defaults: `AMIRAL_BRAIN=fable`, `AMIRAL_HANDS=sonnet`.

Inside a session:

```
/plan-ship add JWT refresh-token rotation to the auth middleware
```

…and the orchestrator plans, hands implementation to `implementer`, bulk edits to `grunt`, verification gates the result, and `reviewer` reads the diff with fresh eyes before you get a summary.

Shipping something risky, security-sensitive, or vibe-coded? Send the corsaire before the users find it:

```
use the corsaire agent on the auth changes before we ship
```

The reviewer checks the work. The corsaire assumes it already failed in production and hunts the cause. If you can't review code yourself, the corsaire is your pre-mortem.

## ✅ Verify the routing actually works

**Run `amiral-doctor` first** — it checks the install and flags the risky configs. Then do this once. If `sonnet` isn't resolved as a subagent model on your version, workers silently fall back to the main model — i.e. the expensive brain — and your quota bleeds anyway.

1. Launch `amiral` in a project.
2. Ask for something that delegates ("implement X using the implementer agent").
3. Check `/agents` or the transcript: workers must show **Sonnet**, not the brain.
4. If not: `export AMIRAL_HANDS=claude-sonnet-5` (full model ID).

## 🧮 Why this saves real money

- Fable 5 is priced at **$10 / MTok input, $50 / MTok output** — the execution phase of a feature (dozens of file writes, test runs, retries) is where the tokens go.
- Subagent-heavy workflows can consume **~7× the tokens** of a single-thread session, since each worker holds its own context window.
- Routing workers to Sonnet/Haiku means the token-heavy phase happens at a fraction of the cost, while the brain only pays for what it's uniquely good at: planning, decomposition, judgment, final review.

Full math and sources: [docs/quota-math.md](docs/quota-math.md). Reproducible measurements: [BENCHMARKS.md](BENCHMARKS.md).

## 🌍 Beyond Claude Code

The **implementation** here is Claude Code (native routing primitives). The **pattern and the discipline are portable** — and partly predate this repo (Aider's architect/editor mode proved the two-tier split years ago):

- [`PATTERN.md`](PATTERN.md) — the CLI-agnostic spec, with an implementation map: Aider (native `--architect` + `--editor-model`), OpenCode and Roo Code (per-agent/mode models), Codex CLI and Gemini CLI (two-session manual split), and the degraded-but-real protocol when your tool has no routing at all: *you* are the amiral.
- [`ports/AGENTS.md`](ports/AGENTS.md) — **the matelot discipline**: the worker policy in the [AGENTS.md open standard](https://agents.md) (Linux Foundation, read by 25+ tools). The amiral is Claude Code-specific; the matelot is universal. Copy one file to your repo root and any of Codex, Aider, OpenCode, Cursor, Gemini CLI, Copilot, Zed or Warp inherits the discipline.

One repo, three layers: universal pattern → portable discipline → Claude Code reference implementation.

## 🪶 Not a framework

The 2026 orchestration landscape is crowded with platforms — the leading one ships **250,000+ lines** of engine and is **API-only, blocked on Pro/Max subscriptions**. amiral takes the opposite bet:

- **6 markdown files** and native Claude Code primitives. Nothing to adopt, no engine to break on the next release.
- **Works on your subscription.** No API key required — it's just configuration. (With a Fable brain after July 7, only the *brain* needs usage credits — the whole point is minimizing those tokens. Or run `AMIRAL_BRAIN=opus` and stay fully inside your plan.)
- When you truly need swarm topologies and consensus protocols, graduate to a framework — and take the amiral policy with you.

Full honest comparison (Ruflo, Code Kit, Octopus, Maestro, opusplan): [docs/landscape.md](docs/landscape.md).

## 🆚 vs. the alternatives

| Approach | What it optimizes | Trade-off |
| --- | --- | --- |
| **amiral** | Brain plans/verifies, workers execute cheap | You verify routing once; slight orchestration overhead |
| `opusplan` (built-in) | Opus in plan mode, Sonnet execution | Only plan-mode handoff; no Fable, no worker specialization, no policy |
| Naive Fable + ultracode | Raw capability, zero setup | Observed 7-agent fan-outs; window gone in minutes |
| Pure Sonnet | Cost | No frontier-grade planning/judgment on hard tasks |
| Manual `/model` switching | Control | You are the router; forgets happen, quota bleeds |

## 🛡️ Design principles

1. **The policy is model-agnostic.** Delegation discipline + verification gates hold even in `matelot` mode. Model choice lives in the profiles, not the policy.
2. **Anti-fan-out is explicit.** Parallel workers capped at 3–4; "a small refactor = 1 agent, not 7."
3. **"Done" means verified.** Build + typecheck + lint (+ tests when present) gate every completion claim. UI changes require render verification.
4. **Never destructive.** Installer backs up `CLAUDE.md`, imports via `@`-reference, safe to re-run. CI proves it.
5. **No auto-commit.** The orchestrator never commits or pushes without an explicit human OK.
6. **Safe by default, fast by opt-in.** No permission-bypass flag shipped — CI enforces it. The spectrum is documented so *you* choose knowingly.
7. **Survive the models.** Brains get suspended and renamed; `AMIRAL_BRAIN`/`AMIRAL_HANDS` mean the fleet sails on.

## 🗺️ Roadmap

- [x] Plugin packaging (marketplace install)
- [x] Windows (PowerShell) profiles
- [x] `verify.sh` template — Next.js; Python & Rust welcome via PR
- [x] Benchmark protocol
- [ ] Seeded benchmark results (maintainer's own numbers — in progress)
- [x] Optional `SubagentStop` hook: hard verification gate on worker results
- [x] Portable pattern spec + AGENTS.md port (works beyond Claude Code)
- [ ] Ralph-loop integration guide: lean routing inside autonomous loops
- [ ] Community ports/ (OpenCode agent config, Roo mode set, Codex two-session script) — PRs open
- [x] `amiral doctor`: one command to check install, version, and routing config

## 🤝 Contributing

The most valuable PR is a **benchmark row** ([BENCHMARKS.md](BENCHMARKS.md) protocol, "Quota report" issue template). Also welcome: worker agents, stack policies, fixes tracking Claude Code releases. See [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License

[MIT](LICENSE)

---

**Disclaimer:** community project, not affiliated with or endorsed by Anthropic. "Claude", "Claude Code" and model names are Anthropic's.

*Part of a small fleet of tools: ⛵ Voile (sovereign AI deployment) · 🗼 Phare (federated agent intelligence) · ⚓ amiral (this repo). Inspired by the structure of [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice).*
