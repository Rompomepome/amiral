# Wiring the butin collector (one-time, opt-in)

The butin only measures what YOU wire. Add to `~/.claude/settings.json`:

```json
{ "hooks": {
    "SubagentStop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-collect.sh" }] }],
    "Stop": [{ "hooks": [{ "type": "command",
      "command": "bash ~/.claude/butin/butin-collect.sh --brain" }] }]
} }
```

Then work normally; `amiral-butin` shows the report. Nothing is sent
anywhere; errors land in `~/.amiral/butin-errors.log`. Check health:
`amiral-doctor` (butin section). Provenance in commits: `amiral-journal`.

## Notes
- **POSIX-only for now** (bash + awk). PowerShell parity is a tracked
  backlog item, not an implied promise.
- **Squash-merge teams**: trailers live on the squashed commit, or use
  `amiral-journal note` (git notes, ref `amiral`) which survives
  rewrites. Notes need one push config: `git push origin refs/notes/amiral`.
- **Multi-machine**: butin logs are append-only JSONL with unique event
  ids — merge machines with `cat`, the core dedups on read.
- **Pricing**: the table is embedded and versioned; it is NEVER fetched
  automatically (nothing phones home). Edit `pricing.tsv` to refresh;
  the report warns when the table is >3 months old.
