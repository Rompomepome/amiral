# ports/

The amiral **implementation** targets Claude Code (routing env vars,
agent frontmatter, hooks). The amiral **discipline** is universal.

- [`AGENTS.md`](AGENTS.md) — the matelot discipline in the
  [AGENTS.md open standard](https://agents.md) (Linux Foundation),
  readable by 25+ tools: Codex, Aider, OpenCode, Cursor, Gemini CLI,
  GitHub Copilot, Zed, Warp, RooCode... Copy it to your repo root. Done.
- [`../PATTERN.md`](../PATTERN.md) — the CLI-agnostic spec, with an
  implementation map per tool (Aider's architect/editor mode gets you
  native brain/hands routing today).

Want to contribute a tool-specific port (an OpenCode agent config, a
Roo mode set, a Codex two-session script)? PRs welcome — one folder per
tool, a README, no binaries. We document ports; we do not maintain
runtimes for other CLIs. That restraint is the point.

## Concrete ports

- [`codex/`](codex/) — run the amiral discipline with Codex, including
  using Codex as the corsaire (adversarial second opinion on another
  model family).
- [`opencode/`](opencode/) — the brain/hands split on OpenCode's 75+
  providers: frontier plans, cheap tier executes, discipline via
  AGENTS.md.

Each port is documentation and config, not a runtime. amiral is the
discipline; these tools are the reach.
