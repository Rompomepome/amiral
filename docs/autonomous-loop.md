# Running amiral in an autonomous loop

amiral is built for a human-in-the-loop session: you type `amiral`, it
plans and delegates, and it stops before anything irreversible. But the
same discipline works inside an autonomous loop (the "Ralph" pattern — a
model driven in a loop against a task list until done). This guide shows
how to do that safely, because an unattended agent with amiral's routing
is powerful and needs guardrails.

## The idea

A wrapper loop feeds amiral a task, lets it plan/execute/verify, checks
whether the task is actually done (via `verify.sh`), and either moves to
the next task or retries. The brain still plans, workers still execute,
the corsaire still guards risky changes — you've just removed the human
"continue" between iterations.

## Minimal loop

```bash
#!/usr/bin/env bash
# ralph-amiral.sh — drive amiral over a task list until each verifies.
# SAFETY: run in a dedicated git worktree, on a branch, never on main.
set -uo pipefail

TASKS="tasks.md"          # one task per line
MAX_ITERS=3               # retries per task before giving up

while IFS= read -r task; do
  [ -z "$task" ] && continue
  echo "=== TASK: $task ==="
  for i in $(seq 1 "$MAX_ITERS"); do
    amiral "/plan-ship $task"        # plan -> delegate -> verify -> review
    if ./verify.sh; then
      echo "  ✓ verified on attempt $i"; break
    else
      echo "  ✗ verify failed, retry $i/$MAX_ITERS"
    fi
  done
done < "$TASKS"
```

## Guardrails (do not skip these)

- **Dedicated worktree, feature branch.** Never loop on `main`. A bad
  iteration must be `git reset`-able without touching real work.
  ```bash
  git worktree add ../amiral-run -b amiral/autonomous
  cd ../amiral-run
  ```
- **`verify.sh` is the stop condition.** The loop only advances when the
  build and tests pass. No green gate = no progress. This is what keeps
  an autonomous run from piling broken commits.
- **The corsaire still fires** on risky changes (auth, payments, data) —
  keep it wired in the policy. An unattended loop is exactly when you
  want an adversary in the path.
- **Fable brain in a loop = credits meter running.** The loop inherits
  your configured brain; `AMIRAL_BRAIN=fable ./ralph-amiral.sh` runs the
  whole batch with Fable planning. Powerful, but every iteration bills
  the brain at frontier rates — run `amiral-savings` on your expected
  volume first, and prefer the default (Opus/Sonnet in-plan) for long
  unattended batches.
- **Cap the iterations and the spend.** `MAX_ITERS` bounds retries; run
  `amiral-savings` first to know what a long loop can cost on your brain
  model. An autonomous loop on a frontier brain can burn a window fast.
- **Review the branch before merging.** Autonomous ≠ unsupervised at the
  end. The loop produces a branch; a human still reads the diff before it
  reaches `main`.

## When to use it

Good: a batch of well-specified, independently-verifiable tasks (add
tests to N modules, migrate M files to a new API). Each has a clear
`verify.sh` outcome.

Bad: vague or exploratory work, anything touching production data, or
tasks where "done" can't be machine-checked. If `verify.sh` can't tell
whether it worked, an autonomous loop can't either — stay in the
interactive session.
