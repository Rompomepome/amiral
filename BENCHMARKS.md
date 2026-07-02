# Benchmarks — the reproducible protocol

Anecdotes don't build trust; protocols do. If you want to contribute a
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
5. Report via the "Quota report" issue template.

## Results (community)

| Date | Task type | CC version | A: naive Fable | B: amiral | C: matelot | Verified? | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| _seeded soon_ | | | | | | | |

Maintainer note: the first row will be my own numbers on a Next.js
production codebase. PRs adding rows are the most valuable contribution
this repo can receive.
