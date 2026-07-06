# Security policy

amiral ships an installer that writes to `~/.claude/`, shell functions,
and an optional hook that executes a project's `verify.sh`. If you find
a way to abuse any of that (path traversal, command injection through
env vars or file names, privilege issues), please report it privately:

- GitHub: use "Report a vulnerability" (Security tab) on this repo, or
- Email: romain@shook-agency.fr

Please do not open a public issue for security reports. You'll get an
acknowledgment within 72 hours. Fixes ship as patch releases with
credit (unless you prefer anonymity).

Scope notes: the shipped profiles use Claude Code's default permission
prompts by design; `--dangerously-skip-permissions` is intentionally
never shipped (CI-enforced). The `subagent-verify.sh` hook executes
`./verify.sh` from the current project — only enable it in repos you
trust.
