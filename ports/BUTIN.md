# BUTIN port — the adapter contract

The butin (savings) core is provider-agnostic. To wire it to a harness
(Claude Code, Codex, OpenCode, Gemini CLI…), an adapter supplies these
capabilities. Optional ones **degrade gracefully** — never a crash, never
an invented number to compensate.

| Capability | Required | Role | Fallback if absent |
| --- | --- | --- | --- |
| `task_event` | yes | agent, chosen model, tokens in/out/cache, duration | — (without it there's nothing to measure) |
| `pricing_id` | yes | a model id resolvable in the multi-provider price table (see "dated model ids" below) | — |
| `history_scan` | no | access to prior logs for baseline auto-detection | default baseline declared by the adapter (conservative, cheapest plausible) |
| `plan_detect` | no | API vs subscription/plan | API mode (real dollars) |
| `quota_snapshot` | no | % of windows/limits at task time | quota-mode metrics omitted |
| `statusline_surface` | no | official persistent-display mechanism | command-only |

## What an adapter must emit

For each routed task, append one JSONL line to `~/.amiral/butin.jsonl`
in the schema below. The core reads only generic keys — it never knows
which harness produced them.

```json
{ "v": 1, "ts": "…", "agent": "grunt", "chosen_model": "<pricing_id>",
  "tokens": {"in":0,"out":0,"cache_write":0,"cache_read":0},
  "real_cost_usd": 0.0, "baseline_model": "<pricing_id>",
  "counterfactual_cost_usd": 0.0, "outcome": "ok|retry|escalated",
  "escalation_extra_usd": 0.0, "prem_in_avoided": 0, "prem_out_avoided": 0 }
```

## Dated model ids

The platform sometimes reports a `pricing_id` with a trailing date, e.g.
`claude-haiku-4-5-20251001`, while the price table holds the undated
`claude-haiku-4-5` (verified present in real transcripts). `measure.py`
retries a pricing-table MISS exactly once, stripping a trailing
`-YYYYMMDD` (dash + exactly 8 digits); if the stripped id isn't priced
either, the task stays unmeasurable — never a guessed price, never a
neighbouring model's rate, and an undated unknown id is never touched (no
8-digit suffix, no retry attempted). `chosen_model` always stays the id
the platform actually billed; when normalization fires, the event also
carries `billed_pricing_id` (the stripped id whose rate was used) and
`pricing_normalized: true` — added only in that case, so single-model
undated events stay byte-compatible with pre-v0.15 output.

## Declaring capabilities

An adapter ships a `capabilities` list. The core and CLI adapt: absent
`statusline_surface` → no install prompt ever shown; absent `plan_detect`
→ dollars, not quota. The mock adapter in tests declares only
`task_event` + `pricing_id` and must still produce a correct API-mode
report — that's the guarantee the core doesn't depend on any harness.

## Platform findings (Claude Code, macOS, verified 2026-07)

Load-bearing quirks observed on real usage, not in any published spec:

- **SubagentStop does not fire for Task-tool agents on 2.1.214.** Verified
  live 2026-07-18 with a controlled experiment: a synchronous agent ran to
  completion, its transcript and `.meta.json` sidecar were written
  instantly — and `receipts.jsonl` never moved. 9 real Task-agent
  transcripts existed in that session; 0 receipts were ever recorded for
  them. On this build, butin has been structurally blind to ~100% of
  worker output via the SubagentStop hook alone.
- **The SubagentStop firings that DO happen come from internal/ephemeral
  agents whose transcript was never written.** 20/20 historical
  SubagentStop-sourced receipts (plus 2/2 observed live) pointed at an
  `agent_transcript_path` that was *minted* by the platform (the field is
  present, non-empty) but the file at that path never existed — and
  `agent_type` in the same payload was empty. In every case the session
  directory was alive with 6-13 *other*, real `agent-*.jsonl` transcripts
  sitting right next to the missing one. An earlier version of this
  document explained these absent-transcript receipts as "the platform
  garbage-collects subagent transcripts after some days" — that
  explanation is **wrong** for every receipt actually observed: the
  correct read is "this path was never written in the first place",
  because a live process wrote 6-13 sibling files in the same directory
  around the same time and only this one name never appeared. Whether the
  platform ever does GC old transcripts remains an open possibility, not
  something this data demonstrates.
- **Therefore: worker receipts are produced by DISCOVERY off the Stop
  hook, not by SubagentStop.** The Stop hook (brain path) fires reliably
  every turn and always carries the live main `transcript_path`. After
  recording the brain receipt, `adapters/claude-code/butin-receipt.sh`
  scans that session's `.../<session>/subagents/` directory for
  `agent-*.jsonl` files that exist on disk but have no receipt yet, and
  mints a worker receipt for each — `ts` set to the *transcript's own
  mtime* (the task's real completion time), not discovery time, so
  day-sliced views place the work on the day it actually happened.
  Identity still comes from the `.meta.json` sidecar at measure time, same
  as always (`agent_hint` on a discovered receipt is deliberately empty).
  Dedup is by full path, checked against both `receipts.jsonl` (not yet
  measured) and `butin.jsonl` (already measured and drained) — so a
  transcript is never re-discovered once it's been accounted for. The
  plain (non-`--brain`) branch of the hook now performs the SAME
  full-path check against both files, for role=worker, before appending
  its own receipt: if a future build restores real SubagentStop firings,
  a receipt it produces for a transcript discovery already recorded (or
  measured) is skipped, and — symmetrically — a transcript SubagentStop
  already receipted is skipped by discovery too. The dedup is two-way by
  construction, not by convention: whichever path runs first wins, the
  other is a no-op for that transcript. (Brain receipts are exempt from
  this transcript-based dedup — they legitimately re-reference the SAME
  main transcript every turn; see the next point.) `lib/butin/measure.py`
  also carries a belt-and-braces version of this same check: any worker
  receipt whose transcript already has a measured event is dropped
  (counted, never re-measured, never a second event), in case a duplicate
  receipt line ever reaches `receipts.jsonl` some other way.
- **`agent_type` is not delivered in the SubagentStop payload either way.**
  `agent_hint` was empty on all 20 real receipts observed — the field a
  port would naively read for agent identity simply isn't there,
  regardless of whether the receipt came from SubagentStop or discovery.
  Agent identity must instead come from the transcript's `.meta.json`
  sidecar (`agentType`), written alongside the transcript file. Any port
  that only trusts the hook payload's hint will silently mislabel every
  subagent as a generic fallback ("worker"). This is why `agent_name()`
  in `lib/butin/measure.py` treats the hint as a last resort, never the
  primary source.
- **A receipt whose transcript is absent can't stay pending forever.**
  Since every observed absent-transcript receipt was never-written (see
  above) rather than written-then-removed, the only legitimate reason a
  transcript is briefly missing is the in-flight flush race (minutes, not
  hours). `measure.py` enforces a receipt TTL (`BUTIN_RECEIPT_TTL_HOURS`,
  default **6h** — dropped from 48h now that the true cause is known: 6h
  sits far above any real flush delay while killing the pending inflation
  the old 48h default caused from phantom receipts). Once a receipt's
  transcript is absent (not merely unparseable — that case still stays
  pending, it may just be mid-flush) and its age exceeds the TTL, it
  becomes `unmeasurable` and is drained from `receipts.jsonl`. Pending must
  never be forever. The reason is **split by whether the transcript was
  ever observed on disk** (recorded at mint time as the receipt's
  `"observed"` boolean — discovery, and the guarded plain branch, only
  mint when the file exists): if it was observed and is now gone, the
  event reads `"transcript removed after it was recorded …"` — a real
  **LOSS**, which STAYS in the coverage denominator (genuine data loss
  must stay visible); if it was never observed, it reads `"transcript
  never written (phantom …)"` — noise the harness generated about itself,
  excluded from coverage but still counted on its own line. (Events minted
  before this split carry the legacy combined reason `"transcript absent
  (never written or removed)"` and cannot be re-split retroactively — the
  originating receipt is already drained; they are presumed phantom on the
  v0.14 evidence that SubagentStop fired only for never-written
  transcripts on that build.)
