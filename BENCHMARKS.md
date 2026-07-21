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
| 2026-07-21 | Author (**observational**, not A/B) — amiral's own multi-week build | baseline **Opus** (the author's real prior default), **~70 amiral-routed tasks and climbing**, plan mode | **~3.9M premium tokens avoided** (API-equivalent **~$880, and climbing** vs the same tokens priced at Opus); coverage **exactly as `amiral-butin` prints it** — measured/total with pending in the denominator (e.g. `118/130 measured · 1 pending · 11 unmeasurable` on 2026-07-21), phantom receipts excluded (count shown in the report); other-subagent activity (**~$77**, not amiral-routed) excluded | `amiral-butin` on the author's real `~/.amiral/butin.jsonl` — a **dated, still-growing snapshot** (see note); run it yourself for the live figure |

### Observational ≠ A/B — read this before comparing the rows

The row above and the protocol below measure **different things**, and
conflating them would be dishonest:

- The **protocol** (steps 1–5) is an **A/B trial**: run the *same task*
  three ways (naive / amiral / pure-worker) and compare. It isolates
  amiral's effect on one controlled task.
- The **six-week row** is **observational**: it is what was *actually
  spent* on real routed work over six weeks, versus the **same tokens
  repriced at the Opus baseline** — the counterfactual. It is not a
  controlled comparison; there is no parallel "naive" universe to diff
  against. It answers "what did routing cost vs not routing, on the work
  that actually happened", not "is amiral faster on task X".

Two caveats travel with the observational number, both stated in
`amiral-butin --detail`:

1. **Decomposition bias, in amiral's favor.** The counterfactual prices
   the *decomposed* token volume — each worker re-reads its own context —
   at the baseline rate. A single frontier session would share some of
   that context, so the true no-routing cost is somewhat lower than the
   counterfactual shown. Use `amiral-butin --haircut=15` for a
   deliberately conservative view. The number is an honest upper-ish
   estimate, not a bill.
2. **Only amiral-routed work is counted.** Subagents Claude Code spawns on
   its own (general-purpose, Explore, …) are measured but shown
   separately and **excluded** from the figure above — amiral didn't
   route them, so it doesn't claim them.

**This is "measured here", not "amiral saves you $X".**
Your ratio depends entirely on your planning-vs-execution mix. The point
is not to trust this row — it's to reproduce your own.

**Why the row is a dated snapshot, and reads the way the tool prints.**
The author's log is active and append-only: every routed task adds an
event, so the aggregate ($, tasks, coverage) climbs whenever the author
keeps working — the numbers above were lower a day earlier and will be
higher a day later. Two rules keep this honest against a reader who just
runs the command:

1. **Coverage is quoted in the tool's own shape** — `measured / total ·
   pending · unmeasurable`, pending included in the denominator, exactly
   what `amiral-butin` prints. There is one definition of coverage and
   it's the tool's; the row does not invent a prettier ratio. (Phantom
   receipts — see the phantom/loss split in `--detail` — are the one
   thing excluded, and the count is always shown, never hidden.)
2. **The aggregate is a point-in-time snapshot, not a constant.** Run the
   command yourself and you'll see a *different* (larger, on an active
   machine) number — that's the ledger growing, not a discrepancy. What's
   stable and checkable is the per-task data in [`examples/`](examples/):
   each event reprices to the same dollar forever, because the transcript
   doesn't change.

### Get your own in two commands

```bash
amiral-butin backfill --all   # mint receipts for your past sessions' real transcripts (local, mints only)
amiral-butin                  # measure them cold and print your report
```

Everything is local; nothing is sent anywhere. The same transcripts
always reprice to the same number, so anyone can re-run and check.

Once you have ≥20 amiral-routed tasks, `amiral-journal flag` prints a
shareable badge from that same data — **generated on demand, embedding
your *current* count and net**:

```
$ amiral-journal flag
[![sailed with amiral](https://img.shields.io/badge/⚓_sailed_with_amiral-<N>_amiral--routed_tasks_·_net_%2B$<NET>-2b4c7e)](...)
```

<!-- Deliberately NOT a live shields.io image with hardcoded numbers here:
     the badge encodes a task count + net that climb with every routed task,
     so a pinned image URL would drift out of date permanently and no CI
     guard could catch a stale number baked into an external image. The
     command generates a current one on demand instead. -->
Run it to mint a current one for your own README; it refuses under 20
measured tasks by design.

Community A/B rows land here via [`amiral-report`](bin/amiral-report) —
run it after your benchmark, it formats the row and prefills the issue.
Drop yours in [issue #3](https://github.com/Rompomepome/amiral/issues/3).

Maintainer note: the first row will be my own numbers on a Next.js
production codebase. PRs adding rows are the most valuable contribution
this repo can receive.
