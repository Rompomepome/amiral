# Permissions: choosing your speed/safety trade-off

amiral ships with Claude Code's **default permission prompts**. That
is deliberate: this repo's whole philosophy is "verified, not trusted",
and that applies to the harness too. Here is the full spectrum, from
safest to fastest, so you can make an informed choice.

## 1. Default (what the aliases use)

Claude asks before edits and shell commands. Safe, noisy on big
delegated tasks.

## 2. Allowlist in settings (recommended sweet spot)

Pre-approve the specific commands your verification gates need, keep
prompts for everything else. In `~/.claude/settings.json` (or per
project in `.claude/settings.json`):

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run build:*)",
      "Bash(npm run lint:*)",
      "Bash(npm test:*)",
      "Bash(npx tsc:*)",
      "Bash(git diff:*)",
      "Bash(git status:*)"
    ]
  }
}
```

Now the build/typecheck/lint loops run unattended, but anything
destructive still prompts. You can also manage this live with
`/permissions`.

## 3. `--permission-mode acceptEdits`

Auto-accepts file edits, still prompts for shell commands. A good middle
ground for pure-implementation sessions:

```bash
amiral() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" --effort xhigh --permission-mode acceptEdits "$@"
}
```

## 4. `--dangerously-skip-permissions` (YOLO mode)

No prompts at all. Some experienced users run this daily, but understand
what you are accepting:

- The agent can run ANY shell command without asking — including
  destructive ones, in error or under prompt-injection from a file or
  web page it read.
- Combined with an orchestrator that spawns workers, one bad delegation
  can fan out fast.
- If you use it anyway: prefer an isolated environment (container, VM,
  or at minimum a dedicated git worktree with clean state), and never in
  a directory containing credentials.

We do not ship it by default and we won't. Add it to your own aliases
if you accept the trade-off.

## The subagent angle

Workers inherit the session's permission context. Restricting a worker's
`tools:` in its frontmatter (as `reviewer` does — read-only) is a
complementary layer: even in a permissive session, the reviewer cannot
write.
