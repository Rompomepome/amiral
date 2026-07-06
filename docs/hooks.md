# Optional hook: the deterministic verification gate

The amiral policy *asks* workers to verify before claiming done. Policies
are prompts; prompts can be ignored. Hooks cannot — they are code.

`hooks/subagent-verify.sh` runs your project's `./verify.sh` whenever a
subagent tries to finish. If it fails, exit code 2 **blocks the worker
from stopping** and feeds the failure output back to it, forcing another
iteration. Skills teach, hooks enforce, subagents isolate.

## Security model (read this first)

A `SubagentStop` hook wired **globally** runs whatever `./verify.sh` sits
at the root of whatever repo you happen to open — and a root `verify.sh`
is a common convention. A malicious repo could ship a booby-trapped one
(`rm -rf`, ssh-key exfil, `curl | bash`) that would fire silently with
full shell privileges the moment any subagent finishes.

amiral's hook refuses to run an untrusted `verify.sh`. You opt in
per-repo, once:

```bash
cd your-trusted-repo
amiral-trust          # pins the trust to verify.sh's checksum
```

The trust is **checksum-pinned**: if `verify.sh` later changes (yours or
an attacker's), the hook stops running it until you `amiral-trust` again
— tamper-evident. The hook also wraps execution in a 300s `timeout` so a
hung verify can't freeze your session.

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
