# Benchmarks — the reproducible protocol

Anecdotes don't build trust; protocols do.

## What Anthropic measured

Anthropic's own cookbook "plan big, execute small" (a frontier model
plans + delegates, cheaper models execute) reports a reference run of
**~$1.61 for the team vs ~$4 all-frontier — ~2.5x cheaper, ~3x faster,
80%+ of tokens at the worker rate.** That's the pattern amiral packages.
Two caveats worth stating plainly: (1) those are Anthropic's figures on
their setup, not independently replicated — treat them as reference
points, not guarantees; (2) your ratio depends on how much of your task
is planning vs execution. Which is exactly why the protocol below exists:
measure it on *your* work.
 If you want to contribute a
quota report, follow this so numbers are comparable.

## Protocol

1. Pick ONE task, medium size (a real feature or refactor, ~30-90 min of
   agentic work). Write it down verbatim — you will run it three times.
2. Fresh session each run, same repo state each run (use a dedicated git
   worktree per run, reset between runs).
3. Run the three configs:
   - **A (naive):** `claude --model fable`, no routing, let it do
     everything itself.
   - **B (amiral):** `amiral` + `/plan-ship <task>`.
   - **C (baseline):** `matelot` (pure Sonnet) — sanity floor.
4. Measure per run:
   - tokens in/out — `npx ccusage` (community CLI that reads Claude
     Code's local usage data), or `/usage` screenshots
   - % of your usage window consumed
   - wall-clock time
   - DID IT PASS `./verify.sh`? (quality gate — cost means nothing if
     the result is broken)
5. Report it — the easy way is `amiral-report`: a local wizard that
   formats your numbers into the table row below and builds a prefilled
   GitHub issue URL for you to review and submit. Nothing is sent
   automatically; you post it yourself. (Or use the "Quota report"
   issue template by hand.)

## Results (community)

| Date | Task type | CC version | A: naive Fable | B: amiral | C: matelot | Verified? | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| _seeded soon_ | | | | | | | |

Maintainer note: the first row will be my own numbers on a Next.js
production codebase. PRs adding rows are the most valuable contribution
this repo can receive.
