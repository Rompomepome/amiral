# Changelog

## v0.13.1 - 2026-07-18
**Receipt TTL (pending is never forever) + statusline profile marker +
coverage bar.**
- **Fix: receipts could stay "pending" forever** — Claude Code
  garbage-collects subagent transcripts
  (`~/.claude/projects/…/subagents/agent-*.jsonl`) after some days; 20
  real receipts from Jul 13 pointed at transcripts that no longer exist
  and could NEVER be measured, yet the coverage line advertised "20
  pending" indefinitely — a soft false-completeness. Now a receipt whose
  transcript is ABSENT past `BUTIN_RECEIPT_TTL_HOURS` (default 48, `0` =
  expire immediately) becomes one `unmeasurable` event with reason
  `"transcript no longer on disk"`, written exactly once (idempotent via
  the existing receipt/done set) and drained from `receipts.jsonl`.
  Absent-but-young stays pending (the async flush race is minutes, not
  days); exists-but-unparseable stays pending (unchanged); an
  unparseable receipt `ts` stays pending (never guess an age). Both
  sides of the TTL boundary are tested.
- **Platform findings documented in `ports/BUTIN.md`** (load-bearing for
  ports): on this platform `agent_type` is NOT delivered in the
  SubagentStop payload — `agent_hint` was empty on all 20 real receipts
  observed; agent identity must come from the transcript's `.meta.json`
  sidecar. And subagent transcripts are GC'd, hence the TTL above.
- **New: statusline profile marker** — `⚓ ultra · +$0.43 today · …`
  shows which profile launched THIS session (`amiral` / `solo` /
  `advisor` / `fine` / `ultra` / `matelot`); marker alone (`⚓ solo`)
  when there is no money segment; no marker at all for a bare `claude`
  session. Signal is a dedicated `AMIRAL_PROFILE` variable set as a
  per-invocation prefix on each profile function's `claude` command —
  NOT inferred from `AMIRAL_BRAIN`/`AMIRAL_HANDS`, which were verified
  live to leak from the sourced `amiral.env` exports into later bare
  `claude` launches (a false "amiral on" is worse than no indicator).
  The renderer sanitizes the value (untrusted env; `^[a-z][a-z-]{0,11}$`
  or nothing). Honesty note, also in the docs: the routing POLICY is
  global (imported into `~/.claude/CLAUDE.md`) and applies to every
  session; only the PROFILE is per-session — the marker never claims
  otherwise.
- **New: coverage bar** — a 5-cell `▰▰▰▰▱` bar for COVERAGE ONLY
  (measured / measured+pending+unmeasurable — a real denominator),
  appended to the coverage parens in both api and plan modes, only when
  total > 0. Honesty rounding: 5/5 cells only at exactly 100%, floor
  otherwise, never 0 cells while measured > 0. Deliberately NO bar for
  savings: no natural maximum exists, an invented scale would be a
  fabricated number. Anchor-glyph "motion" derived from
  `generated_epoch` was considered and SKIPPED (no natural frame set for
  ⚓; movement risked reading as decoration, which the design forbids).
  Amber-on-negative-day and the mute rule unchanged and still
  unhideable.
- **Fresh-context review fixes (post-implementation):**
  - The coverage bar could paint a filled cell for ZERO real coverage:
    BWK awk's `-v` strnum rule turns `m>0` into a STRING comparison for
    a non-numeric `measured` value from a corrupted cache
    (`"corrupt" > "0"` is true), and a negative count cancels the
    denominator into a false-full bar. The renderer's CORRUPT gate now
    requires digits-only `measured`/`unmeasured`/`pending`/`esc_today`
    (they are counts by construction); a hostile cache goes silent
    (§1.8 treat-as-absent) instead of rendering a fabricated bar —
    the profile marker (session identity, not cache data) survives.
  - An id-less receipt crossing the TTL raised an uncaught `KeyError`
    (`r["id"]`), crashing the run before the atomic rewrite and wedging
    EVERY receipt in the batch forever — invisibly, since cache.sh
    swallows the exit code. Id-less receipts (un-dedupable, so no event
    may ever be written for them) now stay pending, and the rest of the
    batch processes normally.
  - `BUTIN_RECEIPT_TTL_HOURS=nan` silently meant "never expire" (NaN
    comparisons are all False); it now falls back to the documented 48.
- Batteries: 21 → 28 (butin: TTL boundary both sides, idempotence, TTL=0
  knob, unparseable-transcript regression guard, id-less no-crash,
  NaN knob) and 38 → 57 (statusline: marker sanitization/injection,
  marker-alone states, bar honesty rounding, chaining with marker+bar,
  hermetic `AMIRAL_PROFILE` isolation, hostile count values).

## v0.13.0 - 2026-07-15
**Live config (part 1) + statusline (part 2) of the DESIGN-NOTES.md v0.13
pass — the receipt (§3) is next.**
- **New: `amiral-butin config`** — the direct escape hatch for when
  `init`'s auto-detection is wrong or the situation changed mid-session
  (new plan, new default model). `--baseline <pricing_id>` and `--mode
  api|plan` set values directly, validated, no detection ceremony;
  `--show` prints the current config, its resolved pricing row, and the
  active pricing_version. Flags combine; no arguments behaves as
  `--show`. Nothing is written on any validation failure — an unknown
  pricing_id lists the known ones and points at `add-model`. The
  collector re-reads `butin-config.json` per event, so a change is live
  from the very next task — but it applies to FUTURE events only:
  history keeps the baseline it was priced with, same rule as
  `rebaseline`.
- **Fix: `init`/`rebaseline` wrote the config with a bare `>` redirect**
  (a reader mid-write could see a torn file). Now atomic: compose to
  `butin-config.json.tmp.$$`, then `mv` onto the live file — same
  pattern `config` uses. Both now also stamp `set_ts`.
- **Fix: `amiral-butin --detail` crashed** — `line 181: PVER: unbound
  variable` under `set -u` (the pricing version lives in `$PV`; `$PVER`
  was never set). `--detail` is the designated honesty surface; it now
  also states the future-only re-baseline rule explicitly.
- **New: statusline** — an opt-in, ambient line in Claude Code's own
  status bar, fed by a new O(1) cache (`~/.amiral/butin-cache.tsv`)
  written atomically by a task-event producer (`lib/butin/cache.sh`)
  that hangs off both adapters (the receipt hook and the legacy direct
  collector) plus amiral-butin's own cold pass, so the cache stays in
  sync no matter which path produced new data. The renderer
  (`bin/amiral-statusline`, plus a `.ps1` shape shipped for Windows, not
  auto-wired) never computes a number and never reads `butin.jsonl`'s
  content: every figure comes from the same `core.awk` engine the report
  uses, run twice (full log + a today-filtered slice) by the producer.
  API mode: `⚓ +$0.43 today · +$12.35 net (57 meas · 3 unmeas)`. Plan
  mode: `⚓ 2.3k prem tok avoided today · 123k total (57 meas)` — premium
  tokens, never a dollar hero, on a subscription. A net-negative day is
  amber and NEVER hidden; `amiral statusline mute` suppresses good news
  only. `amiral statusline install` backs up `settings.json`, saves any
  pre-existing statusLine verbatim, and chains it (same line when it
  fits, the row above when it doesn't); `uninstall` restores exactly
  what was displaced, or leaves a foreign statusLine untouched and says
  so; `status`/`mute`/`unmute` round out the command.
- **`measure.py` hardened for concurrent callers** — cold measurement can
  now run from multiple hooks at once (receipt hook, collector,
  amiral-butin's cold pass, the new statusline producer), so it takes
  its own lock (a lock older than 600s is reclaimed once, never wedging
  measurement forever) and rewrites `butin.jsonl`/`receipts.jsonl`
  through a PID-unique temp file + `os.replace` instead of a bare
  `open(path,"w")` — no more torn-read window for a concurrent core.awk
  pass or report. New `BUTIN_STABLE_SECS` gate (0 by default — unchanged
  behavior for existing callers): the statusline producer calls it with
  60s, so a transcript still being flushed stays pending instead of
  measuring low — the v0.11 lesson, applied to a new caller.
- Doctor: the collector-wiring check now recognizes the receipt hook too
  (`butin-collect` OR `butin-receipt`; receipt-only users previously got
  a false "not wired" warning), and gains statusline checks (wired?,
  project-scope shadow?, cache present/stale?).
- CI: syntax-checks the new/changed scripts (`bin/amiral-statusline`,
  `lib/butin/cache.sh`, `adapters/claude-code/butin-receipt.sh` — the
  last was missing from the syntax check entirely), runs the new
  `tests/test-statusline.sh` battery, and gains a **macOS job** running
  both batteries — every `stat -c || stat -f` / `date -d || date -j`
  chain previously exercised only its GNU branch in CI, while past
  audits found real BSD breaks.
- **Fresh-context review fixes (post-implementation):**
  - The H8 supersede marker carried no `ts`, so the statusline's
    today-slice kept the superseded attempt's phantom counterfactual
    credit while dropping the marker that cancels it — an escalation day
    rendered as a fabricated GREEN positive (`+$3.50 today` on a true
    `-$1.50` day), and mute could then hide the negative day entirely.
    Markers now carry `ts`; a marker whose target sits outside a slice
    stays a no-op in `core.awk`.
  - The report crashed (`syntax error` + `TOTAL: unbound variable`,
    output truncated after the hero line) whenever `receipts.jsonl`
    existed with zero pending entries — under `pipefail`, `grep -c`
    prints `0` AND exits 1, so the `|| echo 0` fallback appended a
    second `0` line. That state is routine now that the statusline
    producer drains receipts continuously. Same latent bug fixed twice
    in `amiral-doctor`.
  - The report's own cold pass now uses the same 60s stable-gate as the
    hook path — measured-once numbers are forever, so `amiral-butin`
    must not race a still-flushing transcript either.
  - Renderer parse is matched by KEY, never by position (an absent cache
    key silently shifted every later field — wrong numbers on screen),
    tolerates CRLF, normalizes IEEE negative zero (`+$-0.00`), clamps
    sub-cent rounding noise so a `-$0.003` residual isn't shown as an
    amber loss, and rejects `COLUMNS=0`.
- **Adversarial pre-mortem fixes (corsaire):**
  - **Integrity-pin the displaced statusline.** `statusline-prev.json` /
    `statusline-prev-cmd` live in `~/.amiral` at the user's own perms,
    outside the workspace-trust boundary Claude Code enforces on
    `settings.json` — yet the renderer *executes* the saved command every
    render and `uninstall` writes the saved object back into
    `settings.json`. Anything running as the user (a prompt-injected
    subagent with Bash, a poisoned dependency) could rewrite either and
    turn "can write a file" into recurring native code execution that
    outlives amiral. Both files are now written `0600`, hashed at install,
    and re-verified before use: the renderer refuses to chain a
    tampered/un-pinned/group-writable command, and `uninstall` refuses to
    restore a poisoned object (removes the key and warns instead).
    Tamper-*evident*, the same model `amiral-trust` uses for `verify.sh`.
  - **Renderer caps a chained command at 2s in pure bash** — stock macOS
    has no coreutils `timeout`, so a slow/hung previous statusline used to
    block the render with no cap.
  - `settings.json` symlink (dotfiles via stow/chezmoi) is written
    *through* now, not silently replaced by a plain file; the backup is
    taken only when an edit can actually happen (no false "nothing
    changed"), `rm -f`'d before `cp` (no write-through a planted symlink),
    and `chmod 600`.
  - Producer no longer wedges forever on a non-directory at the lock path
    (sync-tool artifact / planted symlink); `PENDING` excludes receipts
    already measured in the log, so a crash between `measure.py`'s two
    atomic renames can't display the same task as "1 meas · 1 pending".
Battery: 21/21 butin + 38/38 statusline.


## v0.12.2 - 2026-07-13
- **The brain was triple-counted.** The Stop hook fires once per turn, and
  every receipt points at the same growing main transcript — so a session
  with N brain turns produced N near-identical brain events, inflating the
  total. Cold measurement now keeps ONE brain event per session (a newer
  measurement supersedes the older one); worker subagents, each with a
  distinct transcript, are unaffected. Verified: 3 Stop receipts -> 1
  brain event, idempotent on re-run.


## v0.12.1 - 2026-07-13
- **Coverage told a contradiction: "6/6 measured" while 2 tasks were
  pending.** The total ignored pending receipts, so a full-coverage stamp
  sat next to "2 awaiting measurement" — exactly the false-completeness
  the design forbids. Coverage now counts pending in the denominator and
  names them: "2/4 measured · 2 pending". Measured, pending, and
  unmeasurable are all surfaced, honestly.


## v0.12.0 - 2026-07-13
**The butin is rebuilt on a correct foundation.** v0.11 measured inside
the hook, while the transcript was still streaming. Two adversarial
audits and a real session proved what that produced: the same
`message.id` is written up to 6x, so summing every usage line
over-counted by **6.7x** on a live transcript (739,146 vs 110,424 real
output tokens). No amount of patching fixes measuring a file that is
still being written.

**New architecture — capture and measurement are separated:**
- **The hook writes a receipt** (`butin-receipt.sh`): which agent, which
  session, where its transcript will be. No parsing, no arithmetic,
  nothing that can race.
- **`amiral-butin` measures cold** (`lib/butin/measure.py`), on stable,
  finished files:
  - **Dedup by `message.id`** — a streaming turn appears many times; only
    its last record holds the final totals. This kills the 6.7x.
  - **Identity from the platform's own sidecar** (`.meta.json` →
    `agentType`), so a worker is never a nameless "worker" fallback.
    (Observed: the sidecar correctly said `corsaire` where the hook hint
    said `grunt` — the sidecar wins.)
  - **Pending, never invented** — a transcript not yet flushed keeps its
    receipt pending and is measured on the next run. Coverage reports
    measured / pending / unmeasurable, honestly.
  - **Reproducible** — the same receipts and transcripts always yield the
    same number; re-running is idempotent. Anyone can re-run the
    measurement and check it. No hosted service can offer that.
Six classes of bug (async race, streaming double-count, partial-file
reads, phantom escalations, retroactive markers, false coverage) become
structurally impossible rather than individually patched.

**Wiring changed** — see docs/butin.md; the old collector hook is
superseded. If you ran any earlier butin, archive `butin.jsonl`: its
numbers are fabricated. The journal/attestation hardening (forgeable
Verified, empty attest on --amend, cross-repo route leak) is still open —
do not publish numbers or badges from it yet.


## v0.11.0 - 2026-07-11
**Correctness release. The butin in v0.9-v0.10.1 measured nothing real —
this fixes that.** An adversarial audit (dogfooded: amiral auditing
amiral) proved on a live machine that the collector read hook fields
SubagentStop never delivers, so every event was misattributed. If you
ran the collector before now, your butin.jsonl is fabricated — archive
it and start fresh after installing this.

Blockers fixed (each now covered by a test on REAL transcript fixtures,
so a regression fails CI):
- **C1 — the collector never measured a worker.** It read `subagent_type`
  and `transcript_path`; SubagentStop delivers `agent_type` and
  `agent_transcript_path` (the latter is the subagent's own transcript;
  `transcript_path` is the *main session's*). Every event was logged as
  agent `"worker"`, priced from the brain's tokens at the brain's model.
  Now reads the correct fields; real agent names and models appear.
- **C2 — model decoupled from tokens.** The model was grepped globally
  with `tail -1`, independent of the usage line. Now taken from the same
  assistant message that carries the tokens.
- **H10 — only the last turn was billed.** A multi-turn subagent was
  undercounted 40-60%. Now sums every usage block in the transcript.
- **H8 — a failed cheap route booked a profit.** The wasted attempt kept
  its counterfactual credit while only its cost was charged, flipping a
  loss into a fabricated gain for every model pair. Now the failed
  attempt is superseded (excluded from both sides); only its wasted real
  cost is charged. A failed route is a measured loss.
- **C3 — scientific notation parsed as its mantissa** (1.5e-2 → 1.5, a
  100x error waiting for any Python/JS adapter). Parser now handles eE.
- **C4 — a corrupt state file silently deleted the event.** Now the epoch
  field is validated; a bad state file never loses data.
- **C7 — a missing newline merged two events, and coverage still said
  "complete."** The merged record is now counted as corrupted, so lost
  data surfaces instead of being certified absent.
Also: per-session state uses a PID-unique temp name (H7), double
`pricing_version` removed (M9). Fixtures rewritten to the real Claude
Code transcript schema. The journal/attestation hardening (H2/H3/H4/H9,
forgeable Verified, cross-repo leak) lands next in v0.11.1 — until then,
do not use `amiral-journal flag` or `--with-cost` to publish numbers.


## v0.10.1 - 2026-07-09
Completion pass — everything decided in the three review passes is now
either shipped or explicitly on the recorded roadmap (docs/butin-spec-v2.md):
- **`amiral-butin init` / `rebaseline`**: first-run config with baseline
  auto-detection, the frontier-baseline confirmation (the Fable trap —
  an auto-detected frontier baseline would inflate savings forever),
  atomic write. History keeps the baseline of its time.
- **Escalations are real now.** Conservative heuristic in the collector:
  same session, cheaper→pricier within 15 min (grunt or same agent) →
  the wasted cheap attempt is charged AGAINST amiral. May over-penalize;
  never inflates.
- **`--haircut=N`**: display-time conservative reduction of the
  counterfactual; the decomposition bias (each worker re-reads context)
  is named in --detail.
- **Degenerate-state message** when brain = hands = baseline: "the butin
  measures cost, not quality."
- **`pricing_version` stamped on every event**; report warns when the
  table is >3 months old; refresh is manual-only (nothing phones home).
  Unknown future schema versions are skipped and counted, never crashed.
- **Journal `note` mode**: same provenance block as a git note (ref
  `amiral`) — survives squash-merges. Funnel wired: savings → butin →
  report. Doctor: last-event age + collector-wired check. README gains
  the "Prove it" section + fleet table rows (butin, journal, FLEET.md);
  POSIX-only scoping stated; FR parity.
Battery: 16/16 (was 9).


## v0.10.0 - 2026-07-09
The accountability release: route smart, verify everything, prove it in git.
- **Butin hardened (critical path).** A real collector (SubagentStop →
  worker events; Stop --brain → brain event) with COVERAGE: unextractable
  tokens become "unmeasured" events, never invented numbers. LC_ALL=C
  everywhere data is written (a French locale writing 0,01 corrupted the
  whole log — fixed by rule). Atomic single-write lines (<PIPE_BUF) with
  event ids + read-time dedup. Cache priced as cache, category by
  category. Brain premium = max(0, real−counterfactual): a penalty,
  never a credit. `verified` flows from the verify gate into events.
  Golden transcript fixture + 9-test battery in CI.
- **Journal de bord (new ship).** `amiral-journal enable` = per-repo git
  hook adding provenance trailers: Amiral-Route, Amiral-Verified, and
  Amiral-Attest (sha256 of verify.sh + staged diff — recomputable by
  anyone; forging it means actually running the gate). Cost trailer is a
  separate opt-in with a public-remote warning. `flag` prints the
  pavillon badge — and refuses under 20 measured tasks. FLEET.md
  template: AI-policy-as-code, committed and changed by PR, read by the
  routing policy when present.
- **GPT-5.6 day-one support + model-churn resilience.** Verified prices
  for gpt-5.6-sol/terra/luna (source: openai.com, GA 2026-07-09; new
  cache rule 1.25x write / 0.10x read) in the table. New
  `amiral-butin add-model`: price any new model yourself the day it
  ships — no repo release needed. Unmeasured tasks now NAME their model
  in the report with the add-model hint (silence turned into action).
  Codex port maps the family: brain=sol, hands=terra, grunt=luna.
- **Doctor** gains a butin section (log present, coverage, collector
  errors). Spec v2 decisions recorded in docs/butin-spec-v2.md
  (MUST/SHOULD/roadmap/refused — la vigie, le cap, Fleet Events).
Not a framework. A fleet of small ships — board only what you need.


## v0.9.0 - 2026-07-08
- **New: butin (savings) — amiral proves its own ROI.** `amiral-butin`
  reads your actually-routed tasks and shows a counterfactual saving:
  the SAME tokens priced at your baseline model vs the cheap model amiral
  chose. The number shown is NET — escalations and failed cheap routes
  are counted AGAINST amiral (a bad route can make a task net-negative,
  by design). 100% local, no account, no network.
  - **Portable architecture (3 layers, like amiral itself):** a universal
    core (lib/butin/, zero harness dependency — proven by a mock-adapter
    test on gpt-5 vs gpt-5-mini), a port contract (ports/BUTIN.md), and a
    claude-code adapter (adapters/claude-code/). Adding Codex/OpenCode
    later touches only a new adapter, never the core.
  - **Subscription mode (the cliff angle):** on Pro/Max the hero metric is
    premium tokens avoided (measured, not estimated), not abstract
    dollars — your real currency is the quota. API-equivalent value shown
    as secondary. Never converts tokens to "% of window" (Anthropic's
    limit formula isn't public — we show what we measure, never guess).
  - Multi-provider price table from day one (Anthropic, OpenAI, Google,
    Mistral), refreshable but offline-safe.
  - Honesty is in the design: baseline + its source, the "API-equivalent
    value" label, and escalation costs are shown, not hidden.
  This is v0.1 of the butin (SPEC §7): core + port + one adapter +
  `amiral-butin` command. Statusline and weekly HTML digest come next.


## v0.8.3 - 2026-07-08
- Added IDEAS.md: a feedback log capturing suggestions from real
  conversations (context optimization / governed retrieval from Krishna
  Challa of MonkDB; token-efficiency framing from Venugopala Kotipalli;
  the harness-optimizer landscape around Tokenade/THOL). Each with an
  honest note on whether it fits amiral's line. Roadmap follows terrain,
  not guesses — an idea graduates to a build only when it also draws
  community votes on an issue, and only if it stays within the line
  (markdown discipline, nothing hosted).


## v0.8.2 - 2026-07-08
Honesty & consistency audit (every page re-read):
- **BENCHMARKS.md rewritten.** The "seeded soon" promise is gone —
  replaced by a Results table with what actually exists: Anthropic's
  cookbook reference numbers and the author's observed session ($4.84,
  $4.51 frontier-only, Claude Code's own "75% subagent-heavy" panel).
  New section documents the two contamination traps that invalidated the
  author's first A/B attempt (global policy leaking into the naive run;
  memory recognizing the task) and the corrected protocol. Community
  rows land via amiral-report in issue #3.
- **"6 markdown files" was false since v0.7** (advisor made it 7).
  Fixed in README and landscape. Precision is the positioning.
- how-it-works: five agent files, advisor documented.
- Roadmap deduplicated; dead promises removed; open items now link to
  votable issues #1 (auto-effort) and #2 (Aider port).
- CONTRIBUTING + quota-report template point to amiral-report.
- PATTERN.md gains the two wirings (orchestrator / advisor) as a
  universal principle. README.fr catches up (5 agents, advisor, savings,
  report).


## v0.8.1 - 2026-07-08
- **Fix: hero image reference.** The README pointed at amiral-hero.png
  while the shipped asset is amiral-hero.jpg (a local jpg conversion got
  overwritten during the v0.8.0 sync) — the hero was broken on the repo
  page. Now .jpg everywhere.
- README scannability pass (inspired by the best-presented CLI repos):
  a quick-links row under the badges (Get started · Two shapes · Savings
  · Benchmarks · Ports · How it works · Français) and a "Main takeaways"
  block of one-liners right after the demo, so a visitor gets the whole
  pitch in five seconds.


## v0.8.0 - 2026-07-07
Four additions, all inside the "discipline, not a runtime" line — no
server, no proxy, nothing to host:
- **amiral-report**: community benchmarks WITHOUT telemetry. A local
  wizard packages the user's own numbers into a BENCHMARKS.md row and a
  prefilled public GitHub issue they review and post themselves. Nothing
  is ever sent automatically — there is no endpoint. Consent by design;
  the data lands in the open where it helps everyone. (README gains an
  explicit "No telemetry, ever" design principle.)
- **amiral-savings**: a local cost estimator. `amiral-savings --tokens 5
  --brain fable --hands sonnet --plan 20` prints all-frontier vs amiral
  cost and your savings. Pure math, editable price table, honest "this is
  an estimate, measure real numbers with BENCHMARKS.md".
- **Codex port** (`ports/codex/`): run amiral's discipline with Codex via
  the AGENTS.md standard, including using Codex AS the corsaire — an
  adversarial second opinion on a different model family. (Answers the
  most-asked question after launch.)
- **OpenCode port** (`ports/opencode/`): the brain/hands split on
  OpenCode's 75+ providers. The pattern on any model OpenCode can reach,
  via config, not a bridge.
- **The advisor follows your brain — Fable-ready everywhere.** The
  advisor agent's model is now aligned to your chosen brain by
  amiral-setup (and checked by the doctor). Pick "credits" at setup and
  `amiral-advisor` gives you the exact shape Anthropic benchmarked:
  Sonnet executor + Fable advisor. Every shape (orchestrator, advisor,
  loop, savings) now runs with Fable as the brain via one setting.
- **Autonomous-loop guide** (`docs/autonomous-loop.md`): how to drive
  amiral in a Ralph-style loop safely — dedicated worktree, verify.sh as
  the stop condition, corsaire still in the path, capped spend.

The through-line: amiral stays 6 core files with no engine. "Works on all
LLMs" means the discipline is *portable* to the tools that reach them
(Codex, OpenCode, Aider, Cursor...) via an open standard — not a gateway
we host. That restraint is the moat.


## v0.7.0 - 2026-07-07
- **New: advisor mode.** `amiral-advisor` runs you on the cheap model the
  whole time and consults the expensive brain (new `advisor` agent) only
  for hard calls — plan review, risky architecture, real tradeoffs, or
  when stuck. This is the "executor + on-demand advisor" shape, alongside
  the existing orchestrator shape. The policy routes hard judgment calls
  to the advisor automatically. Fleet is now 5 agents.
- **Anthropic's own numbers, cited.** README and BENCHMARKS now reference
  Anthropic's "plan big, execute small" cookbook: a reference run at
  ~$1.61 team vs ~$4 all-frontier (~2.5x cheaper, ~3x faster, 80%+ tokens
  at worker rate) — with the honest caveat that these are Anthropic's
  figures, not independently replicated, and your ratio depends on your
  task. Solves the "no benchmarks" gap by citing a real, linkable source
  instead of unverified numbers.
- Fable metering cliff dates updated: Anthropic extended inclusion
  through July 11 (was July 7); credits-only from July 12.


## v0.6.5 - 2026-07-07
Documentation cleanup pass (post-launch tidy):
- Fixed install.sh final message: it still said AMIRAL_BRAIN "default
  fable" — the default has been Opus since v0.6.1. Now reads "default
  opus" so nobody panics about the July 7 metering.
- Removed the obsolete geometric assets (architecture.svg,
  admiral-character.svg) replaced by the hero illustration; dropped the
  old diagram image from the README.
- quota-math: Opus stated as the default brain (not an "alternative").
- how-it-works: documents the first-run setup (amiral-setup) and the
  Opus-default behavior.
- Verified: no broken internal links, docs aligned with current
  behavior (one-word usage, Opus default, first-run setup, 4 agents).


## v0.6.4 - 2026-07-07
- Added the amiral hero illustration (assets/amiral-hero.png) to the top
  of the README — an original ligne-claire old-sea-dog admiral in a
  brass porthole, matching the maritime brand.
- Demo GIF finalized (assets/amiral-demo.gif, ~1MB): one word, the
  admiral triaging and fixing a task inline.


## v0.6.3 - 2026-07-06
- Added a terminal demo GIF (assets/amiral-demo.gif) to the top of the
  README: one word, then the admiral triaging a trivial fix inline and
  delegating a real feature, verified end to end. Recorded with
  asciinema, rendered with agg.


## v0.6.2 - 2026-07-06
- **First-run plan setup, asked once.** The first `amiral` asks which
  plan you're on (Pro/Max/credits) and pins the best in-plan brain to
  ~/.claude/amiral.env — then never asks again. New `bin/amiral-setup`
  (re-runnable), loaded by the shell profiles; the installer runs it and
  copies it. Keeps the one-word experience while making the model choice
  explicit up front, as requested.
- README documents the first-run prompt, and answers "can the admiral
  call GPT/Gemini?" honestly: not natively (subagents are Anthropic
  models); use the portable AGENTS.md layer on a multi-provider tool
  (OpenCode/Aider/Codex) instead of bolting a gateway onto amiral.
- doctor shows whether first-run setup has been done.


## v0.6.1 - 2026-07-06
- **Default brain is now Opus, not Fable.** Most users are on Pro
  (Sonnet) or Max (Opus); the free tier has no Claude Code, and Fable
  is metered on subscriptions after July 7. The default now works
  inside the plans people actually have: brain=opus (included on Max;
  Pro serves Sonnet within-plan), hands=sonnet. No credits, no config.
- New `amiral-solo`: all-Sonnet fleet, lightest footprint on a Pro plan.
- Fable is now an explicit opt-in premium planning brain
  (`AMIRAL_BRAIN=fable amiral`), not the default. amiral-ultra still
  uses the frontier brain by default (it's the premium-audit tool).
- doctor and README reframed around "works on the plan you already have".


## v0.6.0 - 2026-07-06
- One-word usage. `amiral` is now the single command you need: type it
  and just talk. The policy makes the admiral triage every task by
  complexity and route it itself - trivial work done inline, mechanical
  work to Haiku, real features to Sonnet (implementer), risky changes to
  the corsaire, always verified before "done". Users never pick a model,
  effort, or agent.
- Variants (amiral-fine, amiral-ultra, matelot) and /plan-ship are now
  explicitly optional power-user tools, not the default path.
- README leads with zero-config "one word" usage.
- Note: model choice at launch is inherently a shell concern, so one
  embark word is the floor; after that the admiral handles everything.


## v0.5.4 — 2026-07-06
Security & robustness pass — findings from running our own corsaire
agent against the repo (dogfooding the adversary):
- **CRITICAL fix**: the SubagentStop hook would run ANY repo's root
  ./verify.sh with full privileges (booby-trap vector). Now it refuses
  untrusted verify.sh entirely; opt in per-repo via `amiral-trust`
  (checksum-pinned = tamper-evident) and execution is wrapped in a 300s
  timeout. New `bin/amiral-trust`; CI proves untrusted scripts don't run.
- install.sh now backs up any pre-existing agent/skill before
  overwriting (timestamped .amiral-bak), matching the CLAUDE.md behavior.
- uninstall.sh: only removes our own skill file then rmdir-if-empty
  (no more nuking a shared skills dir); no longer claims to remove a
  CLAUDE.md import that wasn't there; flags leftover backups.
- install.sh: rc-append is now grep-guarded (truly idempotent).
- doctor reports hook-trust status for the current repo.
- Noted `amiral-auto-effort` on the roadmap (per-task effort selection),
  pending Anthropic's own `auto` effort maturing.


## v0.5.3 — 2026-07-06
- Fix verify-nextjs.sh (found during real dogfooding): it ran a global
  `npx tsc` that fails when TypeScript isn't globally installed. Now it
  prefers the project's own package.json scripts (typecheck/lint/build),
  falls back to the LOCAL tsc via `npx --no-install`, and skips
  gracefully with a message when a step is absent. Adds yarn detection.


## v0.5.2 — 2026-07-06
- **Wired the corsaire into the system** (it was decorative): the
  routing policy now sends security-sensitive / high-risk / vibe-coded
  changes to the corsaire, and /plan-ship runs it in the review step
  for those surfaces. PATTERN.md gains the adversarial-pass principle.
- Policy and plan-ship now prefer `./verify.sh` when present (aligns
  the Claude Code policy with the portable discipline).
- README: mascot on the repo page + "Try it in 5 minutes" copy-paste
  quickstart ending on your first benchmark data point.
- SECURITY.md: private disclosure channel, scope notes.
- doctor: checks the current project for a verify.sh done gate.


## v0.5.1 — 2026-07-03
- Post-corsaire consistency pass: marketplace description, how-it-works
  and the doctor now count 4 agents (the doctor had escaped the sweep —
  no .sh extension). Note: the "6 markdown files" claim is now exactly
  true (policy + 4 agents + skill).
- Social preview: proper French accents and typographic apostrophes
  (modèle, découpe, exécutent, VÉRIF).


## v0.5.0 — 2026-07-03
- **New fleet member: the corsaire** — licensed adversary. Pre-mortem
  (Klein) applied to code: assumes the feature already failed in
  production, works backward through 6 attack surfaces (inputs, state,
  auth, data, edges, dependencies). Severity x likelihood ranking,
  concrete mechanisms only, plain-language verdict. Built for risky
  and vibe-coded changes; read-only. The reviewer checks the work;
  the corsaire hunts the future failure.
- Redrawn admiral character: organic ligne-claire style (3/4 view,
  wind-blown beard, tilted cap, squinting eye) replacing the geometric
  mascot. Original design.


## v0.4.4 — 2026-07-03
- New social preview: original old-sea-dog admiral character (flat
  comic style, porthole frame) + a clear 3-step schema in Montserrat.
  Original design — not derived from any copyrighted character.
- assets/admiral-character.svg: the character source, reusable for
  README, posts, stickers.


## v0.4.3 — 2026-07-03
- Coherence sweep: purged 5 stale profile names (fable-fine,
  sonnet-fast) from quota-math, how-it-works and the quota-report
  template, including one leftover env-var mention contradicting the
  v0.4.2 effort fix. Automated link check: all internal links valid.
- assets/social-preview.png (1280x640): launch asset for GitHub social
  preview and link shares.


## v0.4.2 — 2026-07-03
- **Fix a silent token leak in our own profiles**: CLAUDE_CODE_EFFORT_LEVEL
  takes precedence over agent frontmatter, forcing every worker
  (including the low-effort grunt) to think at xhigh. Profiles now use
  the `--effort` flag (session level, overridable by frontmatter):
  brain at xhigh, grunt at low, as designed. Fixed in bash and
  PowerShell profiles, documented in how-it-works.
- amiral-ultra: caution note — verify in /agents that dynamic-workflow
  workers honor the hands model before trusting a big run.


## v0.4.1 — 2026-07-03
- **July 7 cliff documented** (Anthropic official terms: Fable included
  in subscriptions only through July 7; usage-credits only after, no
  auto-fallback). README section, doctor warning, quota-math update.
- Reframed economics: metered Fable brain + cheap hands is the
  pattern's strongest case; `AMIRAL_BRAIN=opus` is the pure-subscription
  fleet.
- Nuanced the "works on your subscription" claim accordingly.


## v0.4.0 — 2026-07-03
- **Three-layer split**: universal pattern -> portable discipline ->
  Claude Code reference implementation.
- `PATTERN.md`: CLI-agnostic spec with honest prior art (Aider
  architect/editor, Roo modes, opusplan) and an implementation map per
  CLI, including the "you are the amiral" degraded protocol.
- `ports/AGENTS.md`: the **matelot discipline** in the AGENTS.md open
  standard (Linux Foundation) — one file, readable by 25+ tools (Codex,
  Aider, OpenCode, Cursor, Gemini CLI, Copilot, Zed, Warp...). The
  amiral is Claude Code-specific; the matelot is universal.
- `ports/README.md`: ports philosophy — we document ports, we do not
  maintain runtimes for other CLIs.


## v0.3.0 — 2026-07-03
- `amiral doctor`: automated fleet health check (install, version,
  routing config, silent-fallback detection guidance).
- Optional `SubagentStop` verification hook: workers cannot finish while
  `./verify.sh` fails. Policies ask; hooks enforce. Opt-in, documented
  caveats (docs/hooks.md).
- `docs/landscape.md`: honest positioning vs Ruflo (API-only, blocked on
  Pro/Max), ClaudeFast Code Kit, Claude Octopus, Maestro, opusplan.
  "Not a framework" section in README.
- Repository URLs finalized (github.com/Rompomepome/amiral).


## v0.2.0 — 2026-07-03
- **Renamed to amiral** (was fable-lean): the pattern is
  orchestrator/worker, not one model. The admiral doesn't row.
- Configurable fleet: `AMIRAL_BRAIN` / `AMIRAL_HANDS` env overrides —
  survives model suspensions (Fable was suspended once already) and
  renames. Aliases became functions (arg passthrough).
- Plugin packaging: `.claude-plugin/plugin.json` + `marketplace.json` —
  installable via `/plugin marketplace add` + `/plugin install`.
- Restructure: `agents/` and `skills/` at repo root (plugin layout),
  `.claude/` mirrors kept for open-the-repo dogfooding, CI sync check.
- Safe permissions by default (no bypass flag shipped, CI-enforced),
  `docs/permissions.md` documents the full speed/safety spectrum.
- Windows: PowerShell profiles.
- `templates/verify-nextjs.sh` machine-verifiable done gate.
- `BENCHMARKS.md`: reproducible A/B/C protocol (ccusage-based).
- CI: syntax, fresh install, idempotence, CLAUDE.md preservation, clean
  uninstall, dogfood sync, manifest JSON validation, no-dangerous-flags.

## v0.1.0 — 2026-07-02
- Initial release as fable-lean: policy + 3 worker agents + /plan-ship
  + shell profiles + idempotent installer.
