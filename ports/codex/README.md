# amiral on Codex

amiral is Claude Code specific, but its **worker discipline** is not. It
lives in [`../AGENTS.md`](../AGENTS.md), the open AGENTS.md standard that
Codex reads natively. So you can run the same discipline — plan, execute,
don't sprawl, nothing is "done" until the build passes — while working
with Codex, without any bridge to maintain.

There is no proxy here and no server. amiral does not *call* Codex; you
run Codex with amiral's discipline in front of it. That restraint is the
whole point (see the repo's "Not a framework" section).

## Setup

Codex reads an `AGENTS.md` at your repo root. Point it at amiral's:

```bash
# from your project root
cp /path/to/amiral/ports/AGENTS.md ./AGENTS.md
```

Codex now follows the matelot discipline: it plans before touching
multi-file changes, keeps trivial edits inline, and treats a task as done
only when the verification gate is green. Add a `verify.sh` at your root
(see [`../../templates/verify-nextjs.sh`](../../templates/verify-nextjs.sh))
and reference it in the file so "done" means the build and tests pass.

## Codex as the corsaire (adversarial pass)

The post that inspired this port suggested using a second model as a
contrarian reviewer. amiral already has that role — the **corsaire**, an
adversarial pre-mortem on your code. You can have Codex play it, giving
you an attacker on a *different* model family than the one that wrote the
code (fresh blind spots).

Point Codex at the corsaire brief and run it read-only on your diff:

```bash
# review the current diff with the corsaire's mandate, on Codex
codex --config AGENTS.md \
  "You are the corsaire (see agents/corsaire.md): assume this diff already
   shipped and failed in production. Attack inputs, state, auth, data,
   edges, dependencies. Concrete mechanisms only, ranked severity x
   likelihood. You modify nothing."
```

Now you have two adversaries available: the corsaire on Claude Code, and
Codex as a second opinion from another model. Same brief, different eyes.

## What this is (and isn't)

- **Is:** the amiral discipline, portable to Codex via an open standard.
- **Isn't:** amiral orchestrating Codex through a gateway. If you want a
  frontier model to *drive* cheaper workers, do that inside the tool that
  owns the loop (Claude Code for amiral). Cross-tool orchestration is a
  runtime to host and maintain — deliberately out of scope.
