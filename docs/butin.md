# Wiring the butin (one-time, opt-in)

The butin measures in two steps, on purpose:

1. **The hook writes a receipt.** When an agent finishes, we record only
   what the payload already knows (which agent, which session, where its
   transcript will be). No parsing, no arithmetic — the transcript is
   still being written at that moment, and measuring it there is how
   v0.11 over-counted by 6.7x.
2. **`amiral-butin` measures cold.** It reads the now-complete transcripts,
   **deduplicates by `message.id`** (a streaming turn is written many
   times; only the last record holds the final totals), takes the agent's
   real identity from the platform's own `.meta.json` sidecar, and prices
   it. A transcript that isn't flushed yet stays **pending** — never
   invented, measured on the next run.

Add to `~/.claude/settings.json`:

```json
{ "hooks": {
    "SubagentStop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-receipt.sh" }] }],
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-receipt.sh --brain" }] }]
} }
```

Then work normally and run `amiral-butin`. Nothing is sent anywhere. The
same receipts + transcripts always produce the same number — anyone can
re-run the measurement and check it.
