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
   - **A (naive):** `claude --model fable`, no routing. **Trap:** if
     amiral is installed, your global `~/.claude/CLAUDE.md` imports the
     routing policy into EVERY session — so this run isn't naive at all.
     Comment out the `@amiral-policy.md` line for run A, restore after.
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

## The contamination traps (learned the hard way)

The author's own first A/B attempt was invalid, for two reasons worth
knowing before you run yours:

1. **The global policy leaks into the "naive" run.** amiral's install
   imports the routing policy in `~/.claude/CLAUDE.md`, which applies to
   every Claude Code session — including your control run. Result: run A
   triaged and delegated like run B. Disable the import for run A.
2. **Memory recognizes the task.** Claude Code remembers prior sessions
   in a project; the second run of the same task got "this was already
   built, verifying instead". `git checkout` resets the files, not the
   memory. Use a fresh clone per run, or equivalent-but-different tasks
   of matched size.

Publishing a wrong table would be worse than publishing none. Hence:

## Results

| Date | Source | Setup | Result | Verified |
| --- | --- | --- | --- | --- |
| 2026 | Anthropic cookbook ("plan big, execute small") | frontier plans, Sonnet executes | ~$1.61 vs ~$4 all-frontier (~2.5x cheaper, ~3x faster, 80%+ tokens at worker rate) | Anthropic's own eval — reference point, not replicated |
| 2026-07-08 | Author (observed, not A/B) | one real session, amiral policy active | $4.84 total, $4.51 of it frontier-only; Claude Code's usage panel: "75% of your usage came from subagent-heavy sessions… consider a cheaper model for simpler subagents" | usage panel screenshot |

Community A/B rows land here via [`amiral-report`](bin/amiral-report) —
run it after your benchmark, it formats the row and prefills the issue.
Drop yours in [issue #3](https://github.com/Rompomepome/amiral/issues/3).

Maintainer note: the first row will be my own numbers on a Next.js
production codebase. PRs adding rows are the most valuable contribution
this repo can receive.
