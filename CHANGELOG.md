# Changelog

## v0.6.5 - 2026-07-07
Documentation cleanup pass (post-launch tidy):
- Fixed install.sh final message: it still said AMIRAL_BRAIN "default
  fable" — the default has been Opus since v0.6.1. Now reads "default
  opus" so nobody panics about the July 7 metering.
- Removed the obsolete geometric assets (architecture.svg,
  admiral-character.svg) replaced by the hero illustration; dropped the
  old diagram image from the README.
- quota-math: Opus stated as the default brain (not an "alternative").
- how-it-works: documents the first-run setup (amiral-setup) and the
  Opus-default behavior.
- Verified: no broken internal links, docs aligned with current
  behavior (one-word usage, Opus default, first-run setup, 4 agents).


## v0.6.4 - 2026-07-07
- Added the amiral hero illustration (assets/amiral-hero.png) to the top
  of the README — an original ligne-claire old-sea-dog admiral in a
  brass porthole, matching the maritime brand.
- Demo GIF finalized (assets/amiral-demo.gif, ~1MB): one word, the
  admiral triaging and fixing a task inline.


## v0.6.3 - 2026-07-06
- Added a terminal demo GIF (assets/amiral-demo.gif) to the top of the
  README: one word, then the admiral triaging a trivial fix inline and
  delegating a real feature, verified end to end. Recorded with
  asciinema, rendered with agg.


## v0.6.2 - 2026-07-06
- **First-run plan setup, asked once.** The first `amiral` asks which
  plan you're on (Pro/Max/credits) and pins the best in-plan brain to
  ~/.claude/amiral.env — then never asks again. New `bin/amiral-setup`
  (re-runnable), loaded by the shell profiles; the installer runs it and
  copies it. Keeps the one-word experience while making the model choice
  explicit up front, as requested.
- README documents the first-run prompt, and answers "can the admiral
  call GPT/Gemini?" honestly: not natively (subagents are Anthropic
  models); use the portable AGENTS.md layer on a multi-provider tool
  (OpenCode/Aider/Codex) instead of bolting a gateway onto amiral.
- doctor shows whether first-run setup has been done.


## v0.6.1 - 2026-07-06
- **Default brain is now Opus, not Fable.** Most users are on Pro
  (Sonnet) or Max (Opus); the free tier has no Claude Code, and Fable
  is metered on subscriptions after July 7. The default now works
  inside the plans people actually have: brain=opus (included on Max;
  Pro serves Sonnet within-plan), hands=sonnet. No credits, no config.
- New `amiral-solo`: all-Sonnet fleet, lightest footprint on a Pro plan.
- Fable is now an explicit opt-in premium planning brain
  (`AMIRAL_BRAIN=fable amiral`), not the default. amiral-ultra still
  uses the frontier brain by default (it's the premium-audit tool).
- doctor and README reframed around "works on the plan you already have".


## v0.6.0 - 2026-07-06
- One-word usage. `amiral` is now the single command you need: type it
  and just talk. The policy makes the admiral triage every task by
  complexity and route it itself - trivial work done inline, mechanical
  work to Haiku, real features to Sonnet (implementer), risky changes to
  the corsaire, always verified before "done". Users never pick a model,
  effort, or agent.
- Variants (amiral-fine, amiral-ultra, matelot) and /plan-ship are now
  explicitly optional power-user tools, not the default path.
- README leads with zero-config "one word" usage.
- Note: model choice at launch is inherently a shell concern, so one
  embark word is the floor; after that the admiral handles everything.


## v0.5.4 — 2026-07-06
Security & robustness pass — findings from running our own corsaire
agent against the repo (dogfooding the adversary):
- **CRITICAL fix**: the SubagentStop hook would run ANY repo's root
  ./verify.sh with full privileges (booby-trap vector). Now it refuses
  untrusted verify.sh entirely; opt in per-repo via `amiral-trust`
  (checksum-pinned = tamper-evident) and execution is wrapped in a 300s
  timeout. New `bin/amiral-trust`; CI proves untrusted scripts don't run.
- install.sh now backs up any pre-existing agent/skill before
  overwriting (timestamped .amiral-bak), matching the CLAUDE.md behavior.
- uninstall.sh: only removes our own skill file then rmdir-if-empty
  (no more nuking a shared skills dir); no longer claims to remove a
  CLAUDE.md import that wasn't there; flags leftover backups.
- install.sh: rc-append is now grep-guarded (truly idempotent).
- doctor reports hook-trust status for the current repo.
- Noted `amiral-auto-effort` on the roadmap (per-task effort selection),
  pending Anthropic's own `auto` effort maturing.


## v0.5.3 — 2026-07-06
- Fix verify-nextjs.sh (found during real dogfooding): it ran a global
  `npx tsc` that fails when TypeScript isn't globally installed. Now it
  prefers the project's own package.json scripts (typecheck/lint/build),
  falls back to the LOCAL tsc via `npx --no-install`, and skips
  gracefully with a message when a step is absent. Adds yarn detection.


## v0.5.2 — 2026-07-06
- **Wired the corsaire into the system** (it was decorative): the
  routing policy now sends security-sensitive / high-risk / vibe-coded
  changes to the corsaire, and /plan-ship runs it in the review step
  for those surfaces. PATTERN.md gains the adversarial-pass principle.
- Policy and plan-ship now prefer `./verify.sh` when present (aligns
  the Claude Code policy with the portable discipline).
- README: mascot on the repo page + "Try it in 5 minutes" copy-paste
  quickstart ending on your first benchmark data point.
- SECURITY.md: private disclosure channel, scope notes.
- doctor: checks the current project for a verify.sh done gate.


## v0.5.1 — 2026-07-03
- Post-corsaire consistency pass: marketplace description, how-it-works
  and the doctor now count 4 agents (the doctor had escaped the sweep —
  no .sh extension). Note: the "6 markdown files" claim is now exactly
  true (policy + 4 agents + skill).
- Social preview: proper French accents and typographic apostrophes
  (modèle, découpe, exécutent, VÉRIF).


## v0.5.0 — 2026-07-03
- **New fleet member: the corsaire** — licensed adversary. Pre-mortem
  (Klein) applied to code: assumes the feature already failed in
  production, works backward through 6 attack surfaces (inputs, state,
  auth, data, edges, dependencies). Severity x likelihood ranking,
  concrete mechanisms only, plain-language verdict. Built for risky
  and vibe-coded changes; read-only. The reviewer checks the work;
  the corsaire hunts the future failure.
- Redrawn admiral character: organic ligne-claire style (3/4 view,
  wind-blown beard, tilted cap, squinting eye) replacing the geometric
  mascot. Original design.


## v0.4.4 — 2026-07-03
- New social preview: original old-sea-dog admiral character (flat
  comic style, porthole frame) + a clear 3-step schema in Montserrat.
  Original design — not derived from any copyrighted character.
- assets/admiral-character.svg: the character source, reusable for
  README, posts, stickers.


## v0.4.3 — 2026-07-03
- Coherence sweep: purged 5 stale profile names (fable-fine,
  sonnet-fast) from quota-math, how-it-works and the quota-report
  template, including one leftover env-var mention contradicting the
  v0.4.2 effort fix. Automated link check: all internal links valid.
- assets/social-preview.png (1280x640): launch asset for GitHub social
  preview and link shares.


## v0.4.2 — 2026-07-03
- **Fix a silent token leak in our own profiles**: CLAUDE_CODE_EFFORT_LEVEL
  takes precedence over agent frontmatter, forcing every worker
  (including the low-effort grunt) to think at xhigh. Profiles now use
  the `--effort` flag (session level, overridable by frontmatter):
  brain at xhigh, grunt at low, as designed. Fixed in bash and
  PowerShell profiles, documented in how-it-works.
- amiral-ultra: caution note — verify in /agents that dynamic-workflow
  workers honor the hands model before trusting a big run.


## v0.4.1 — 2026-07-03
- **July 7 cliff documented** (Anthropic official terms: Fable included
  in subscriptions only through July 7; usage-credits only after, no
  auto-fallback). README section, doctor warning, quota-math update.
- Reframed economics: metered Fable brain + cheap hands is the
  pattern's strongest case; `AMIRAL_BRAIN=opus` is the pure-subscription
  fleet.
- Nuanced the "works on your subscription" claim accordingly.


## v0.4.0 — 2026-07-03
- **Three-layer split**: universal pattern -> portable discipline ->
  Claude Code reference implementation.
- `PATTERN.md`: CLI-agnostic spec with honest prior art (Aider
  architect/editor, Roo modes, opusplan) and an implementation map per
  CLI, including the "you are the amiral" degraded protocol.
- `ports/AGENTS.md`: the **matelot discipline** in the AGENTS.md open
  standard (Linux Foundation) — one file, readable by 25+ tools (Codex,
  Aider, OpenCode, Cursor, Gemini CLI, Copilot, Zed, Warp...). The
  amiral is Claude Code-specific; the matelot is universal.
- `ports/README.md`: ports philosophy — we document ports, we do not
  maintain runtimes for other CLIs.


## v0.3.0 — 2026-07-03
- `amiral doctor`: automated fleet health check (install, version,
  routing config, silent-fallback detection guidance).
- Optional `SubagentStop` verification hook: workers cannot finish while
  `./verify.sh` fails. Policies ask; hooks enforce. Opt-in, documented
  caveats (docs/hooks.md).
- `docs/landscape.md`: honest positioning vs Ruflo (API-only, blocked on
  Pro/Max), ClaudeFast Code Kit, Claude Octopus, Maestro, opusplan.
  "Not a framework" section in README.
- Repository URLs finalized (github.com/Rompomepome/amiral).


## v0.2.0 — 2026-07-03
- **Renamed to amiral** (was fable-lean): the pattern is
  orchestrator/worker, not one model. The admiral doesn't row.
- Configurable fleet: `AMIRAL_BRAIN` / `AMIRAL_HANDS` env overrides —
  survives model suspensions (Fable was suspended once already) and
  renames. Aliases became functions (arg passthrough).
- Plugin packaging: `.claude-plugin/plugin.json` + `marketplace.json` —
  installable via `/plugin marketplace add` + `/plugin install`.
- Restructure: `agents/` and `skills/` at repo root (plugin layout),
  `.claude/` mirrors kept for open-the-repo dogfooding, CI sync check.
- Safe permissions by default (no bypass flag shipped, CI-enforced),
  `docs/permissions.md` documents the full speed/safety spectrum.
- Windows: PowerShell profiles.
- `templates/verify-nextjs.sh` machine-verifiable done gate.
- `BENCHMARKS.md`: reproducible A/B/C protocol (ccusage-based).
- CI: syntax, fresh install, idempotence, CLAUDE.md preservation, clean
  uninstall, dogfood sync, manifest JSON validation, no-dangerous-flags.

## v0.1.0 — 2026-07-02
- Initial release as fable-lean: policy + 3 worker agents + /plan-ship
  + shell profiles + idempotent installer.
