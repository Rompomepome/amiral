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
amiral-trust          # pins the trust to verify.sh's checksum AND this repo's identity
```

**What this actually guarantees:**

1. The hook runs `verify.sh` only if you explicitly trusted THIS repo at
   THIS path. Untrusted repos are skipped, never executed.
2. The checksum detects edits to `verify.sh`'s own bytes and re-requires
   trust: change one byte of the file and the gate stops firing until you
   run `amiral-trust` again. The hook also re-hashes `verify.sh`
   immediately before running it, to shrink the window between the trust
   check and the run.
3. The fingerprint is also bound to the repo's identity (its remote
   origin URL, or failing that its root commit). A different repo later
   checked out at a previously-trusted path — even with a byte-identical
   `verify.sh` — does not *accidentally* inherit trust. This is **not an
   authentication boundary**: the origin URL is a local, unauthenticated
   string, so an attacker who already controls what gets written to that
   path can forge it (`git remote add origin <the-old-url>`). It closes the
   accidental-collision case (a clone of a public template landing where you
   once trusted a real project), not a deliberate malicious repo-swap — a
   local attacker with write access to your checkout is outside what any
   path-scoped trust file can defend.

**What it does NOT guarantee:** anything `verify.sh` sources, execs, or
invokes — a helper script it `source`s, `npm test`, a Makefile target,
code under `node_modules/` — is **not fingerprinted**. That code runs
with full shell privileges the moment `verify.sh` runs, just like
`verify.sh` itself. This is a deliberate scope limit, not an oversight: a
soundly-pinned transitive read-set is not achievable for an arbitrary
build in shell (you would need to enumerate and hash every file
`verify.sh` might read, including ones chosen at runtime by
`npm`/`make`/`$PATH` lookups — grep-based detection of `source`/`exec` is
both over- and under-inclusive, missing `eval`, `` `backticks` ``, and
plain PATH lookups). **So: trusting a repo means trusting its entire build, not just one file.**
Only run `amiral-trust` on repos whose full build you would be
comfortable running unsandboxed.

The hook also wraps execution in a 300s `timeout` so a hung verify can't
freeze your session.

Note: the trust fingerprint format changed in v0.15.1 to add the identity
binding above. If you trusted a repo before that release, run
`amiral-trust` once more in it — the old two-field (`path::hash`) format
no longer matches and is treated as untrusted, which is the safe
direction.

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
