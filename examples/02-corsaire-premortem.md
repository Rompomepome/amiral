# Example 2 — risky work gets an adversarial pass (the corsaire)

**The request** (verbatim, paths stripped):

> Pre-mortem attack on uncommitted v0.13.0 work … Assume it SHIPPED and
> something went badly wrong for a user; work backward to every plausible
> cause. Scope: `git diff` + untracked new files … Read-only: you may run
> scripts against throwaway mktemp homes to prove an attack, but NEVER
> touch the real ~/.claude or ~/.amiral …

The statusline edits `settings.json` and runs on every turn — the kind of
change that fails quietly and outside the test suite. Fleet policy: after
implementation, anything risky or unreviewable also gets the `corsaire`
(adversarial pre-mortem) before it's called done.

**Triage → route**

- Freshly implemented, touches a user's `settings.json` → risky tier.
- Needs a hostile reader who did *not* write it → **`corsaire` agent**,
  read-only, `model: sonnet`.
- Its top findings were addressed before the feature was reported done.

**Measured cost** (`~/.amiral/butin.jsonl`, baseline Opus)

| | |
| --- | --- |
| Model actually used | Sonnet 5 |
| Real cost | **$9.78** |
| Same tokens at the Opus baseline | $48.91 |
| **Saved on this one task** | **$39.13** |

An adversarial pass is pure judgment work — the tier you'd *expect* to
need the frontier model. It didn't: the corsaire ran on Sonnet and still
found the issues, at a fifth of the counterfactual cost.
