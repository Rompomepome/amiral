# Changelog

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
