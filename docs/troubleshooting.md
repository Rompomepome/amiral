# Troubleshooting

## Workers are running on Fable, not Sonnet

- Your Claude Code may not resolve the `sonnet` alias as a subagent
  model. Set the full model ID via the fleet env var:
  `export AMIRAL_HANDS=claude-sonnet-5` (add it to your rc file).
- Your organization may enforce an `availableModels` allowlist; excluded
  values silently fall back to the inherited (main) model.
- Check with `/agents` or read the transcript header of a spawned agent.

## `ultracode` does not appear in /effort

- ultracode requires an xhigh-capable model (Fable 5, Opus 4.8, Opus
  4.7). Since v2.1.160 the menu hides it instead of erroring when the
  model cannot run xhigh.
- If you were rerouted to a non-xhigh model, that's why (see below).

## My session silently switched from Fable to Opus

Fable 5 runs safety classifiers (cybersecurity, biology). A flagged
request is re-run on Opus with a notice, and the session stays on Opus
until you run `/model fable` again. It can trigger on your FIRST message
because the request carries workspace context (CLAUDE.md, git status,
directory names, MCP tool surfaces). Debug with `claude --safe-mode`, or
disable auto-switching in `/config`.

## The installer says "import already present"

That's the idempotence working: re-running never duplicates the import
line in your CLAUDE.md.

## Are permission prompts on by default?

Nothing to do — the shipped profiles already use default permission
prompts. See docs/permissions.md if you customized yours.

## Sonnet 5 not found

Run `claude update` — Sonnet 5 requires Claude Code v2.1.197+.
