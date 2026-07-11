# AUDIT-FABLE-V2 — targeted re-audit of amiral v0.11.0

Branch `audit/v0.10.1`, HEAD `5a18208` ("v0.11.0 correctness — C1/C2/H10/H8/C3/C4/C7"), 2026-07-11.
macOS 26.5.1 (BSD userland, `/bin/bash` 3.2.57). Read-only audit: no repo file was modified except this one. All attacks ran against a scratch `AMIRAL_HOME`; the user's real `~/.amiral` was inspected read-only and never written.

Scope: **not** a full re-scan. Two focused parts, as commissioned.
- **Part A** — do the v0.11.0 fixes (C1/C2/H10, H8) hold under attack on *real* data?
- **Part B** — do the five unfixed provenance findings (H2/H3/H4/H9/C6) still reproduce on v0.11.0?

Evidence tags: `[self-reproduced]` = I ran it and observed the output this session; `[docs-confirmed]` = verified against the official Claude Code hooks documentation; `[real-data]` = observed in the user's actual `~/.amiral` logs and `~/.claude` transcripts from a live v0.11.0 run; `[corsaire-confirmed]` = independently re-derived and re-run from scratch by a separate adversarial pass.

Method: every Part A verdict below was produced twice — once by my own battery against the real logs, once by an independent adversarial pass that rebuilt its own fixtures rather than trusting the write-up. The two agree on every verdict; where the second pass narrowed or corrected a hypothesis it is noted. Part B was confirmed the same way. This is the three-way standard the v1 audit set.

---

## TL;DR verdict

The v0.11.0 field-name fix was **correct and real** — on live data the collector now resolves agent names (`implementer`) and the worker's own model (`claude-sonnet-5`), which v0.10.1 never did. But it **did not make the butin trustworthy**, and in one respect made it worse:

- **C1 — partially holds.** Agent name resolves *when the payload carries `agent_type`*; when it doesn't, it silently invents `"worker"`. Both happened in the same real session.
- **C2 — holds.** Model is taken from the usage-bearing lines; the worker's model is billed, not the brain's. Confirmed on real data.
- **H10 — BREAKS on real data.** "Sum every usage block" double-counts streaming transcripts, which write the *same* assistant turn on multiple lines. On the one real measured event, cache-write tokens are over-counted **1.96×**; in a controlled faithful case the reported net saving is inflated **1.93×**. The fix traded a systematic *undercount* for a systematic *overcount*, in the direction that flatters the headline.
- **H8 — holds for the straight sequential case, breaks at the edges.** A forced cheap→escalate books a loss (correct). But the correction is order-dependent (a reordered/rotated/torn log flips net to a **profit**, resurrecting the original H8), non-idempotent (a double marker corrupts every sum), and the test suite doesn't exercise the real collector's code path at all.
- **worker/unmeasured — root cause found: the documented async-transcript race.** `agent_transcript_path` can reference a file not yet flushed (or never materialized) when `SubagentStop` fires; the collector hard-depends on reading it and ignores the field the docs provide for exactly this case (`last_assistant_message`).

Part B: **all five findings reproduce unchanged on v0.11.0.**

**Is the butin math now safe to trust on real data? No.** (Full reasoning at the end.)

---

# PART A — do the fixes hold?

## A1 — C1 / C2 / H10 (agent name, worker model, all turns)

### The documented schema (settles the v1 dispute) · [docs-confirmed]

The official hooks docs (`code.claude.com/docs/en/hooks#subagentstop`) confirm `SubagentStop` **does** deliver `agent_type`, `agent_transcript_path`, `agent_id`, and `last_assistant_message`, and that `transcript_path` is the *main* session while `agent_transcript_path` is *the subagent's own transcript* in a nested `subagents/` folder. So the v0.11.0 switch from `subagent_type`/`transcript_path` to `agent_type`/`agent_transcript_path` (`butin-collect.sh:33-34`) is **correct**. `subagent_type` is documented only as a field of the Agent tool's `tool_input`, never of `SubagentStop` — the v0.10.1 code was reading a field that structurally does not exist on that event.

Proof it changed behavior on real data: the pre-fix log (`~/.amiral/butin.jsonl.BROKEN-c1`) contains only `brain` (6) and `worker` (9) — never a real agent name. The first v0.11.0 run (`~/.amiral/butin.jsonl.v11-firstrun`) contains a correctly-named, correctly-modelled subagent event:

```
{"agent":"implementer","chosen_model":"claude-sonnet-5","tokens":{"in":10,"out":538,"cache_read":34936,"cache_write":27291},...}
```

### C2 — VERDICT: HOLDS · [self-reproduced] [real-data]

The model is now extracted from the assistant lines that carry `usage` and kept together with the running token sums (`butin-collect.sh:47-59`), not from a global `tail -1`. On the real event above, the worker's model (`claude-sonnet-5`) was billed — not the session brain's `claude-opus-4-8`, and not the main transcript's last model string. A faithful scratch payload with `agent_type:"grunt"` and a `claude-sonnet-5` transcript logs `"chosen_model":"claude-sonnet-5"`. C2 is fixed.

### C1 — VERDICT: PARTIALLY HOLDS · [self-reproduced] [real-data]

`agent` resolves to the real name when the payload carries `agent_type` (`implementer`, above). But the fallback is still an invented bucket: `[ -z "$AGENT" ] && AGENT="worker"` (`butin-collect.sh:35`). In the **same real session**, a second subagent event resolved neither its name nor its tokens:

```
{"agent":"worker","model":"unknown","unmeasured":true}
```

So C1 is fixed *in principle* (correct field, correct name when present) but the defense is incomplete: there is no use of `agent_id` (which the docs say is always present on `SubagentStop`), so when `agent_type` is absent the event collapses to a nameless `"worker"` that is indistinguishable from a real agent literally named worker and carries no stable identifier. Root cause of that specific event is analysed in **A3**.

### H10 — VERDICT: BREAKS ON REAL DATA · [self-reproduced] [real-data] · **new CRITICAL (V2-C1)**

The v1 fix replaced `grep '"input_tokens"' | tail -1` (last turn only) with an awk pass that sums **every** line matching `/"usage"/ && /"input_tokens"/` (`butin-collect.sh:48-58`). On real transcripts this **double-counts**, because Claude Code streams: the *same* assistant turn (same `message.id`) is written to the JSONL on more than one line — a partial and a final.

Direct evidence from the real subagent transcript that produced event #1 (`~/.claude/projects/.../subagents/agent-a76aaa6ac002ffe8a.jsonl`):

```
distinct message ids among the 6 usage lines:
  2 × "id":"msg_011CcvYWck9oi6XTaLiVWhKv"     ← one logical turn, logged twice
  2 × "id":"msg_011CcvYWNXt4t1v7tNbU3xat"     ← one logical turn, logged twice
  1 × "id":"msg_011CcvYXpsgWcmGwchBBw93e"
  1 × "id":"msg_011CcvYYS9j4SPH62PJAeKY3"
```

4 logical turns, 6 usage lines. Running the collector's own extractor over that file:

```
NAIVE (collector sums all lines): in=12 out=747 cache_read=48791 cache_write=27418
DEDUP (one per msg id, final):    in=8  out=744 cache_read=38041 cache_write=13982
cache_write over-count: 1.96×    cache_read over-count: 1.28×
```

`input_tokens` is only ~2 per turn here (virtually all context is cached), so the cost is driven almost entirely by `cache_read`/`cache_creation` — exactly the categories the double-count inflates. Controlled faithful case, opus baseline, two turns each duplicated:

```
TRUE dedup:      in=4 out=300 cache_read=10000 cache_write=15000
collector logged:in=8 out=310 cache_read=20000 cache_write=30000
reported net saved = 0.492696  |  true net saved = 0.255048  |  inflation = 1.93×
```

An independent pass reproduced the same mechanism from a different fixture (4 turns, 2 duplicated, engineered to the same dedup cache-write of 13982) and measured **+77.5%** inflation on both `real_cost` and `counterfactual` for a single event — converging with the real-data 1.96× and the controlled 1.93× on the same conclusion: reported dollars run roughly **1.8–2× true** on the normal shape of a real transcript. Because the double-count multiplies the token vector before *both* `real_cost` and `counterfactual_cost` are computed, every downstream dollar figure — real, counterfactual, **and net saved** — is inflated by roughly the duplication factor. This is the single most damaging Part-A finding, confirmed three ways: the fix meant to *increase* accuracy now systematically **overstates the savings the whole project exists to report honestly.**

Separately, the logged event #1 (`in=10 out=538 cr=34936 cw=27291`) matches **neither** the naive sum **nor** the dedup total of its own source transcript — because at hook time the file was still being written (see A3). The measured number is not a faithful measurement of anything.

---

## A2 — H8 (a failed cheap route must be a loss, never a profit)

### Straight sequential case — VERDICT: HOLDS · [self-reproduced]

Forcing the collector's own heuristic (not a hand-written ledger): E1 = `grunt`/`claude-haiku-4-5`, then E2 = `grunt`/`claude-sonnet-4-6` in the same session within 15 min, with baseline = `claude-sonnet-4-6` (so the escalation target equals the baseline and earns zero counterfactual credit). The collector wrote E1 (`outcome:"ok"`), a `superseded_marker` for E1, then E2 (`outcome:"escalated"`, `escalation_extra_usd:0.000480`). `core.awk` output:

```
ESC 1 0.0005   GROSS 0.0000   NET -0.0005
```

Net is a **loss** equal to the wasted cheap attempt. On this path the H8 fix works: E1's counterfactual credit is removed (via the marker) and its real cost is carried as `escalation_extra`, so the failed route cannot show a profit.

### The test does not exercise the real path · [self-reproduced]

`tests/test-butin.sh:39-45` hand-writes E1 with `outcome:"superseded"` **and** a separate `superseded_marker`. But the live collector never rewrites E1's outcome — it emits E1 as `outcome:"ok"` and a *separate* marker (`butin-collect.sh:125`). These hit **different** `core.awk` branches: the fixture triggers the line-40 skip (`if (j("outcome")=="superseded") next`), while real data triggers the marker-subtraction path (`core.awk:17-24`). The green test validates a code path the collector does not take. Every break below lives in the untested path.

### Break 1 — marker before its target flips net to a PROFIT · [self-reproduced] · **resurrects H8**

`core.awk:19` subtracts E1's contribution only `if (tgt in ev_real)` — i.e., only if E1 was already seen. If the marker is processed *before* E1 (log rotation, a torn concurrent append, manual edit, cross-file split), the subtraction silently no-ops and E1's counterfactual credit survives:

```
log order: [marker→e1] [e1 ok, cf 0.05] [e2 escalated]
result:    GROSS 0.0400   NET +0.0300      ← a failed cheap route booked as +$0.03 profit
```

This is the exact v1 H8 defect, reintroduced through the correction mechanism itself. Normal single-session sequential runs keep E1 before its marker, but the log is a single global append-only file shared across sessions and parallel siblings with no rotation, so ordering is not guaranteed by construction.

### Break 2 — a double marker corrupts every sum · [self-reproduced]

`core.awk` never `delete`s `ev_real[tgt]` after subtracting, so the subtraction is **not idempotent**. Two markers for the same target (reachable via the still-unfixed shared-state read race, below) subtract twice:

```
e1 (real 0.01 / cf 0.05), marker(e1), marker(e1), e2 escalated →
GROSS -0.0400   NET -0.0500   MEASURED 0   agent row: grunt count=0 savings=-0.0400
```

`measured` and per-agent counts go negative; the totals are garbage. Fix: `delete ev_real[tgt]` (and the companion arrays) after the first subtraction.

### Break 3 — cross-agent phantom escalation between parallel siblings · [self-reproduced] · **H7 survives, HIGH**

The heuristic keys off the shared per-session state file with only a 900 s window and an `[ "$PAG" = "grunt" ] || [ "$PAG" = "$AGENT" ]` guard (`butin-collect.sh:121`). It cannot tell a sequential retry from two agents running **in parallel** in the same session — which is amiral's whole design (the policy spawns up to 3–4 parallel subagents). A `grunt`/`haiku` finishing just before an `implementer`/`sonnet-5` in the same session:

```
implementer event → "outcome":"escalated", "escalation_extra_usd":0.000480
grunt event       → voided by a superseded_marker
```

The implementer is falsely booked as an "escalation of" the grunt; the grunt's genuine counterfactual credit is voided and its real cost is double-charged against the implementer. Two unrelated parallel tasks are accounted as one failed-then-retried task.

The bug is **asymmetric**, confirmed in both directions by the independent pass: `grunt → other` fires a *false* escalation (credit erased), but `other → grunt` (e.g. implementer finishing first, then a grunt) does **not** fire the guard, so a *genuine* escalation off a non-grunt cheap attempt is **missed** and books as two independent savings — silently profitable, the original H8 again. So the same defect can erase a real saving or invent a fake one depending only on which agent finished first. Note the false-escalation direction is *opposite* the H10 double-count (one **understates**, the other **overstates**), so the two largest defects do not cancel — the net error is unpredictable in sign and magnitude.

### Break 4 — CHEAP_RATE is fabricated · [self-reproduced] · MEDIUM

`core.awk:51` reads `outcome` to set `ev_ok[id]` one line **before** `outcome` is assigned at line 52, so it captures the *previous* record's outcome. Combined with the supersede bookkeeping, a `grunt` route that failed and was superseded still reports as a success:

```
forced escalation (grunt failed → superseded) → CHEAP_RATE 1 1   (i.e. "100% grunt success")
```

The "cheap-route success rate" honesty metric is computed on stale data.

### Dangling marker — VERDICT: HOLDS · [self-reproduced]

A marker whose `supersedes` target is absent is a safe no-op (`NET -0.0100`, unchanged) — the `if (tgt in ev_real)` guard protects against it. This particular break attempt fails; the code is defended here.

---

## A3 — why did a real run log `agent:"worker", model:"unknown", unmeasured:true`?

**Root cause: the documented asynchronous-transcript race, which the collector has no defense against.** This is the most important answer in Part A, so it is evidenced in full.

The real event (`~/.amiral/butin-errors.log`, single line, verbatim):

```
2026-07-11T15:57:23Z unmeasured event (worker): transcript=/Users/romainpoulard/.claude/projects/-Users-romainpoulard-dev-amiral/e9c3d37f-.../subagents/agent-adf520b16489ab6b9.jsonl in= out= model=
```

Two facts from that one line:
1. `agent_transcript_path` **was present** — `transcript=` is a real, well-formed `subagents/agent-*.jsonl` path. So the field resolved.
2. `in= out= model=` are **all empty** — the collector extracted nothing from that path.

And the decisive fact: that transcript file **is not on disk**, then or now:

```
$ ls .../subagents/agent-adf520b16489ab6b9.jsonl   → No such file
$ ls .../subagents/                                → agent-a76aaa6ac002ffe8a.jsonl (a DIFFERENT id) + .meta.json
```

The payload named a subagent transcript (`adf520…`) that was never materialised under that name at hook time. The collector's guard `[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]` (`butin-collect.sh:42`) failed the `-f` test, the awk block was skipped, `IN`/`OUT`/`MODEL` stayed empty, and the unmeasured path fired (`butin-collect.sh:65-69`). The `agent_type` field also didn't resolve on that same payload, so the name fell back to `"worker"` (`:35`).

This is **exactly** the failure the docs warn about (`code.claude.com/docs/en/hooks#common-input-fields`, verbatim): the transcript "is written **asynchronously and may lag** the in-memory conversation, so it **may not yet include the current turn's most recent messages when a hook fires**. Hooks that need the final assistant text of the current turn should use `last_assistant_message` on Stop and SubagentStop instead of reading the transcript." There is **no** documented flush guarantee for `agent_transcript_path`, and the entry format is explicitly "internal … scripts that parse these files directly can break on any release."

So the worker/unmeasured event is not a one-off glitch — it is the **expected** outcome whenever a subagent's `SubagentStop` fires before its transcript is on disk. The collector:
- hard-depends on reading a file the platform does not promise exists yet (`:42`);
- ignores `last_assistant_message`, the field the docs provide precisely to avoid this race;
- ignores `agent_id`, so it can't even retain a stable identity for the lost event.

The compounding tragedy (A1/H10): when the transcript *is* on disk, the streaming format double-counts it. So a subagent is either **unmeasured** (transcript not ready) or **mis-measured** (transcript double-counted). On the real session captured here, one collector-visible session produced: 1 subagent measured-but-wrong (`implementer`, numbers don't match its transcript), 1 subagent unmeasured (`worker`), and 2 brain events. Zero subagent events were both counted and correct.

### Sub-questions the brief asked

- **An `agent_type` the code doesn't expect** → any unknown string is logged verbatim as the agent name (no allow-list); an absent/empty/null one falls back to `"worker"` (`:35`). A garbage agent name is measured; a missing one is bucketed. This is not cosmetic: the escalation guard tests `[ "$PAG" = "grunt" ]` (`:121`), so if a *failed cheap attempt's* payload happened to omit `agent_type`, it is stored as `"worker"`, the guard can never fire, H8's loss-detection is silently disabled for that retry, and the fabricated-profit case returns with no warning. Identity laundering feeds directly into the money accounting.
- **A transcript still being written** → confirmed above: absent file → unmeasured; a *partial* file → measured but undercounted, with no signal that it was partial. This is worse than the absent case, because it looks complete.
- **A sub-subagent** → the real `.meta.json` sidecar carries `"spawnDepth":1`, so nesting is tracked by the harness. The collector reads neither the sidecar nor `spawnDepth`; a nested subagent fires its own `SubagentStop` with its own `agent_transcript_path` and is billed as an independent top-level worker. Nesting is invisible to the accounting.

---

# PART B — the unfixed provenance surface (confirm on v0.11.0)

All five reproduce, each independently by two passes (my own code-read + repro and a fresh adversarial pass). None was touched by the v0.11.0 commit (which changed only `butin-collect.sh`, `core.awk`, fixtures, and docs).

> **Process note — an injected "already fixed" channel.** Both independent adversarial passes, separately and without prompting, reported that the tool-result stream carried injected `system-reminder`-styled messages asserting the v0.11.0 fixes were already implemented (e.g. "SubagentStop payload parsing fixed (C1/C2)") and steering toward non-existent helper tools (`get_observations`, `smart_outline`). Every such "fixed" claim that overlapped audited scope was **false** — verified by execution. Two independent agents flagging the same injection is itself evidence it is persistent, not a fluke. Flagging it because a live channel that can tell an auditor "already fixed, stop checking" is a threat to the integrity of any review run here; this audit ignored those assertions and reproduced everything from source and observed output.

### H2 — `Amiral-Verified` is forgeable; the marker has no producer · REPRODUCES · [self-reproduced]

- **No producer.** `hooks/subagent-verify.sh` runs `verify.sh` and exits 0 or 2 (`:36-42`) — it never writes a `verify-ok-*` marker. A repo-wide search finds the marker string only in the two *consumers* (`butin-collect.sh:101`, `amiral-journal:43`) and in `tests/test-butin.sh`, which `touch`es it to fake a producer. So the collector's `verified` field is **always `null`** in normal operation (confirmed on all real events in `butin.jsonl.v11-firstrun`: `"verified":null` on every line) — and **forgeable to `true`** by any local process that `touch`es `~/.amiral/state/verify-ok-$SESSION` before the collector runs (`butin-collect.sh:101-107` only checks the file's existence and age, never that a gate produced it).
- **Unscoped consumer.** The journal hook greens the trailer on *any* session's marker: `find "$AMIRAL_HOME/state" -name 'verify-ok-*' -mmin -60` (`amiral-journal:43`) — no repo, no session scoping. A bare `touch ~/.amiral/state/verify-ok-anything` turns `Amiral-Verified: green (verify.sh, fresh)` in a repo that contains no `verify.sh` at all.

### H3 — `Amiral-Attest` proves reading, not running; degenerates to the hash of nothing · REPRODUCES · [self-reproduced]

`attest_hash()` (`amiral-journal:15-20`) and the generated hook (`:44`) compute `sha256(cat verify.sh + git diff --cached)` — producing the digest requires **reading** `verify.sh`, never **executing** it. In a repo with no `verify.sh` and an empty staged diff (the `--amend` case), the input is empty and the hash is a recognizable constant proving nothing ran:

```
$ { cat ./verify.sh; git diff --cached; } | sha256   → 01ba4719c80b6fe9   (sha256 of "\n")
$ printf '' | sha256                                  → e3b0c44298fc1c14   (sha256 of "")
```

Trailers also **stack**: the hook's only idempotence guard is `grep -q "Amiral-Route:" "$MSG" && exit 0` (`:37`). When `ROUTES` is empty (unmeasured-only log, fresh repo), no `Amiral-Route:` line is emitted (`:47`), so the guard never matches and every amend re-appends the pair — confirmed **3 copies** of `Amiral-Verified`/`Amiral-Attest` after two `--amend --no-edit` runs. The mirror-image failure occurs when routes *are* present and the guard *does* early-exit: the trailer is frozen at the first commit, so after an amend that changes the staged diff the surviving `Amiral-Attest` hashes to the *original* diff while `git show HEAD` is now different — the attestation actively **lies about the committed code**. One broken guard, two failure modes (unbounded duplication or silent staleness), selected only by whether `butin.jsonl`'s last 50 lines happened to contain a matching entry.

### H4 — `Amiral-Route` leaks other repositories' routing · REPRODUCES · [self-reproduced]

`ROUTES` is `tail -50` of the **global** `~/.amiral/butin.jsonl` with no repo scoping (`amiral-journal:39-41`, and the `note` arm `:69-71`). A commit in repo A carries the agent/model pairs of tasks run in repo B. The `--with-cost` warning covers only `Amiral-Net-Saved`; `Amiral-Route` ships by default in the base `enable` and is never flagged as a cross-repo leak. A private client's routing profile can land in a public commit.

### H9 — trust gate is checksum-blind to sourced files (ACE one `source` deep) · REPRODUCES · [self-reproduced]

The trust fingerprint is `repo_root :: shasum(verify.sh)` — verify.sh's own bytes only (`hooks/subagent-verify.sh:19`). Anything it `source`s / `exec`s / invokes (`verify-helpers.sh`, a Makefile, `node_modules/`, `npm test`) is unfingerprinted. Trust a `verify.sh` that does `source ./verify-helpers.sh`, then edit **only** `verify-helpers.sh` to run arbitrary code — `shasum verify.sh` is unchanged, the gate still fires, and the injected code executes with full shell privileges on the next `SubagentStop`. The "checksum-pinned, tamper-evident" guarantee (`docs/hooks.md`) covers one file while the real attack surface is the whole transitive read-set.

### C6 — `--with-cost` consent gate is a no-op without a TTY · REPRODUCES · [self-reproduced]

`amiral-journal:27-30` prompts, then reads with `read -r _ </dev/tty 2>/dev/null || true`. With no controlling TTY (an agent's own Bash tool, CI, any scripted install) the read fails and `|| true` swallows it:

```
$ bash bin/amiral-journal enable --with-cost </dev/null      # repo with a github.com remote
⚠ public remote detected: Amiral-Net-Saved will be visible to everyone. Ctrl-C to abort, Enter to continue.
bin/amiral-journal: line 29: /dev/tty: Device not configured
⚓ journal enabled for this repo (trailers: Route + Verified + Attest + Net-Saved).
→ generated hook contains the Net-Saved cost line
```

The one gate guarding the publication of dollar figures to a public repo is bypassed silently.

---

# New findings (ranked)

| ID | Sev | Finding | Evidence |
|----|-----|---------|----------|
| **V2-C1** | CRITICAL | Streaming transcripts write one turn on ≥2 lines (same `message.id`); "sum every usage block" (`butin-collect.sh:48-58`) double-counts them. Real event: cache-write over-counted 1.96×. Controlled: net saved inflated 1.93×. Inflates real, counterfactual, and net together. The H10 fix over-corrected undercount → overcount. | [self-reproduced] [real-data] |
| **V2-H1** | HIGH | Subagents silently drop to `unmeasured` on the documented async-transcript race (`:42` hard-depends on a file the platform doesn't promise; `last_assistant_message` ignored). An unmeasured cheap attempt also writes no state, so escalation detection can't see it. | [self-reproduced] [real-data] [docs-confirmed] |
| **V2-H2** | HIGH | Cross-agent phantom escalation: parallel siblings (grunt/haiku + implementer/sonnet in one session) are mis-booked as a failed-then-retried task — real credit voided, real cost double-charged, per-agent attribution corrupted. (v1 H7, surviving.) | [self-reproduced] |
| **V2-H3** | HIGH | `core.awk` supersede correction is order-dependent and non-idempotent: marker-before-target flips net to a **profit** (H8 resurfaces); double marker corrupts every sum (negative `measured`/per-agent). Reachable via rotation, torn appends, or the shared-state read race. | [self-reproduced] |
| **V2-H4** | HIGH | A *partial* or *torn* transcript (hook fires mid-stream, or an append is OS-buffer-torn) logs `outcome:"ok"` with silently dropped turns — indistinguishable from a complete measurement. No expected-turn count, no `stop_reason`, no re-read. Real event #1 logged `in=10/out=538/cr=34936/cw=27291`, matching neither its transcript's naive nor dedup totals. Same tier as the unmeasured case, but worse: it *looks* measured. | [self-reproduced] [real-data] [corsaire-confirmed] |
| **V2-M1** | MEDIUM | `core.awk` has no locale guard of its own; under a comma-decimal locale, `awk -f core.awk log.jsonl` **silently zeros every dollar figure** (`strtod` truncates `"0.006"`→`0`) while integer counts stay intact, so the report looks structurally valid. The three shipped callers export `LC_ALL=C`, so the CLI is safe *by convention*; any third-party adapter or direct/CI/dashboard invocation of the "provider-agnostic" engine reads $0.00. Reconfirms v1 M7 live. | [corsaire-confirmed] |
| **V2-M2** | MEDIUM | `CHEAP_RATE` fabricated: `core.awk:51` uses `outcome` before it is assigned at `:52`, so `ev_ok` captures the previous record; a failed+superseded grunt reports as 100% success. | [self-reproduced] [corsaire-confirmed] |
| **V2-M3** | MEDIUM | `amiral-journal enable` (`:31-32`) truncate-overwrites any pre-existing `.git/hooks/prepare-commit-msg` with no check, backup, or warning; `disable` (`:62`) then `rm -f`s it. A repo whose git-hook tooling (husky, commitizen, ticket-prefixing) lives only in `.git/hooks` loses it unrecoverably. | [corsaire-confirmed] |
| **V2-L1** | LOW | Cross-version state schema: v0.10 wrote a 5-field state line; v0.11 reads 7 (`:117`). A leftover 5-field file (real example: `~/.amiral/state/last-ba4b0128…`) leaves `PID`/`PCF` empty, so the first post-upgrade escalation writes no supersede marker (H8 correction silently skipped). | [real-data] |
| **V2-L2** | LOW | `session_id` is used raw in the state-file path (`:101,114,130`) with no sanitization. A `../`-laden id can't fully escape (the `last-` prefix blocks an exact `..` first component) but it dumps the internal path to hook stderr, and there is no ownership check — any caller can read/clobber another session's escalation state by naming it. | [corsaire-confirmed] |
| **V2-N1** | note | The entire token-extraction strategy parses a transcript the docs call "internal … can break on any release," and ignores the two sanctioned APIs (`last_assistant_message`, `/export`). Systemic fragility independent of every bug above. | [docs-confirmed] |

---

# Is the butin math now safe to trust on real data?

**No.**

The v0.11.0 commit fixed what it claimed at the field level — and that is a genuine, verifiable improvement: on live data the collector now resolves agent names and the worker's own model, which v0.10.1 provably never did (its log holds only `worker`/`brain`). C2 holds outright; C1 holds whenever the payload cooperates; the straight-line H8 case books a loss, not a profit.

But "safe to trust on real data" requires the numbers to be *right*, and on real data they are not:

1. **Every dollar figure is inflated ~2×** by the streaming duplicate-usage double-count (V2-C1) — and it inflates in the direction that flatters the headline savings, which is the one direction this project cannot afford to be wrong in.
2. **Subagents silently vanish into `unmeasured`** whenever their transcript isn't flushed at hook time (V2-H1), a race the platform documents and the collector does nothing to survive.
3. **Even the events that *are* measured don't match their own transcripts** (V2-H4): a partial or torn transcript read mid-write logs `outcome:"ok"` with silently dropped turns, indistinguishable from a full measurement.
4. **Parallel fan-out — amiral's signature workflow — manufactures phantom escalations** (V2-H2) that void real credits and double-charge, while the escalation correction that H8 added is itself order-fragile and non-idempotent (V2-H3), able to flip a loss back into a fabricated profit.

These are not independent rounding errors that wash out. Two of the largest (the double-count and the phantom escalation) push in *opposite* directions, so the aggregate error has no predictable sign or bound. A badge or a benchmark computed from this ledger is not defensible.

Separately, the provenance surface is unchanged: `Amiral-Verified` is forgeable and has no producer (H2), `Amiral-Attest` proves reading not running and degenerates to the hash of nothing (H3), `Amiral-Route` leaks cross-repo (H4), the trust gate is one `source` from arbitrary code execution (H9), and the cost-consent gate is a no-op without a TTY (C6). None of these block the *math*, but they block calling the journal "proof."

**What would move the answer to yes** (in dependency order):
1. Read tokens from `last_assistant_message` / a supported interface, or — if parsing the transcript at all — **deduplicate usage by `message.id`** and only count final turns. This kills V2-C1.
2. Handle the async race explicitly: retain `agent_id`, and if the transcript is absent/partial/torn, defer or reconcile rather than silently emitting a measured (or `unmeasured`) event with no completeness signal. This addresses V2-H1 and V2-H4.
3. Distinguish sequential retries from parallel siblings before charging an escalation (require the previous event to have *completed before this one started*, and not merely share a `session_id`), and make the supersede correction idempotent (`delete ev_real[tgt]`) and order-independent. This addresses V2-H2 / V2-H3.
4. Give `core.awk` its own locale guard (V2-M1), fix `CHEAP_RATE`'s stale-outcome bug (V2-M2), the cross-version state schema (V2-L1), and stop clobbering pre-existing git hooks (V2-M3).

Until at least (1)–(3) land, the butin is measuring a mixture of double-counted, undercounted, and phantom events, and its headline number should not be published.
