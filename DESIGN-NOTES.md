# Design notes — statusline, live config, receipt

Design pass on v0.10.1 (branch `audit/v0.10.1`), 2026-07-11. **Spec only — nothing here is implemented.**
Constraints inherited from `docs/butin-spec-v2.md`: statusline is already a SHOULD ("1-line nominal; O(1) cache written atomically via mv"); nothing hosted, nothing phones home, no demo mode; POSIX shell first, PowerShell parity is tracked backlog, never an implied promise.

Mechanism facts below were verified against the official Claude Code docs (`code.claude.com/docs/en/statusline.md`, `/en/hooks.md`) on 2026-07-11. Version-gated features are flagged.

---

## 1. Statusline (highest priority)

### 1.1 Mechanism facts (verified, cited)

- Config lives in `settings.json`: `{"statusLine": {"type": "command", "command": "<path or inline>", "padding": 0}}`. Optional `refreshInterval` (seconds, min 1) re-runs the command on a timer *in addition to* event-driven updates; optional `hideVimModeIndicator`. (statusline.md, "Manually configure a status line".)
- The command receives a JSON object on **stdin** with, among others: `model.id`, `model.display_name`, `session_id`, `workspace.*`, `cost.total_cost_usd`, `context_window.*`, `rate_limits.five_hour|seven_day.*` (Pro/Max plans only), `version`. (statusline.md, "Available data".)
- It runs after each assistant message, after `/compact`, on permission-mode change; **debounced 300 ms; an in-flight run is cancelled when superseded** → the renderer must be fast and side-effect-free.
- **Multi-line is officially supported**: "each `echo` or `print` statement displays as a separate row." So a two-line display is reliable — but the spec's own SHOULD says 1-line nominal; we use line 2 only in the chaining case (§1.6).
- ANSI colors supported (`\033[33m` amber); OSC 8 links supported. The docs warn complex escape sequences can occasionally glitch → keep to plain SGR color codes.
- `tput cols` does not work (output is captured); read `COLUMNS`/`LINES` env vars instead (Claude Code ≥ 2.1.153).
- Settings precedence: project `.claude/settings.json` overrides user `~/.claude/settings.json` → a project-level `statusLine` silently masks ours; the installer must detect and warn.
- The statusline only runs after the workspace trust dialog is accepted, and `disableAllHooks` gates it too.
- There is no programmatic CLI to set it (only the interactive `/statusline` or editing settings.json) → we edit settings.json ourselves, carefully (§1.5).

### 1.2 Architecture: producer / cache / renderer

Three parts, one honesty invariant: **the renderer never computes and never reads `butin.jsonl`.** All numbers displayed come from the same engine that prints the report (`lib/butin/core.awk`), via a cache the collector writes. No second accounting implementation may ever exist (that is how displayed numbers and reported numbers would drift apart).

```
SubagentStop/Stop ──> butin-collect.sh ──append──> ~/.amiral/butin.jsonl
                              │
                              └──run core.awk twice (full log + today slice)
                                 write ~/.amiral/butin-cache.tsv.tmp.$$  ──mv──> butin-cache.tsv
Claude Code statusline ──stdin JSON──> amiral-statusline.sh ──reads──> butin-cache.tsv   (O(1))
```

- **Producer** (modify `adapters/claude-code/butin-collect.sh`): after the existing append, re-run `core.awk` over the full log, and once more over a today-filtered slice (pre-filter by `"ts":"<UTC-day>` prefix with a two-line awk, pipe into core.awk unchanged — core.awk stays universal, no date logic added to it). Write all aggregates to `butin-cache.tsv.tmp.$$`, then `mv` onto `~/.amiral/butin-cache.tsv`. Cost: two O(n) awk passes per *task* (not per render); at 10 MB of JSONL that is ~0.2 s, amortized once per task. Log rotation (already on the spec roadmap) caps n. This is deliberate: an incremental O(1) cache update would require re-implementing dedup/escalation/brain-premium rules outside core.awk — a drift machine. Rejected.
  - The temp name **must be PID-unique** (`.tmp.$$`). A fixed `.tmp` name would reintroduce the same clobber race the audit found in the collector's `$STATE.tmp`.
  - Concurrent collectors: each computes from the full log at its own time and `mv`s; last writer wins with a complete, internally consistent snapshot. `rename(2)` is atomic on the same filesystem → readers never see a partial file.
- **Cache** (`~/.amiral/butin-cache.tsv`, format v1): `key<TAB>value` lines, C locale, UTF-8. Grep-able from bash and PowerShell alike, extensible without breaking readers:

  ```
  v	1
  generated_ts	2026-07-11T12:20:00Z
  day	2026-07-11
  mode	api
  baseline	claude-sonnet-4-6
  net_total	12.3456
  net_today	0.4321
  prem_avoided_total	123456
  prem_avoided_today	2345
  measured	57
  unmeasured	3
  esc_today	1
  last_receipt	grunt→claude-haiku-4-5: $0.009 (baseline $0.034, est.)
  last_receipt_ts	2026-07-11T12:19:58Z
  ```

  "Today" is the **UTC day**, matching the `ts` field stamped by the collector (`date -u`). Local-midnight would silently disagree with the data plane; documented in the file header comment and docs/butin.md.
- **Renderer** (new `bin/amiral-statusline`, installed to `~/.claude/butin/amiral-statusline.sh`): reads stdin (must consume it even if unused — needed for chaining, §1.6), reads the cache with one awk pass, prints one line, exits 0. Under 20 ms. Never touches butin.jsonl, never writes anything, never prints to stderr (statusline errors would flicker in the UI). `export LC_ALL=C` like every other script.

### 1.3 What it shows

One line, nominal:

- **API mode**: `⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas)`
  - Color from **today's** sign: green when `net_today > 0`, dim when zero/no tasks today, **amber (`\033[33m`) when negative** — e.g. `⚓ −$0.12 today (1 escalation) · +$12.35 net`. A net-negative day is *never hidden or clamped*; that is the honesty rule made pixel.
- **Plan mode** (from `mode` in the cache, which mirrors butin-config.json): `⚓ 2.3k prem tok avoided today · 123k total (57 meas)` — premium-tokens-avoided is the hero, consistent with the report's §5bis rule (never "cash saved" on a subscription).
- Degraded states, all silent-by-design:
  - No cache file → print **nothing**, exit 0 (fresh install, collector not wired; an error string would be noise in every session forever).
  - Cache `generated_ts` older than `butin.jsonl` mtime by > 10 min → append dim `· stale` (collector wired but failing; points at butin-errors.log via docs, not via the statusline).
  - `NO_COLOR` respected (same convention as amiral-butin).
- If `last_receipt_ts` is fresh (< 10 min), the receipt replaces the totals segment for that render (§3). One line either way.

### 1.4 Commands: `amiral statusline install|uninstall|mute|unmute|status`

Implementation lives in `bin/amiral-butin` as a `statusline` subcommand arm (keeps one distribution channel and one file copied by install.sh); the word `amiral statusline …` is routed by a small dispatch added at the top of the `amiral()` function in `shell/amiral-profiles.sh`:

```sh
amiral() {
  case "${1:-}" in statusline) shift
    bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-butin" statusline "$@"; return $? ;;
  esac
  _amiral_first_run; _amiral_load_prefs
  ...
}
```

Files to touch: `bin/amiral-butin` (subcommand), new `bin/amiral-statusline` (+ `.ps1` shape), `shell/amiral-profiles.sh` (dispatch), `adapters/claude-code/butin-collect.sh` (cache write), `install.sh` (copy renderer to `~/.claude/butin/`), `uninstall.sh` (remove + offer restore), `bin/amiral-doctor` (checks: statusline wired? project-level override shadowing it? cache fresh?), `docs/butin.md` (section), `tests/test-statusline.sh` (new), `.github/workflows/ci.yml` (run it).

### 1.5 Install: opt-in, backup, surgical edit

`amiral statusline install`:

1. Refuse if `~/.claude/settings.json` is unparseable (never "fix" a broken file).
2. Timestamped backup: `settings.json.amiral-bak.<epoch>` (same convention install.sh already uses).
3. If a `statusLine` entry exists and is not ours: save the **verbatim JSON object** to `~/.amiral/statusline-prev.json` (this powers both chaining and restore), then replace `statusLine.command` with `bash ~/.claude/butin/amiral-statusline.sh`.
4. JSON editing: prefer `jq` when present; else `python3 -c` with `json` stdlib (python3 is already a soft dependency of amiral-report); else print the exact snippet to paste manually and touch nothing. **Never sed/regex into settings.json.**
5. Idempotent: if `statusLine.command` already contains `amiral-statusline`, print "already installed" and exit 0.
6. Warn (not fail) when the current repo has `.claude/settings.json` or `.claude/settings.local.json` with its own `statusLine` — project scope overrides user scope, so ours won't show there.

`amiral statusline uninstall`: if the current `statusLine.command` is ours → restore the saved `statusline-prev.json` object verbatim (or delete the key if none was saved); if it is **not** ours → leave settings.json untouched and say so. This is ponytail's safety rule plus restoration: ponytail's uninstall "only removes the statusLine entry if it points at ponytail's own script" but never restores what the user had before the install nudge replaced it; we keep the displaced entry and put it back.

`amiral statusline mute` / `unmute`: touch/remove flag file `~/.amiral/statusline-mute` (ponytail's flag-file pattern — theirs is `~/.claude/.ponytail-active` read by their statusline; same trick, inverted meaning). **Mute suppresses good news only**: when `net_today < 0` the amber segment still prints. "Amber when a day goes net-negative, never hidden" outranks mute; documented in the command's own output so nobody is surprised.

`amiral statusline status`: prints installed/not, muted/not, cache age, and the settings scope that currently wins.

Ponytail reference, summarized — what we take and what we improve:

| ponytail | amiral |
|---|---|
| flag file read by statusline (`.ponytail-active`) | same pattern for `statusline-mute` only; *data* comes from an atomically-replaced aggregate cache, not a flag |
| setup nudge writes `statusLine` into settings.json | explicit opt-in command, parse-don't-regex, timestamped backup |
| uninstall removes entry only if it points at its own script | same guard **plus** verbatim restore of the displaced entry |
| static badge (mode name) | computed segment sourced from the same awk engine as the report; stale/negative states first-class |

### 1.6 Chaining a pre-existing statusline

If `statusline-prev.json` exists, the renderer pipes the same stdin JSON into the previous command and composes:

```sh
IN=$(cat)                                   # always consume stdin
PREV=$(printf '%s' "$IN" | sh -c "$PREV_CMD" 2>/dev/null | head -3)
SEG="⚓ +\$0.43 today · +\$12.35 net"
# fits? (COLUMNS is set by Claude Code ≥ 2.1.153)
first=$(printf '%s\n' "$PREV" | head -1)
if [ $(( ${#first} + ${#SEG} + 3 )) -le "${COLUMNS:-120}" ]; then
  printf '%s · %s\n' "$first" "$SEG"; printf '%s\n' "$PREV" | tail -n +2
else
  printf '%s\n' "$PREV"; printf '%s\n' "$SEG"   # segment becomes line 2 — officially supported
fi
```

- Two-line mode is used **only** here (or on overflow), and it is safe because the mechanism explicitly renders each printed line as a row (statusline.md, "What your script can output"). That answers "two-line only if the mechanism reliably supports it": it does, with an official cite, but 1-line stays nominal per spec v2.
- Executing the previous command is not a privilege escalation: it is the exact string the user had in `settings.json`, same trust domain, now run by our wrapper instead of by Claude Code.
- The previous command gets the *unconsumed* full stdin JSON, so existing statuslines keep working unmodified.
- `refreshInterval`: leave unset by default (our data only changes on task stop events, which also trigger renders). Document `"refreshInterval": 30` as an option for people running long background fleets where the main session idles (doc-cited use case).

### 1.7 PowerShell shape (backlog, per spec scope note — spec'd so the port is mechanical)

Same cache file, same rules; `bin/amiral-statusline.ps1`:

```powershell
$in = [Console]::In.ReadToEnd()            # consume stdin (chaining parity)
$cache = Join-Path $env:USERPROFILE '.amiral\butin-cache.tsv'
if (-not (Test-Path $cache)) { exit 0 }
$kv = @{}; Get-Content $cache | ForEach-Object { $k,$v = $_ -split "`t",2; $kv[$k]=$v }
if ((Test-Path (Join-Path $env:USERPROFILE '.amiral\statusline-mute')) -and ([double]$kv['net_today'] -ge 0)) { exit 0 }
$today = [double]$kv['net_today']
$color = if ($today -lt 0) { "`e[33m" } elseif ($today -gt 0) { "`e[32m" } else { "`e[2m" }
if ($kv['mode'] -eq 'plan') { "$color⚓ $($kv['prem_avoided_today']) prem tok avoided today · $($kv['prem_avoided_total']) total`e[0m" }
else { "$color⚓ {0:+0.00;-0.00}`$ today · {1:+0.00;-0.00}`$ net ($($kv['measured']) meas)`e[0m" -f $today, [double]$kv['net_total'] }
```

settings.json command: `powershell -NoProfile -File %USERPROFILE%\.claude\butin\amiral-statusline.ps1`. Culture note: parse with `[double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)` in the real port — the cache is C-locale data; a French Windows locale must not reintroduce the comma-decimal bug the data plane exists to prevent.

### 1.8 Edge cases

- **Collector not wired / cache absent** → empty output, exit 0 (never nag).
- **Corrupt cache** (partial keys, wrong `v`) → treat as absent. `mv` atomicity makes this near-impossible; belt and braces anyway.
- **Huge log** → renderer unaffected (never opens it); producer cost documented (§1.2); rotation is the real fix and already on the roadmap.
- **Multiple simultaneous sessions** → all render the same global cache; that is correct (the butin is a global ledger, not per-session). Session-scoped display is explicitly out of scope v1.
- **Plan/api mode flips mid-day** (via §2 config) → next collected event rewrites the cache with the new mode; the renderer follows. No restart needed.
- **Clock skew / day rollover mid-session** → `day` key is authoritative; first event after UTC midnight rebuilds today-slice from the new day. A render between midnight and the next event shows yesterday's `net_today` labeled by the cache's `day` — acceptable, self-heals on next task; not worth a timer.
- **`exceeds_200k` / rate-limit fields absent** (API-key users) → renderer never depends on stdin fields for v1 output; stdin is consumed and forwarded only.

### 1.9 Test plan (`tests/test-statusline.sh`, T-prefixed like test-butin.sh)

1. **T-S1 render, api mode**: fixture cache → exact expected line under `NO_COLOR=1`.
2. **T-S2 amber + never hidden**: `net_today=-0.12` → output contains the amber SGR and the minus; then `touch statusline-mute` → output STILL contains the negative line; positive cache + mute → empty output.
3. **T-S3 plan mode hero**: `mode plan` → premium-tokens line, no `$` amount as hero.
4. **T-S4 degraded**: no cache → empty stdout, rc 0; corrupt cache → same; stale (`generated_ts` old, log mtime new) → `· stale` present.
5. **T-S5 producer atomicity**: run two collectors concurrently 50× (fixture transcripts) → cache always parses, `v=1` present, no `.tmp.` residue; totals equal a fresh core.awk run over the final log (cache == report, the invariant).
6. **T-S6 install/uninstall roundtrip**: fake `CLAUDE_CONFIG_DIR` with a pre-existing exotic statusLine (unicode command, `padding: 2`) → install saves it byte-identical to statusline-prev.json, injects ours; uninstall restores settings.json to byte-identical original (modulo key order if python3 path; assert semantic equality then); uninstall when entry is NOT ours → settings.json untouched.
7. **T-S7 chaining**: prev command = script that asserts it received the stdin JSON and prints a marker line → composed output contains marker + segment; narrow `COLUMNS=40` → two rows.
8. **T-S8 render budget**: renderer completes < 100 ms with a 1M-line butin.jsonl present (proves it never opens the log).
9. Manual (UI-truth, per repo policy "never trust tests alone for UI"): one screenshot in Claude Code with light/dark terminal, one with a chained ponytail-style previous line.

---

## 2. Live config — `amiral-butin config`

### 2.1 Interface

```
amiral-butin config --baseline <pricing_id>     # set baseline, validated, no detection
amiral-butin config --mode api|plan             # set mode, no detection
amiral-butin config --show                      # print current config + resolved rates
```

Flags combine (`--baseline X --mode plan`). No arguments → `--show`. Exit 1 and **write nothing** on any validation failure. This is the escape hatch when `init`'s auto-detection is wrong or the situation changed mid-session (new plan, new default model) — `init`/`rebaseline` keep the detection + confirmation ceremony; `config` is direct.

File: one new arm in `bin/amiral-butin` (before the report path, alongside `init|rebaseline`). Docs: new "commands" section in `docs/butin.md` (the audit found the doc documents no subcommand at all). Tests: extend `tests/test-butin.sh`.

### 2.2 Validation & write

- `--baseline`: must be a `pricing_id` present in the active `pricing.tsv` (same resolution order as the collector: `$CLAUDE_CONFIG_DIR/butin/pricing.tsv` then repo fallback). On failure: list known ids and point at `amiral-butin add-model <id> <in> <out>` — the day-one-pricing path stays the answer for unknown models. Never accept an unpriced baseline: every future counterfactual would be silently uncomputable (unmeasured events), which is technically honest but a foot-gun this command exists to prevent.
- `--mode`: literal `api` or `plan`, nothing else.
- Write: compose full JSON (`baseline_model`, `baseline_source: "manual (config)"`, `mode`, `set_ts`) to `butin-config.json.tmp.$$`, `mv` over `butin-config.json`. Atomic — a collector reading mid-change sees old-complete or new-complete, never a torn file. (The audit notes `init` currently writes with a bare `>`; this command must not copy that, and fixing init to tmp+mv is the companion one-liner.)
- `--show` prints: baseline + its pricing row, mode, source, set_ts, pricing_version of the active table, and — when a statusline cache exists — the mode the cache last saw (drift hint if the collector hasn't run since).

### 2.3 Live semantics (why this works mid-session)

The collector re-reads `butin-config.json` **per event** (butin-collect.sh line ~55). There is no daemon and no session state: the very next SubagentStop after the `mv` prices against the new baseline. That must be stated in the command's output:

```
⚓ baseline set: claude-opus-4-8 (manual). Applies to FUTURE events only —
  history keeps the baseline it was priced with.
```

### 2.4 The future-only rule, documented everywhere it applies

The rule (stored `counterfactual_cost_usd` is immutable; re-baselining never re-prices history) already exists in code behavior and in one echo. It must appear, verbatim-consistent, in **all** of:

1. `bin/amiral-butin` `rebaseline` echo (exists, line 45) — keep.
2. `bin/amiral-butin` `config --baseline` echo (new, §2.3).
3. `docs/butin.md` new commands section (new).
4. `docs/butin-spec-v2.md` MUST list (exists: "history keeps the baseline of its time" — add `config` to that bullet).
5. `README.md` butin section, one sentence (currently absent).
6. `amiral-butin --detail` honesty block: add "Baseline changes apply to future events only; each stored row keeps the baseline it was priced with." (`--detail` is the designated honesty surface; it currently crashes on an unbound `PVER` — audit CRITICAL/HIGH — fix ships before or with this.)

### 2.5 Edge cases

- Unknown/typo'd model → rc 1, nothing written (T-C2).
- `pricing.tsv` missing entirely → rc 1 with the install-path hint (can happen on plugin-only installs, which don't ship butin — audit doc-drift finding).
- Config file absent (never ran init) → `config` creates it; `baseline_source: "manual (config)"` keeps provenance honest — the report already prints the source in its header.
- Concurrent `config` from two shells → last mv wins, both complete files; acceptable.
- `--baseline` equal to the hands model on every event → degenerate-state message already handles the display; no special case.
- Locale → `export LC_ALL=C` at script top already covers the new arm; `set_ts` is `date -u`.

### 2.6 Tests

- **T-C1** roundtrip: `config --baseline claude-opus-4-8 --mode plan` then `--show` reflects both; JSON parses; `baseline_source` is `manual (config)`.
- **T-C2** rejection: `config --baseline not-a-model` → rc 1, config byte-identical to before.
- **T-C3** future-only: collect event A (baseline sonnet) → `config --baseline opus` → collect event B (same fixture) → A's stored `counterfactual_cost_usd` unchanged in the log; B's differs; report NET equals hand-computed mix.
- **T-C4** mode flip is live: event after `--mode plan` accrues `prem_*` display path; report hero switches to premium tokens.
- **T-C5** atomicity: `config` racing 20 parallel collectors → every log line has a baseline that is one of the two valid values, never empty/torn.

---

## 3. The receipt — per-task one-liner

### 3.1 Channel analysis (where it can hook, honestly)

The natural trigger exists already: **the collector on SubagentStop is the only place that knows agent, model, real cost and counterfactual at task-end time.** The question is only the display channel:

| channel | verdict |
|---|---|
| Hook stdout (SubagentStop/Stop) | **No.** Hook stdout is not rendered in the main UI chrome (only exit-2 stderr is fed back — to the *agent*, not the user). Abusing exit 2 to display text would block task completion: disqualified. |
| PostToolUse on the Agent tool | Knows `subagent_type` from `tool_input` but gets no usage/cost (confirmed missing today: anthropics/claude-code#11008, #21837). Same stdout problem. **No.** |
| Desktop notification (osascript / terminal-notifier) | Works but interruptive, platform-specific, and precisely the spam the brief fears. **Rejected**, noted for completeness. |
| **Statusline segment** | **Yes.** Ambient, transient, zero extra processes, already fed by the collector's cache. |
| **On-demand CLI** (`amiral-butin last`) | **Yes.** For people who want the paper trail without the statusline. |

So: the receipt is a **cache field + statusline segment + CLI tail command**, not a new hook.

### 3.2 Behavior

- Collector (when `receipt` is enabled in config) composes one string per event and writes it into the cache (`last_receipt`, `last_receipt_ts` — §1.2):
  - measured, api: `grunt→claude-haiku-4-5: $0.009 (baseline $0.034, est.)`
  - measured, plan: `grunt→claude-haiku-4-5: 6.0k prem tok avoided (est.)`
  - escalated: `implementer↑claude-sonnet-4-6: escalated, −$0.012 net (est.)` — **amber, negative shown**. Receipts are estimated counterfactuals and CAN be negative; a receipt stream that only ever shows wins would be a lie by omission.
  - unmeasured: `reviewer→<model>: unmeasured (not priced — amiral-butin add-model)` — coverage gaps surface at the moment they happen, not only in the report footer.
  - brain (`--brain` Stop events): only when premium > 0: `brain (claude-opus-4-8): premium −$0.021` — the user opted into seeing costs; hiding the brain's premium while showing worker wins would bias the stream.
- Statusline renderer: if `last_receipt_ts` < 10 min old, the receipt **replaces** the totals segment for that render: `⚓ grunt→claude-haiku-4-5: $0.009 (baseline $0.034, est.)`. Next render after expiry falls back to totals. One line always.
- `amiral-butin last [-n N]` (default 5): formats the last N events from `butin.jsonl` as receipt lines with timestamps. Reads the tail of the log directly (`tail -n`, cheap), recomputes nothing — it prints the stored fields, which is exactly what the honesty rules require of stored history.

### 3.3 Spam control

- **Off by default.** `amiral-butin config --receipt on|off` (third flag on §2's command; stored as `"receipt": true` in butin-config.json).
- One receipt visible at a time (latest wins); 10-minute expiry; muting the statusline mutes receipts too (they are good-news-suppressed, negative-preserved, same rule §1.5).
- No terminal bell, no notification, no second line.

### 3.4 Honesty constraints (restated as requirements)

1. A receipt is an **estimate of a counterfactual** — every format string carries `est.`; the baseline figure is printed next to the real one so the subtraction is inspectable at a glance.
2. Negative receipts (escalations, brain premium) render in amber with an explicit minus; they may not be filtered, rounded toward zero, or expired faster than positive ones.
3. Receipt strings are composed from the same variables the collector writes to the log line — never recomputed elsewhere (one engine rule, §1.2).
4. Unmeasured events produce an "unmeasured" receipt, not silence.

### 3.5 Files & tests

Files: `adapters/claude-code/butin-collect.sh` (compose + cache write), `bin/amiral-butin` (`config --receipt`, `last` subcommand, statusline renderer segment), `docs/butin.md`.

Tests (extend test-butin.sh + test-statusline.sh):
- **T-R1** golden receipts: one fixture per class (ok/escalated/unmeasured/plan/brain-premium) → exact expected string, including the minus sign and `est.`.
- **T-R2** off by default: fresh config → no `last_receipt` key in cache.
- **T-R3** expiry: stale `last_receipt_ts` → renderer shows totals, not the receipt.
- **T-R4** `last -n 3` on a 5-event log → 3 lines, newest last, stored values only (assert equality with grep'd log fields, proving no recomputation).
- **T-R5** mute interaction: muted + positive receipt → nothing; muted + escalation receipt → amber line still prints.

---

## Cross-cutting note

All three features deliberately hang off the two files the audit already marks as the honesty chokepoints: `core.awk` (the only calculator) and `butin-collect.sh` (the only writer). Nothing in this design adds a second place where a dollar figure is computed. The audit's collector findings (wrong hook field `subagent_type` vs `agent_type`; parent vs `agent_transcript_path`; last-usage-block extraction) sit **upstream of everything here** — fix those first or the statusline will display beautifully-cached wrong numbers. See AUDIT-FABLE.md.
