# BUTIN port — the adapter contract

The butin (savings) core is provider-agnostic. To wire it to a harness
(Claude Code, Codex, OpenCode, Gemini CLI…), an adapter supplies these
capabilities. Optional ones **degrade gracefully** — never a crash, never
an invented number to compensate.

| Capability | Required | Role | Fallback if absent |
| --- | --- | --- | --- |
| `task_event` | yes | agent, chosen model, tokens in/out/cache, duration | — (without it there's nothing to measure) |
| `pricing_id` | yes | a model id resolvable in the multi-provider price table | — |
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

## Declaring capabilities

An adapter ships a `capabilities` list. The core and CLI adapt: absent
`statusline_surface` → no install prompt ever shown; absent `plan_detect`
→ dollars, not quota. The mock adapter in tests declares only
`task_event` + `pricing_id` and must still produce a correct API-mode
report — that's the guarantee the core doesn't depend on any harness.

## Platform findings (Claude Code, macOS, verified 2026-07)

Two load-bearing quirks observed on real usage, not in any published spec:

- **`agent_type` is not delivered in the SubagentStop payload.** On this
  platform `agent_hint` was empty on all 20 real receipts observed — the
  field a port would naively read for agent identity simply isn't there.
  Agent identity must instead come from the transcript's `.meta.json`
  sidecar (`agentType`), written alongside the transcript file. Any port
  that only trusts the hook payload's hint will silently mislabel every
  subagent as a generic fallback ("worker"). This is why `agent_name()`
  in `lib/butin/measure.py` treats the hint as a last resort, never the
  primary source.
- **Subagent transcripts are garbage-collected.** Files under
  `~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl` are
  deleted by the platform after some days. A receipt whose transcript
  has vanished can never be measured — keeping it "pending" forever
  would be false completeness, not honesty. `measure.py` enforces a
  receipt TTL (`BUTIN_RECEIPT_TTL_HOURS`, default 48): once a receipt's
  transcript is absent (not merely unparseable — that case still stays
  pending, it may just be mid-flush) and its age exceeds the TTL, it
  becomes `unmeasurable` with `"reason": "transcript no longer on disk"`
  and is drained from `receipts.jsonl`. Pending must never be forever.
