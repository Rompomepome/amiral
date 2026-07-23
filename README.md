# ⚓ amiral

<img src="assets/amiral-hero.jpg" width="230" align="right" alt="amiral — the old sea dog who commands the fleet"/>

**The admiral doesn't row.** Orchestrator/worker model routing for Claude Code: an expensive brain (Fable 5, Opus) plans, delegates and verifies — cheap hands (Sonnet, Haiku) do the token-heavy execution.

*Français ? Lisez le [README.fr.md](README.fr.md).*

![CI](https://github.com/Rompomepome/amiral/actions/workflows/ci.yml/badge.svg)
![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.197%2B-white?style=flat&labelColor=555)
![License](https://img.shields.io/badge/license-MIT-white?style=flat&labelColor=555)
![Pattern](https://img.shields.io/badge/pattern-orchestrator%2Fworkers-white?style=flat&labelColor=555)

**[🚀 Get started](#-try-it-in-5-minutes) · [🧭 Two shapes](#-two-shapes-both-included) · [🧮 Savings](#-why-this-saves-real-money) · [📊 Benchmarks](BENCHMARKS.md) · [🌍 Ports](ports/) · [🧠 How it works](docs/how-it-works.md) · [🇫🇷 Français](README.fr.md)**

## ⚡ Main takeaways

- **One word.** Type `amiral`, talk normally. It routes every task itself.
- **Works inside the plan you already pay for.** No API key, nothing to configure.
- **Frontier plans, cheap models execute.** Measured here: **~$880 saved over six weeks** (baseline Opus, ~70 routed tasks, observational — reproduce it: `amiral-butin backfill --all && amiral-butin`), consistent with Anthropic's own ~2.5x cheaper / ~3x faster reference run.
- **Two shapes included:** orchestrator and advisor — the exact shapes from Anthropic's evals.
- **5 specialized agents**, including an adversarial security pass (the corsaire).
- **Portable** to Codex, OpenCode, Aider and 25+ tools via the open AGENTS.md standard.
- **Provable.** Opt-in git trailers (route, diff-digest) — ship AI-written code you can defend.
- **No telemetry, ever.** Nothing hosted, nothing phones home.

> [!TIP]
> Jump to [**How to Use**](#-how-to-use) for the 2-minute setup — installer or plugin, your pick.

---

## ⚓ How you use it: one word

Install once, then type **`amiral`**. The very first time, it asks your
plan once (Pro / Max / credits) and remembers it — so it always uses the
best brain included in *your* plan. After that, just talk.

```
amiral
# first run only:  Which Claude plan are you on?  [1 Pro · 2 Max · 3 credits]
> ajoute la validation email au formulaire d'inscription
```

You never pick a model, an effort level, or an agent. The admiral reads each request, judges its complexity, and routes it: trivial edits it does itself, mechanical work goes to a cheap fast model, real features go to a mid model that implements against a plan, risky changes get an adversarial security pass, and nothing is "done" until it verifies (build/lint/tests). You give the cap a heading; the admiral commands the fleet. **No flags to memorize. No config to write.**

**Works on the plan you already have.** The default brain is Opus —
included on Max, and on Pro Claude Code serves Sonnet within your plan,
so there's nothing to pay and nothing to configure. Workers run on
Sonnet (~1/5 the frontier cost). On a Pro plan and want the lightest
footprint? `amiral-solo` runs an all-Sonnet fleet. Want the premium
planning brain? `AMIRAL_BRAIN=fable amiral` — included on Max and Team
Premium (up to 50% of weekly limits); metered via usage credits ($10/$50
per MTok) on Pro and Team Standard.

(Power users: optional variants and env overrides exist, but you never need them to start.)

### One real task, start to finish

Not a hypothetical — a task from this repo's own build, measured in
`~/.amiral/butin.jsonl` (baseline Opus, tokens priced from the real
transcript):

```
request   "Implement the butin statusline (producer/cache/renderer)."
route     real feature → implementer agent, model: sonnet
          (the admiral planned + verified; it did not write the bulk)
receipt   real $28.70  ·  same tokens at the Opus baseline $143.49
          → saved $114.79 on one task
```

The worker did the token-heavy execution at ~1/5 the frontier rate; the
brain paid only for planning and review. Four more traces — including one
where the admiral **refused to delegate** because the hand-off would cost
more than the edit — are in [`examples/`](examples/). This is
*observational* (what was actually spent vs the same tokens at baseline),
not an A/B trial; reproduce your own with `amiral-butin backfill --all &&
amiral-butin`.

## 🧠 The problem

Frontier models in Claude Code are the fastest way to burn a usage window:

- Fable + `ultracode` has been reported to consume a **full 5-hour usage window in ~7 minutes** on a codebase-wide audit.
- Fable in ultracode mode has been observed **spawning 7 parallel agents for a single small refactoring task** ([anthropics/claude-code#66867](https://github.com/anthropics/claude-code/issues/66867)).
- Every subagent inherits the main model by default. Orchestrate with a frontier model naively and **every worker bills at frontier price**.

You don't need frontier intelligence to rename 40 imports. You need it to *plan* the rename and *verify* it happened. The admiral commands the fleet; the admiral doesn't row.

## 💸 The Fable cliff (what changed since July 12)

Anthropic's [official redeployment terms](https://www.anthropic.com/news/redeploying-fable-5): Fable 5 was included in Pro/Max/Team plans (up to 50% of weekly limits) **only through July 11, 2026** (Anthropic extended the original July 7 date). On July 12 every Fable token moved to **usage credits at $10/$50 per MTok** — then on July 20 access split by plan: **Max and Team Premium keep Fable included** (up to 50% of weekly limits, permanent), while **Pro and Team Standard stay metered** via usage credits ($10/$50 per MTok, after a one-time $100 credit). On the metered plans there is still no automatic fallback: if credits aren't enabled, access simply stops.

This changes the economics from *quota hygiene* to *direct money*:

- **Default = Opus brain + Sonnet hands** — fully inside your subscription (Max includes Opus; Pro serves Sonnet). No credits, no config. This is what `amiral` gives you out of the box.
- **`AMIRAL_BRAIN=fable amiral`** — opt-in premium planning brain. On Max/Team Premium the Fable brain runs inside your included 50%; on Pro/Team Standard, amiral minimizes brain tokens *by construction*, so you pay the metered frontier rate only for planning/judgment/review, never for bulk execution.
- **`amiral-solo`** — all-Sonnet, the lightest footprint on a Pro plan.
- Hands are cheaper than ever: Sonnet 5 launched at **$2/$10 intro pricing through Aug 31**.

Either way, the fleet sails. That's what `AMIRAL_BRAIN` is for.

## ✅ Anthropic's own numbers

This isn't a hunch. Anthropic published a cookbook on exactly this shape
(a frontier model plans and delegates, cheaper models execute) called
"plan big, execute small". Their reference run puts the team at **~$1.61
vs ~$4 for all-frontier: roughly 2.5x cheaper and about 3x faster, with
80%+ of tokens billed at the cheaper worker rate.** amiral is that shape,
packaged as one command.

*Source: Anthropic's [claude-cookbooks](https://github.com/anthropics/claude-cookbooks), "plan big, execute small". Treat any published figure as a reference point, not a guarantee, and run your own with [BENCHMARKS.md](BENCHMARKS.md).*

## 🧭 Two shapes, both included

Same idea, two ways to wire it:

- **Orchestrator** (`amiral`) — the expensive brain plans, splits the
  work, and fans out to cheap workers. Best when a task breaks into
  parallel pieces. This is the default.
- **Advisor** (`amiral-advisor`) — you run on the *cheap* model the whole
  time and consult the expensive brain (the `advisor` agent) only for
  hard calls: reviewing a plan, challenging an architecture, breaking a
  tie. Best for a long single-threaded task that occasionally needs a
  frontier opinion. Most tokens stay at the worker rate.

Want the exact shape Anthropic benchmarked — **Sonnet executor + Fable
advisor**? Pick "credits" in `amiral-setup` (or re-run it): the setup
pins the advisor agent to your brain, so `amiral-advisor` gives you
Sonnet doing the work and Fable making the hard calls. Same mechanics
with Opus on a Max plan, zero credits.

## ⚓ The fleet of ships

amiral is not a framework — it's a fleet of small, separately boardable
ships. Board only what you need; read any of them in five minutes.

- **amiral** (route) — the 7-file core: the brain plans, cheap hands
  execute, nothing ships until the gate is green.
- **butin** (measure) — `amiral-butin`: counterfactual NET savings from
  your own routed tasks. Coverage shown, escalations and brain premium
  deducted, cache priced as cache, 100% local. First run: `amiral-butin
  init` detects your baseline (and refuses to strawman a frontier one
  without your confirmation). Baseline or mode changed mid-session (new
  plan, new default model)? `amiral-butin config` sets it directly, no
  detection — changes apply to future events only, history keeps the
  baseline it was priced with. Wire the collector once: [docs/butin.md](docs/butin.md).
  The headline NET only ever credits agents amiral actually ships and
  routes (`agents/*.md`); a subagent Claude Code spawns on its own (or
  any custom agent you define) is measured too but shown on its own
  clearly-labelled line, never mixed into the amiral figure. The brain
  keeps its own premium accounting, separate from both.
- **journal de bord** (prove) — `amiral-journal enable`: opt-in git
  trailers per repo — `Amiral-Route` and `Amiral-Diff-Digest` (a
  recomputable digest of verify.sh's bytes + the commit's diff — proves
  what was present, not what was run). Squash-merge
  team? `amiral-journal note` attaches the same proof as a git note.
  `FLEET.md` makes the routing policy part of the repo itself —
  AI-policy-as-code, changed by PR ([template](templates/FLEET.md)).
- **pavillon** — `amiral-journal flag` prints a shareable badge from
  your butin data, and refuses to generate under 20 measured tasks.
  The design encodes the honesty.

Route smart, verify everything, prove it in git — the accountability
layer for AI-assisted code, with nothing hosted and nothing phoning home.
*(butin & journal are POSIX shell for now; PowerShell parity is tracked
on the roadmap.)*

## 💡 The pattern

Three levers, combined:

1. **`CLAUDE_CODE_SUBAGENT_MODEL`** — hard-forces every subagent onto a cheap model, whatever the brain decides to spawn. Highest precedence in the [resolution order](https://code.claude.com/docs/en/sub-agents).
2. **Per-agent `model:` frontmatter** — fine-grained routing: Sonnet for real implementation, Haiku for mechanical work.
3. **A memory policy (`CLAUDE.md`)** — teaches the orchestrator to delegate, to *not* fan out 7 agents on a 1-agent task, and to verify (build/typecheck/lint) before claiming "done".

## ⛵ Model-agnostic by design

The brain is **configurable, not hardcoded** — because models get suspended (Fable already was, once), renamed, and superseded:

```bash
amiral                      # brain = opus (default), hands = sonnet
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
| 🧭 **advisor** | [`agents/advisor.md`](agents/advisor.md) | The expensive brain, consulted on demand: a cheap executor calls it for hard judgment calls (plan review, architecture, tradeoffs) then takes back control. Powers `amiral-advisor`. |
| 💰 **butin** | [`bin/amiral-butin`](bin/amiral-butin) + [`lib/butin/`](lib/butin/) | Proves amiral's ROI from your own routed tasks: net counterfactual savings (escalations and brain premium deducted), coverage shown, 100% local. Wire once: [docs/butin.md](docs/butin.md). POSIX-only for now. |
| 🧾 **journal** | [`bin/amiral-journal`](bin/amiral-journal) | Provenance for AI-assisted commits: opt-in git trailers — `Amiral-Route` and `Amiral-Diff-Digest` (a recomputable sha256 of verify.sh's bytes + the commit's diff — proves what was present, not what was run). `note` mode survives squash-merges. `flag` prints the pavillon badge (refuses under 20 measured tasks). |
| 📟 **statusline** | [`bin/amiral-statusline`](bin/amiral-statusline) | Opt-in Claude Code status-line integration: shows your net butin savings live (producer/cache/renderer), 100% local. `amiral statusline install`. |
| 🗺️ **FLEET.md** | [`templates/FLEET.md`](templates/FLEET.md) | AI-policy-as-code: commit the fleet policy of THIS repo; amiral reads it and it overrides personal defaults. Changed by PR, like code. |
| 🏴 **corsaire** | [`agents/corsaire.md`](agents/corsaire.md) | Licensed adversary: pre-mortem attack on risky or vibe-coded features — assumes it already failed in production, works backward to every cause. Read-only, hostile, concrete. |
| 🅢 **/plan-ship** | [`skills/plan-ship/SKILL.md`](skills/plan-ship/SKILL.md) | One command: plan → delegate → verify → review → summary. Never commits without your OK. |
| 📜 **Routing policy** | [`CLAUDE.md`](CLAUDE.md) | Persistent memory: orchestrator role, anti-fan-out discipline, mandatory verification. |
| ⚡ **Fleet profiles** | [`shell/`](shell/) | `amiral`, `amiral-fine`, `amiral-ultra`, `matelot` — bash/zsh **and** PowerShell. Safe permission defaults. |
| ✅ **verify.sh template** | [`templates/verify-nextjs.sh`](templates/verify-nextjs.sh) | Machine-verifiable "done" gate (typecheck + lint + build). |
| 🔌 **Plugin manifests** | [`.claude-plugin/`](.claude-plugin/) | Install as a native Claude Code plugin — gets you the 5 agents + `/amiral:plan-ship`, no scripts to run. Does NOT install butin, journal, statusline, doctor, backfill, the shell profiles, or the global routing policy — those need `./install.sh`. |
| 📊 **Benchmark protocol** | [`BENCHMARKS.md`](BENCHMARKS.md) | Reproducible A/B/C measurement protocol + community results table. |
| 🌍 **Portable pattern** | [`PATTERN.md`](PATTERN.md) + [`ports/AGENTS.md`](ports/AGENTS.md) | The CLI-agnostic spec and the matelot discipline in the AGENTS.md standard — usable by 25+ non-Claude tools. |
| 🩺 **amiral doctor** | [`bin/amiral-doctor`](bin/amiral-doctor) | One command to check install, version, and routing config — catches the silent-fallback quota bleed. |
| 🔐 **amiral-trust** | [`bin/amiral-trust`](bin/amiral-trust) | Per-repo, opt-in trust for the verification hook: the checksum pins `verify.sh`'s own bytes + the repo's identity, and re-requires trust on any edit. Scope limit: anything `verify.sh` sources or execs runs unfingerprinted — trusting a repo means trusting its whole build. [docs/hooks.md](docs/hooks.md). |
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

### Option C — npm

```bash
npm i -g @rompomepome/amiral
```

Note the scoped name — `@rompomepome/amiral`, **not** `amiral` (that's a different, unrelated package on npm).

What this gives you: the `amiral-install` and `amiral-uninstall` commands on your PATH. What it does **not** do: it does **not** touch `~/.claude`, your shell rc, or `settings.json` on install — there is no `postinstall` script, by design (same honest accounting as the Plugin-manifests row above: this states plainly what it does and does not give you).

Then run the installer explicitly (same effect as `./install.sh`):

```bash
amiral-install
echo 'source ~/.claude/amiral-profiles.sh' >> ~/.zshrc && source ~/.zshrc
```

Why the two-step instead of one: a package that rewrites your agent config the moment you run `npm i` is exactly what security teams block, and it contradicts "nothing surprising, nothing hosted." Config changes to your agent setup stay an explicit action you take, never a silent side effect of a package manager.

**Windows:** `npm i -g` works, but `amiral-install` is a bash script — run it from **Git Bash or WSL** (native PowerShell has no `bash`), then add `. "$HOME\.claude\amiral-profiles.ps1"` to your `$PROFILE`. Same requirement as Option B.

### The fleet

| Command | Brain | Workers | When |
| --- | --- | --- | --- |
| `amiral` | `$AMIRAL_BRAIN` @ xhigh | **forced `$AMIRAL_HANDS`** | 🏆 Daily driver. Max planning capability, capped execution cost. |
| `amiral-fine` | `$AMIRAL_BRAIN` @ xhigh | per-agent frontmatter (Sonnet/Haiku) | When you want Haiku on the grunt work. |
| `amiral-ultra` | `$AMIRAL_BRAIN` + ultracode | forced `$AMIRAL_HANDS` | Big audits **only**. Then `/effort` → `ultracode`. 🔥 Quota incinerator. |
| `matelot` | — | `$AMIRAL_HANDS` @ high | Everything that doesn't deserve the brain. The matelot discipline itself is [portable to 25+ tools](ports/AGENTS.md). |

Defaults: `AMIRAL_BRAIN=opus`, `AMIRAL_HANDS=sonnet` (only `amiral-ultra` falls back to Fable).

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

## 🚀 Try it in 5 minutes

```bash
git clone https://github.com/Rompomepome/amiral.git && cd amiral && ./install.sh
source ~/.claude/amiral-profiles.sh
amiral-doctor                       # fleet health check
cd ~/your-nextjs-project
cp ~/dev/amiral/templates/verify-nextjs.sh ./verify.sh   # your "done" gate
amiral                              # launch the fleet
```

Then, inside the session:

```
/plan-ship add input validation to the signup form
```

Watch `/agents` while it runs: the brain plans, workers execute on Sonnet, the gate verifies, the reviewer reads the diff. That run is also your first [benchmark data point](BENCHMARKS.md).

## ✅ Verify the routing actually works

**Run `amiral-doctor` first** — it checks the install and flags the risky configs. Then do this once. If `sonnet` isn't resolved as a subagent model on your version, workers silently fall back to the main model — i.e. the expensive brain — and your quota bleeds anyway.

1. Launch `amiral` in a project.
2. Ask for something that delegates ("implement X using the implementer agent").
3. Check `/agents` or the transcript: workers must show **Sonnet**, not the brain.
4. If not: `export AMIRAL_HANDS=claude-sonnet-5` (full model ID).

## 🧮 Why this saves real money

Run the numbers for your own setup:

```bash
amiral-savings --tokens 5 --brain fable --hands sonnet --plan 20
# -> All-frontier: $250 · amiral: $110 · save $140 (56% cheaper, 2.3x)
```


- Fable 5 is priced at **$10 / MTok input, $50 / MTok output** — the execution phase of a feature (dozens of file writes, test runs, retries) is where the tokens go.
- Subagent-heavy workflows can consume **~7× the tokens** of a single-thread session, since each worker holds its own context window.
- Routing workers to Sonnet/Haiku means the token-heavy phase happens at a fraction of the cost, while the brain only pays for what it's uniquely good at: planning, decomposition, judgment, final review.

Full math and sources: [docs/quota-math.md](docs/quota-math.md). Reproducible measurements: [BENCHMARKS.md](BENCHMARKS.md).

## 🧾 Prove it (the journal de bord)

Ship AI-written code you can defend. `amiral-journal enable` adds
provenance trailers to every commit of the repo (opt-in, per repo,
removable anytime):

```
Amiral-Route: implementer=claude-sonnet-4-6 grunt=claude-haiku-4-5
Amiral-Diff-Digest: sha256:8dca5e258291f50c
```

The digest is a recomputable hash of verify.sh's bytes + the commit's
diff — it proves what was present, not what was run. Squash-merge
teams: `amiral-journal note` attaches the same block as a git note
(ref `amiral`), which survives history rewrites. Cost trailer is a
separate opt-in (`enable --with-cost`) with a public-remote warning.
No registry, no server: the audit trail lives in your git.

## 🌍 Beyond Claude Code

The **implementation** here is Claude Code (native routing primitives). The **pattern and the discipline are portable** — and partly predate this repo (Aider's architect/editor mode proved the two-tier split years ago):

- [`PATTERN.md`](PATTERN.md) — the CLI-agnostic spec, with an implementation map: Aider (native `--architect` + `--editor-model`), OpenCode and Roo Code (per-agent/mode models), Codex CLI and Gemini CLI (two-session manual split), and the degraded-but-real protocol when your tool has no routing at all: *you* are the amiral.
- [`ports/AGENTS.md`](ports/AGENTS.md) — **the matelot discipline**: the worker policy in the [AGENTS.md open standard](https://agents.md) (Linux Foundation, read by 25+ tools). The amiral is Claude Code-specific; the matelot is universal. Copy one file to your repo root and any of Codex, Aider, OpenCode, Cursor, Gemini CLI, Copilot, Zed or Warp inherits the discipline.

One repo, three layers: universal pattern → portable discipline → Claude Code reference implementation.

**"Can the admiral call GPT or Gemini?"** Not from inside Claude Code — subagents run on Anthropic models, by design. Routing to other vendors means a proxy/gateway you'd host and maintain (that's a framework, not 7 files). The clean answer is the portable layer above: run the amiral *pattern* on a tool that already speaks many LLMs — OpenCode (75+ providers), Aider, Codex — via [`ports/AGENTS.md`](ports/AGENTS.md). amiral stays small and native; multi-vendor lives where it belongs.

## 🪶 Not a framework

The 2026 orchestration landscape is crowded with platforms — the leading one ships **250,000+ lines** of engine and is **API-only, blocked on Pro/Max subscriptions**. amiral takes the opposite bet:

- **7 markdown files** and native Claude Code primitives. Nothing to adopt, no engine to break on the next release.
- **Works on your subscription.** No API key required — it's just configuration. (Now that Fable is metered on Pro and Team Standard — Max and Team Premium keep it included — only the *brain* would need usage credits, and the whole point is minimizing those tokens. Or run `AMIRAL_BRAIN=opus` and stay fully inside your plan.)
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

**No telemetry, ever.** amiral never phones home — there is no endpoint to phone. Community benchmarks come from `amiral-report`: users package their own numbers locally and post them as public GitHub issues themselves. Consent by design, data in the open where it helps everyone.

## 🗺️ Roadmap

- [x] Plugin packaging (marketplace install)
- [x] Windows (PowerShell) profiles
- [x] `verify.sh` template — Next.js; Python & Rust welcome via PR
- [x] Benchmark protocol + [results table](BENCHMARKS.md) (Anthropic reference numbers + observed data; community A/B rows land via `amiral-report` in [#3](https://github.com/Rompomepome/amiral/issues/3))
- [x] Optional `SubagentStop` hook: hard verification gate on worker results
- [x] Portable pattern spec + AGENTS.md port (works beyond Claude Code)
- [x] `amiral-savings` local cost estimator · Codex + OpenCode ports · [autonomous-loop guide](docs/autonomous-loop.md)
- [x] `amiral doctor` + `amiral-report` (share your numbers without telemetry)
- [ ] `amiral-auto-effort`: per-task effort selection — vote/discuss in [#1](https://github.com/Rompomepome/amiral/issues/1)
- [ ] More ports: Aider next — vote in [#2](https://github.com/Rompomepome/amiral/issues/2); Roo mode set, Codex two-session script welcome via PR

## 🤝 Contributing

The most valuable PR is a **benchmark row** — run [`amiral-report`](bin/amiral-report) after a benchmark, it formats your numbers and prefills the issue ([protocol](BENCHMARKS.md), collected in [#3](https://github.com/Rompomepome/amiral/issues/3)). Also welcome: worker agents, stack policies, fixes tracking Claude Code releases. See [CONTRIBUTING.md](CONTRIBUTING.md). Ideas and feedback from the community are logged in [IDEAS.md](IDEAS.md).

## 📄 License

[MIT](LICENSE)

---

**Disclaimer:** community project, not affiliated with or endorsed by Anthropic. "Claude", "Claude Code" and model names are Anthropic's.

*Part of a small fleet of tools: ⛵ Voile (sovereign AI deployment) · 🗼 Phare (federated agent intelligence) · ⚓ amiral (this repo). Inspired by the structure of [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice).*
