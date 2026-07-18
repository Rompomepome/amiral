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

## Commands

- `amiral-butin init` — first-run setup: detects your baseline model from
  history (asks you to confirm if it looks like a frontier model — the
  Fable trap), writes `butin-config.json`.
- `amiral-butin rebaseline` — same detection + confirmation, re-run any
  time. Applies to FUTURE events only — history keeps the baseline it
  was priced with.
- `amiral-butin config --baseline <pricing_id>` / `--mode api|plan` /
  `--show` — the direct escape hatch: set the baseline or the mode
  WITHOUT detection (the baseline is validated against the priced
  models; unknown ids are rejected and nothing is written), or print the
  current config plus its resolved rates. Flags combine (`--baseline X
  --mode plan`); no arguments behaves as `--show`. The collector re-reads
  the config on every event, so a change is live from the next task —
  but it applies to FUTURE events only: history keeps the baseline it
  was priced with.
- `amiral-butin add-model <id> <in_$/Mtok> <out_$/Mtok>` — price a model
  yourself, day one, no repo update needed.
- `amiral-butin refresh-pricing` — explicit-only pointer to the table;
  nothing here ever touches the network.
- `amiral-butin --detail` — the honesty block: what's estimated, the
  baseline source, the pricing table version, the decomposition bias.
- `amiral-butin --haircut=N` — display-time conservative reduction (%) of
  the counterfactual, for a more cautious number.

## Statusline

Opt-in, ambient line in Claude Code's own status bar — the same numbers as
`amiral-butin`'s report, computed once per task event and cached, so
rendering it costs nothing on every turn.

- **API mode**: `⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas ▰▰▰▰▱)`
- **Plan mode** (mirrors `butin-config.json`'s `mode`): `⚓ 2.3k prem tok
  avoided today · 123k total (57 meas ▰▰▰▰▱)` — premium tokens avoided is
  the hero, never a dollar figure, same rule as the report (spec §5bis).
- **Amber = a net-negative day, and it is NEVER hidden.** Green when
  today's net is positive, dim when zero/no tasks yet, amber with an
  explicit minus sign when negative. `amiral statusline mute` suppresses
  GOOD news only — a net-negative day still prints in amber. Honesty
  outranks mute, always.
- A `· stale` suffix appears when the cache has fallen more than 10
  minutes behind the log — the collector is probably wired but failing;
  check `~/.amiral/butin-errors.log`.

### Coverage bar

The 5-cell bar (`▰`/`▱`, same idea as Claude Code's own context meter) is
over the one honest denominator the cache has: `measured + pending +
unmeasured` — every task event is exactly one of the three. Rounding is
literal, not flattering: 5/5 filled only at *exactly* 100% coverage, floor
otherwise, but never 0 filled cells when at least one event was measured
(a sliver of real coverage must never look like zero). No bar exists for
the dollar/premium-tokens totals — a savings figure has no natural
maximum, so any "scale" drawn for it would be a made-up number.

### Profile marker

If the session was launched via one of the `amiral`/`amiral-solo`/
`amiral-advisor`/`amiral-fine`/`amiral-ultra`/`matelot` shell functions, its
name appears right after the anchor: `⚓ ultra · +$0.43 today · ...` (dim,
regardless of the line's green/amber sign — it's identity, not news). With
no money segment to show (fresh install, corrupt cache, muted positive
day) the marker still renders alone: `⚓ ultra`. Mute only ever hides GOOD
money news, never the marker, and never a net-negative day.

**Be precise about what the marker does and doesn't mean.** The ⚓
statusline itself is wired through Claude Code's *global* `statusLine`
setting — every session on the machine renders it, launched by amiral's
functions or not. The routing **policy** in `shell/amiral-profiles.sh` is
also global (`~/.claude/CLAUDE.md` imports it), so it governs every
session regardless of marker. The marker means only: *this session's
`claude` process was launched by `<profile>`*. A bare `claude` shows no
marker but still runs under the same global policy.

Why not read `AMIRAL_BRAIN`/`AMIRAL_HANDS` instead of a dedicated var?
Verified live: those are `export`ed by `_amiral_load_prefs`, so once one
amiral function has run in a shell, they leak into every later **bare**
`claude` launched from that same shell — a false "amiral on". A
per-invocation, never-exported `AMIRAL_PROFILE` set only on each
function's own `claude` command line is the only signal that can't lie
this way. The renderer treats it as untrusted input reaching a terminal:
anything not matching `^[a-z][a-z-]{0,11}$` is silently discarded (no
marker), never printed raw.

### Commands

- `amiral statusline install` — opt-in, one time. Backs up `settings.json`
  (timestamped, same convention as the installer), saves any statusLine
  you already had (verbatim) so it can be **restored on uninstall**, then
  wires ours. A pre-existing statusline keeps rendering — chained on the
  same line when it fits, or the row above when it doesn't (multi-line is
  officially supported by Claude Code's statusline mechanism). Never edits
  `settings.json` with sed/regex: `jq` when present, else `python3`, else
  it prints the exact snippet to paste by hand and touches nothing.
- `amiral statusline uninstall` — restores the displaced statusline (or
  removes the key if there wasn't one). Refuses to touch a `statusLine`
  that isn't amiral's.
- `amiral statusline mute` / `unmute` — toggle the good-news-only
  suppression described above.
- `amiral statusline status` — installed?, muted?, cache age, whether a
  project-scope `.claude/settings.json` shadows the user-scope one here.

### How the data flows

A task-event producer (the same hooks that already write `butin.jsonl` /
`receipts.jsonl` — both the receipt path and the legacy direct collector)
runs `core.awk` — the **same engine the report uses** — over the full log
and a today-filtered slice, and writes the result to
`~/.amiral/butin-cache.tsv` atomically (compose to a PID-unique temp file,
then `mv`). The renderer reads only that cache: it never opens
`butin.jsonl`, never computes a number itself. There is exactly one
calculator in the whole system. "Today" is the **UTC day**, matching the
collector's timestamps — local midnight can disagree with the data plane
by a few hours depending on your timezone; it self-heals on the next task.
Because cold measurement is stability-gated (a transcript touched in the
last 60 seconds stays `pending`, never guessed at — the lesson from
v0.11's 6.7x over-count), a just-finished task can take up to ~60s to
appear; it is retried on the next event.

For long-running background fleets where the main session sits idle, add
`"refreshInterval": 30` next to `.statusLine` in `settings.json` (seconds,
minimum 1 per Claude Code's docs) to also re-render on a timer.

If you wire `settings.json` by hand instead of using `install`, also
`touch ~/.amiral/statusline-on` — the cache producer is opt-in and stays
silent until that flag exists.

**Windows**: `bin/amiral-statusline.ps1` ships and is documented, reading
the same cache format (every number parsed with `[double]::Parse` and
`InvariantCulture`, so a French Windows locale can't reintroduce the
comma-decimal bug). `amiral statusline install` does **not** wire it
automatically — POSIX shell is v1, PowerShell parity is tracked backlog
(docs/butin-spec-v2.md), never an implied promise. Point `settings.json`
at it yourself: `"command": "powershell -NoProfile -File
%USERPROFILE%/.claude/butin/amiral-statusline.ps1"` (forward slashes —
Git Bash on Windows eats backslashes).
