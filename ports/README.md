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
