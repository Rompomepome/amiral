# Optional hook: the deterministic verification gate

The amiral policy *asks* workers to verify before claiming done. Policies
are prompts; prompts can be ignored. Hooks cannot — they are code.

`hooks/subagent-verify.sh` runs your project's `./verify.sh` whenever a
subagent tries to finish. If it fails, exit code 2 **blocks the worker
from stopping** and feeds the failure output back to it, forcing another
iteration. Skills teach, hooks enforce, subagents isolate.

## Enable it (opt-in)

Copy the script somewhere stable, then add to your project's
`.claude/settings.json` (or `~/.claude/settings.json` for global):

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "bash /path/to/hooks/subagent-verify.sh" }
        ]
      }
    ]
  }
}
```

Pair it with [templates/verify-nextjs.sh](../templates/verify-nextjs.sh)
dropped at your repo root as `verify.sh`.

## Caveats (read before enabling)

- It runs on EVERY subagent stop — including read-only ones like
  `reviewer`. On a slow build this adds real minutes. Prefer enabling it
  per-project, on projects with a fast `verify.sh`.
- An always-failing verify.sh + a persistent worker = a loop. Keep
  `verify.sh` honest and fast, and remember Esc interrupts.
- Hook schemas evolve with Claude Code releases; if the hook doesn't
  fire, check `/hooks` in a session and the current docs.
