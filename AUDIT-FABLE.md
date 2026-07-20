# AUDIT-FABLE — adversarial audit of amiral v0.10.1

Branch `audit/v0.10.1`, 2026-07-11. macOS 26.5.1 (BSD userland, `/bin/bash` 3.2.57), ambient locale `fr_FR.UTF-8`.
Read-only audit: no file in the repo was modified. Fixes are **suggested, not applied**.

Sources: an adversarial pass (corsaire) on portability/robustness, a fresh-context consistency pass (reviewer) on dead code and doc drift, a hook/statusline mechanism pass against the official Claude Code docs, and my own verification battery. **Every finding below marked `[reproduced]` was executed and observed in this session**; `[agent-verified]` means an agent ran it and I did not re-run; `[code-read]` means inspection only. Evidence lives in the session scratchpad.

---

## Verdict

**The butin has never measured a subagent.** The collector reads two hook fields that SubagentStop does not deliver, and one it does deliver but which means something else. On real data it bills the *main session's* last API call — the brain's tokens, at the brain's price — once per subagent completion, under the invented agent name `"worker"`. Every downstream honesty feature (coverage, cheap-route rate, escalation detection, brain premium, the badge, the commit trailer) is computing over fabricated rows. The test suite is green because the tests hand-craft the same wrong fields the collector reads.

Wiring the collector on real data is **blocked** until C1 is fixed. Everything else in this audit is downstream of that.

---

## Coverage map (the 8 questions asked)

1. **macOS/BSD portability** → H5, H6, L5, L7, plus non-finding N1. The classic `sed -i` / `date -d` / `stat -c` traps are all correctly guarded already (`bin/amiral-butin:109` chains `date -d || date -j -f`; `butin-collect.sh:85` chains `stat -c || stat -f`); the real BSD damage is the **absent `timeout`** (H5) and the `%N` id-entropy assumption (H6).
2. **Robustness / `set -u` / hostile data** → C3, C4, C7, M2, M3, M6, M8, M11, L2.
3. **Honesty (every number traced to core.awk)** → C1, C2, C7, H10 (undercount), **H8 (the escalation credit — both corsaires reproduced it independently)**, plus what *holds*: N3, N4, N5.
4. **Concurrency** → H7 (`$STATE.tmp` race, reproduced), H2 (the verify marker has no producer at all), N1 (appends are safe, but for the wrong reason — L7).
5. **Attestation integrity** → H2 (**forgeable green `Verified`**, reproduced), H3 (amend attests nothing + trailers stack 3-deep), H4 (cross-repo route leak), and the flat answer that **Amiral-Attest does not prove verify.sh ever ran**.
6. **Dead/duplicate code** → H1, M9, M10, L3, L6.
7. **Doc drift** → D1–D11.
8. **Security** → C6 (consent gate bypass), **H9 (trust-gate include-blindness = arbitrary code execution, reproduced)**, H4 (leak), M11/M12 (JSON injection, PII in error log), L10 (trust rebind), N2 and N6 (attacked, held).

---

## CRITICAL

### C1 — The collector reads hook fields that do not exist; it has never measured a worker
`adapters/claude-code/butin-collect.sh:26-28,36-42` · **[reproduced]**

SubagentStop delivers `agent_type` and `agent_transcript_path`. It does **not** deliver `subagent_type` (that is a field of the *Task tool's input*, not of the hook), and its `transcript_path` is **the main session's transcript**, not the subagent's — both stated verbatim in `code.claude.com/docs/en/hooks.md` §SubagentStop input. The collector greps `subagent_type` (never matches → `AGENT` falls back to the literal `"worker"`) and `transcript_path` (matches → reads the *brain's* transcript).

Consequences, all confirmed on a real SubagentStop payload built to the documented schema, against this session's real transcripts:

- `agent` is `"worker"` on every event. The rows `grunt`, `implementer`, `reviewer` **never appear**. `CHEAP_RATE` (grunt success) can never compute. The escalation heuristic's `[ "$PAG" = "grunt" ]` test can never fire — and its `[ "$PAG" = "$AGENT" ]` test now *always* fires, since every agent is `"worker"`.
- Tokens come from the main session's last API call. A subagent that truly used 46k context is billed the brain's 163k. With N subagents finishing, the **same brain context is re-billed N times**.
- The model is the main transcript's last `"model"` string — `claude-opus-4-8` in my run, while the finishing subagent actually ran `claude-sonnet-5` and the session brain is `claude-fable-5`. Three models; the collector picked the one that is neither.

Repro: feed the collector the documented payload with `agent_type:"grunt"` + real transcripts →
`{"agent":"worker","chosen_model":"claude-opus-4-8","tokens":{"in":2,"out":1158,"cache_read":163125,...},"real_cost_usd":0.387105,"counterfactual_cost_usd":0.077421}` — **−$0.31 net booked for a task that really cost about $0.02.**

Why CI is green: `tests/test-butin.sh:17` hand-writes `{"subagent_type":"grunt","transcript_path":"<fixture>"}`. The tests encode the same wrong assumption as the code, so they can never catch it.

Fix: on SubagentStop read `agent_type` and `agent_transcript_path`; keep `transcript_path` only for the `--brain` (Stop) path; rewrite the fixtures to the documented schema.

### C2 — The billed model is uncorrelated with the tokens billed
`adapters/claude-code/butin-collect.sh:42` · **[reproduced]**

`MODEL` is grepped over the *whole* transcript with `tail -1`, independent of `$ULINE` (the line the tokens came from). Any later `"model"` mention wins — a subsequent Task-tool call's target model, a mixed-model transcript, a resumed session. Surviving C1's fix does not save this: the last model in a file is not the model of the last usage block.

Repro (real transcript, above): tokens from one API call, model string from an unrelated later line → up to ~19x mis-billing (haiku tokens at opus rates).
Fix: extract `MODEL` from `$ULINE`, the same line the token counts came from.

### C3 — `core.awk`'s number parser is exponent-blind (100× errors)
`lib/butin/core.awk:11-12` · **[reproduced]**

`j()`'s numeric regex is `-?[0-9.]+` — no `e`/`E`. A cost in scientific notation (the default serialization for small floats in Python `json.dumps` and JS `JSON.stringify` — exactly the shape of per-token dollar values) is truncated at the mantissa: `1.5e-2` parses as **`1.5`**, a 100× inflation.

Repro: `awk 'BEGIN{s="\"real_cost_usd\":1.5e-2,"; match(s,"\"real_cost_usd\"[ ]*:[ ]*-?[0-9.]+"); v=substr(s,RSTART,RLENGTH); sub(/^.*:[ ]*/,"",v); print v}'` → `1.5`.
Today this is masked only because the bash collector writes `%.6f`. But `core.awk` is advertised as the *universal, provider-agnostic* engine (`ports/BUTIN.md`) that third-party adapters — plausibly written in Python or JS — are invited to feed. The first such adapter inflates every number 10^N.
Fix: `-?[0-9.]+([eE][-+]?[0-9]+)?`.

### C4 — A corrupt state file destroys the event entirely (not even "unmeasured")
`adapters/claude-code/butin-collect.sh:99-100` · **[reproduced]**

`GAP=$(( NOW - ${PEPOCH:-0} ))` reads `PEPOCH` from the per-session state file. If that field is ever non-numeric (partial write from the H7 race, a legacy-schema file, a manual edit), bash parses the dashed model id as an arithmetic expression, hits an unset variable under `set -u`, and **aborts before the append**. The event is not logged as measured, not logged as unmeasured — it vanishes with no trace, and the log file is never even created.

Repro: write a 5-field state file with a model id in the epoch slot, fire a normal event → `line 100: claude: unbound variable`; `butin.jsonl` does not exist.
This violates the cardinal rule of the design ("never invent a number" has a twin: "never silently lose one").
Fix: validate `PEPOCH` against `^[0-9]+$` before the arithmetic; default to 0.

### C5 — The badge's "refuses to lie small" gate fails open at zero measured tasks
`bin/amiral-journal:83-86` · **[reproduced]**

`MEAS=$(grep -c '"real_cost_usd"' "$LOG" 2>/dev/null || echo 0)`: when grep matches nothing it prints `0` **and exits 1**, so `|| echo 0` fires too. `MEAS` becomes the two-line string `"0\n0"`. `[ "$MEAS" -lt 20 ]` then throws `integer expression expected` and evaluates **false** — so the guard is skipped in exactly the case it exists to catch, and the badge prints.

Repro: `amiral-journal flag` on a log holding only an unmeasured event →
`[![sailed with amiral](...0\n0_tasks_·_net_%2B$0.0000...)]` and exit 0, instead of the refusal.
Spec rule C3 ("no badge under 20 measured tasks") is not enforced. Same bug, cosmetic, at `bin/amiral-doctor:81-82`.
Fix: `MEAS=$(grep -c ... || true); MEAS=${MEAS%%$'\n'*}; MEAS=${MEAS:-0}`.

### C6 — The public-remote consent gate is a silent no-op without a TTY
`bin/amiral-journal:27-30` · **[agent-verified]**

The `--with-cost` warning ("public remote detected: Amiral-Net-Saved will be visible to everyone… Ctrl-C to abort") reads with `read -r _ </dev/tty 2>/dev/null || true`. With no controlling TTY — an agent's own Bash tool, CI, any scripted install — the read fails and `|| true` swallows it. The consent prompt prints and is instantly bypassed; the cost-leaking hook installs anyway.

Repro: `bash amiral-journal enable --with-cost </dev/null` in a repo with a github.com remote → `/dev/tty: Device not configured`, then `⚓ journal enabled … + Net-Saved`.
This is a consent bypass on the one gate that guards publishing money figures to a public repo.
Fix: fail closed — if no TTY, refuse to enable `--with-cost` and say why.

**FIXED v0.15.1**: the gate now fails closed. `enable` scans all args for `--with-cost` and a new opt-out flag `--yes`/`--assume-yes` (order-independent, replacing the old single-position `$2` check). A new `have_tty()` probe actually opens `/dev/tty` (not `[ -t 0 ]`) to detect a real controlling terminal. On a public remote with `--with-cost`: `--yes` proceeds and says so; a real TTY shows the warning and a failed `read` now aborts (`exit 1`) instead of being swallowed by `|| true`; no TTY and no `--yes` refuses outright (`exit 1`, hook not written, reason printed to stderr). Covered by `tests/test-journal.sh` J-17/J-18/J-19.
**Hardened after adversarial review**: the public-remote check was a `github.com|gitlab.com` denylist — Bitbucket, Codeberg, self-hosted forges and `ssh` remotes bypassed the gate entirely (C6 still open for every other host). It now fails closed the other way: `remote_needs_consent()` gates on ANY remote pointing at a network host and skips only obviously-local ones (filesystem paths, loopback), so over-asking on a private host is the worst case, never a silent leak. The interactive `read` also gained `-t 60` so an output-only pty can't hang it instead of failing closed. `tests/test-journal.sh` J-20/J-21 add Bitbucket and `ssh` remote repros.

### C7 — A missing trailing newline silently swallows an event, and coverage then *claims* full accounting
`adapters/claude-code/butin-collect.sh:112` + `lib/butin/core.awk:15,18-24` · **[reproduced]**

If any append is interrupted before its `\n` (killed hook, disk full, OOM), the next event's JSON is concatenated onto the unterminated line. `core.awk`'s `/^\{/` still matches the merged line as **one** record, and `j()`'s leftmost-match takes only the first object's fields. The second event's money disappears — and it is counted neither as a bad line nor as a duplicate.

Repro: two events, first written without a trailing newline (real cost 0.01/cf 0.05; second 5.00/9.00) → `amiral-butin` prints `Net saved +0.04 $` and **`Coverage: 1/1 tasks measured`**. A $4.00 event vanished while the honesty line affirmed complete coverage.
This is the worst failure mode in the design: the mechanism built to disclose gaps actively certifies their absence.
Fix: in `core.awk`, reject any record containing a second top-level `{` after the first closes (count as `bad`), so lost data surfaces as a corrupted-line note.

---

## HIGH

### H8 — A failed cheap route can still be reported as a profit (escalation keeps a phantom credit)
`lib/butin/core.awk:36,41-43` + `adapters/claude-code/butin-collect.sh:95-105` · **[reproduced]**

Direct answer to "verify escalations can only ever REDUCE net, never inflate it": **they reduce it, but not enough — the accounting still overstates.**

When a cheap attempt E1 fails and is retried by E2, the collector charges `escalation_extra_usd = R1` against E2. But **E1 remains in the ledger as a normal measured event**, so its counterfactual credit `cf1` stays in `cf_sum`. In the counterfactual world the cheap attempt never happened and produced nothing, so `cf1` is a credit for work that was thrown away.

```
reported net = cf1 + cf2 − 2·R1 − R2
true net     =       cf2 −   R1 − R2
overstatement = cf1 − R1        ← always positive (the cheap model is always cheaper than baseline)
```

Repro (real rates, haiku attempt → sonnet retry, sonnet baseline): reported **+$0.0204**, truth **−$0.0117**. The overstatement is exactly `cf1 − R1 = $0.0321` — and it **flips the sign**: a failed cheap route that lost money displays as a win. With a pricier baseline (opus) the overstatement grows.

This makes the honesty note at `bin/amiral-butin:168` ("a failed cheap route can make a task net-negative — by design") true only in the narrow case `2·R1 > cf1`; the common case books a profit on a failure.
Fix: on escalation, exclude E1's counterfactual from `cf_sum` (mark E1 `outcome:"superseded"` and have `core.awk` skip its `cf`), instead of adding a `R1` penalty and keeping `cf1`.

### H1 — `--detail` crashes on an unbound variable, taking the entire honesty block with it
`bin/amiral-butin:166` · **[reproduced]**

`$PVER` is referenced but never assigned in this script (only `$PV` is, at line 107) — a rename that never propagated. Under `set -uo pipefail` this is fatal.
Repro: `amiral-butin --detail` → prints as far as "Baseline source:", then `line 166: PVER: unbound variable`, exit 1. The decomposition-bias caveat, the escalation caveat, the pricing-table version, the staleness warning and the corrupted-line note **never print**. No test covers `--detail`.
Fix: `$PV`. Add a `--detail` test.

### H2 — `verified` has no producer, and the journal's consumer is global → a `green` trailer is forgeable
`adapters/claude-code/butin-collect.sh:83-89`, `bin/amiral-journal:43` · **[reproduced]** · *promotes toward CRITICAL when read with H3*

Two halves, both confirmed:

1. **No producer.** `grep -rn verify-ok` finds exactly three hits: two consumers and `tests/test-butin.sh:59`, which `touch`es the marker itself to fake the producer. `hooks/subagent-verify.sh` runs verify.sh and exits 0 or 2 — it never writes a marker. So the collector's `"verified"` is always `null`. `docs/butin-spec-v2.md:21-22` lists this as MUST, implemented in v0.10.
2. **The journal consumer matches *any* session's marker.** `bin/amiral-journal:43` checks `find "$AMIRAL_HOME/state" -name 'verify-ok-*' -mmin -60` — no repo scoping, no session scoping. One stray marker from an unrelated session (or a bare `touch`) turns the trailer green **in a repo that has no verify.sh at all**.

Repro: `touch ~/.amiral/state/verify-ok-SOME-OTHER-SESSION`, then commit in a fresh repo containing no `verify.sh` → trailer reads **`Amiral-Verified: green (verify.sh, fresh)`**. The provenance claim is not merely absent, it is fabricable.
Fix: write the marker from `hooks/subagent-verify.sh` on exit 0, and scope the filename *and* the `find` to `repo_root` + session — not a global glob.

### H3 — `Amiral-Attest` proves nothing about verify.sh having run, and on `--amend` it hashes nothing at all
`bin/amiral-journal:15-20,44` · **[reproduced]**

Two separate defects:
1. The hash is `sha256(cat verify.sh + git diff --cached)`. Computing it requires **reading** verify.sh, not **running** it. Anyone can produce a valid trailer without executing the gate. The claim at `bin/amiral-journal:17` and `docs/butin-spec-v2.md:24-26` — "forging it means actually running the real gate" — is **false**. What the hash actually proves: "a file named verify.sh with this content sat next to this diff." Nothing about execution, exit code, or result.
2. On `git commit --amend`, the staged diff is empty. With no `verify.sh` in the repo, the hash degenerates to the SHA-256 of the empty string: **`sha256:e3b0c44298fc1c14`** (reproduced on a live amend). A constant, recognizable "I attest to nothing" that still renders as a legitimate-looking attestation.

Fix: attest the *committed* diff (as the `note` arm already does) and bind the attestation to a gate **result** (marker from H2 carrying exit code + verify.sh checksum), or rename the trailer to what it really is (`Amiral-Diff-Digest`) and drop the forgery claim.

### H4 — Commit trailers leak routing from other repositories
`bin/amiral-journal:39-41,69-71` · **[reproduced]**

`ROUTES` comes from `tail -50` of the **global** `~/.amiral/butin.jsonl`. The log is not scoped by repo, so a commit in repo A carries the agent/model pairs of tasks run in repo B. In my test, a commit in a fresh throwaway repo emitted `Amiral-Route: grunt=claude-haiku-4-5 implementer=claude-sonnet-4-6` — routes from an entirely different session's work.
The `--with-cost` warning covers `Amiral-Net-Saved` only; `Amiral-Route` ships **by default** in the base `enable` and is never mentioned as a cross-repo leak. A private client project's routing profile can land in a public commit.
Fix: stamp `cwd`/repo root into each event and filter `ROUTES` to the current repo; document the residual leak.

### H5 — The verify-gate timeout does not exist on macOS
`hooks/subagent-verify.sh:29-34`, promised in `docs/hooks.md:30` · **[reproduced]**

`TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"` — stock macOS ships **neither** (both confirmed absent on this box; `gtimeout` needs Homebrew coreutils). The fallback runs `./verify.sh` with no bound at all, directly contradicting the script's own comment and the doc's "wraps execution in a 300s `timeout` so a hung verify can't freeze your session."
Fix: implement the timeout in bash (background the child, `kill` after N seconds) instead of depending on a binary that isn't there.

### H6 — Event ids can collide on the mainstream macOS install base, and collisions silently *delete* events
`adapters/claude-code/butin-collect.sh:32` · **[partially reproduced]**

`ID` derives its entropy from `date +%s%N`. BSD `date` only gained `%N` in FreeBSD 14.1; on the macOS versions most users are actually running, `date +%s%N` prints the epoch followed by a literal `N`. Two same-agent events in the same session within one wall-clock second then hash to the **same id** — and `core.awk:18` treats a repeated id as a duplicate and **discards it**. Parallel fan-out (the shape amiral exists for) is precisely this scenario. Amplified by C1: every agent is named `"worker"`, so the agent component adds no entropy either.
On *this* box (macOS 26.5.1) `%N` works — verified monotonic. The finding is real for the install base, not for this machine.
Fix: don't source uniqueness from sub-second time. Use `$$`, `$RANDOM`, and a counter, or `mktemp`-derived entropy.

### H9 — The trust gate is checksum-blind to anything verify.sh sources → arbitrary code execution past a gate advertised "tamper-evident"
`hooks/subagent-verify.sh:19`, claim at `docs/hooks.md:27-29` · **[reproduced]**

The trust fingerprint is `repo_root :: shasum(verify.sh)` — **verify.sh's own bytes only.** Nearly every real verify.sh sources helpers, calls `npm test`, invokes a Makefile, or runs code under `node_modules/`. None of that is fingerprinted. Edit any of it and the gate still fires: the doc's "checksum-pinned… tamper-evident" guarantee covers one file while the actual attack surface is the whole transitive read-set.

Repro (forced, full ACE): trust a `verify.sh` that does `source ./verify-helpers.sh`; after trusting, edit **only** `verify-helpers.sh` to `touch /tmp/PWNED`; `shasum verify.sh` is unchanged → the hook runs and `/tmp/PWNED` is created with full shell privileges on the next SubagentStop. Confirmed end to end in this session.
This is the same weight as the original threat model the gate exists to stop (a booby-trapped verify.sh), just one `source` deep.
Fix: refuse to trust a verify.sh that sources/execs outside itself, or fingerprint the transitive read-set; and re-hash immediately before exec to close the check→run TOCTOU window (L5-adjacent).

**FIXED v0.15.1 — honest-scope docs, not static detection**: static detection of `source`/`exec` was rejected as unsound (every real `verify.sh` runs `npm test`/`make`/`node_modules`; grep-detection is both over- and under-inclusive — it misses `eval`, `` `backticks` ``, `$(cat)`, and plain `PATH` lookups), and a soundly-pinned transitive read-set is not achievable in shell for an arbitrary build. Instead `docs/hooks.md` "Security model" was rewritten to state the actual guarantee and drop the unqualified "tamper-evident" claim: the hook only runs `verify.sh` for a repo you explicitly trusted at this path+identity, the checksum covers `verify.sh`'s own bytes only, and anything it sources/execs/invokes is explicitly **not** fingerprinted — trusting a repo means trusting its entire build. `bin/amiral-trust`'s header and success output, and `hooks/subagent-verify.sh`'s header, carry the same caveat. Separately, `hooks/subagent-verify.sh` now re-hashes `verify.sh` immediately before exec and refuses if it changed since the trust match (closes the TOCTOU window this entry also flagged). Regression-tested in `tests/test-trust.sh`.

### H10 — Only the last API turn is billed; multi-turn subagents are undercounted ~40–60%
`adapters/claude-code/butin-collect.sh:37-42` · **[agent-verified]** · *survives the C1 fix*

`grep '"input_tokens"' "$TRANSCRIPT" | tail -1` takes the **last** usage block. A subagent doing real work makes many API calls; only the final turn's tokens are counted. This is a distinct bug from C1/C2 (wrong transcript / wrong model): even after the collector reads the correct `agent_transcript_path`, it still bills a fraction of that transcript.
Repro: a 4-turn transcript with true totals in=20000/out=3200/cache_read=12000 → collector logs in=8000/out=1100/cache_read=6000 (≈40–60% visibility). Both real and counterfactual shrink together, so the *sign* of net usually survives, but the magnitude — the headline dollar figure and every per-agent row — is understated and the undercount is disclosed nowhere.
Fix: sum every usage block in the (correct) transcript, not `tail -1`.

### H7 — Per-session state file uses a fixed temp name; concurrent siblings race it
`adapters/claude-code/butin-collect.sh:106` · **[reproduced]**

`printf … > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"` — `$STATE.tmp` is a **fixed** name per session, and parallel subagents share a session. Two collectors finishing together both write the same temp path; one `mv` wins, the other fails.
Repro: two collectors, same session, fired concurrently → `mv: …/last-PAR.tmp: No such file or directory`, and the surviving state file holds an arbitrary sibling's row.
Two harms: (a) the loser's state is lost or interleaved, feeding C4's crash path; (b) the escalation heuristic then compares a sibling against a *parallel* sibling — which is not an escalation at all — and can charge a phantom penalty. With C1 in play (`PAG == AGENT == "worker"` always), the same-agent guard that was supposed to constrain this is permanently open.
Fix: `mktemp "$STATE.tmp.XXXXXX"` (PID-unique) then `mv`; and scope the escalation heuristic to *sequential* events (require the previous event to have completed before this one started).

---

## MEDIUM

- **M2** `bin/amiral-butin:52-57` · `add-model` validates only that prices are non-empty, not numeric. `add-model foo abc def` writes a row of zeros and reports success; every future event on that model is then "measured" at `$0.000000`. Fix: require `^[0-9.]+$`. [agent-verified]
- **M3** `bin/amiral-butin:54,58` · `add-model` does not reject TABs in the pricing id, corrupting the TSV column layout; `rates()` then returns a string in a numeric slot and awk silently prices it as 0. Fix: reject tabs/newlines in the id. [agent-verified]
- **M4** `bin/amiral-journal:53` · The generated `--with-cost` hook runs the **full** `core.awk` over the entire unbounded `butin.jsonl` on *every commit*, forever. `ROUTES` is correctly windowed (`tail -50`); `NET` is not, and no rotation exists anywhere. Commit latency grows linearly with lifetime log size. Fix: window it, or read the §1 statusline cache. [code-read]
- **M5** `bin/amiral-butin:17,160` · `--no-color` and `--detail` are only honored as `$1`, while `--haircut` is scanned across `"$@"`. `amiral-butin --no-color --detail` silently drops the honesty block; `--detail --no-color` emits raw ANSI. Fix: scan `"$@"` for all flags. [reproduced]
- **M6** `bin/amiral-savings:29-32` · `--tokens` with no value dereferences `$2` under `set -u` → `unbound variable`, not a usage message. Fix: guard `[ $# -ge 2 ]`. [agent-verified]
- **M7** `lib/butin/core.awk` (whole file) + `ports/BUTIN.md` · `core.awk` has no locale guard of its own; it relies entirely on every caller having exported `LC_ALL=C`. The port spec handed to third-party adapters never states the requirement. Under this machine's ambient `fr_FR.UTF-8`, `awk -f core.awk` prints `0,0000` — comma decimals — for every dollar figure (I hit this myself mid-audit). The three shipped callers all export `LC_ALL=C`, so the data plane is safe *today*, by convention only. Fix: state the requirement in `ports/BUTIN.md`; consider a `BEGIN` guard. [reproduced]
- **M8** `bin/amiral-butin:73-82` vs `152-156` · An **absent** log gives the friendly "no routed tasks yet" onboarding; an **empty but existing** log runs the full report and prints `Coverage: 0/0` plus the "your brain and hands are on the same tier" diagnostic — a specific conclusion drawn from zero data. Fix: treat a 0-byte log as absent. [agent-verified]
- **M9** `adapters/claude-code/butin-collect.sh:58,108-109` · `pricing_version` is computed twice (the first, with its `head -1` guard and `unknown` fallback, is dead) and **emitted twice in the same JSON object**. A leftmost-match awk reader and a real JSON parser (`jq`, Python: last key wins) would disagree about the value. Fix: compute once, emit once, keep `head -1`. [code-read]
- **M10** `uninstall.sh:8-23` · Never removes `~/.claude/butin/` — `core.awk`, `pricing.tsv`, `butin-collect.sh`, `adapter.sh` are all orphaned after uninstall. Fix: `rm -rf "$CLAUDE_DIR/butin"`. [code-read]
- **M11** `adapters/claude-code/butin-collect.sh:28,48,109` · Agent/model strings are interpolated into the JSONL line with no JSON-escaping. A value containing a backslash (`agent_type:"grunt\"`) produces a line that fails strict JSON parsing (`python -m json.tool`: "Expecting ',' delimiter"). `core.awk`'s regex parser happens to tolerate it, but `jq` and any future dashboard break, and it is a genuine structural-injection surface. Fix: build `LINE` with `jq -n --arg`, or escape `\` and `"`. Refines N6: no *command* injection exists, but *structured-data* injection does. [agent-verified]
- **M12** `adapters/claude-code/butin-collect.sh:21,50` + `bin/amiral-doctor:90` · `butin-errors.log` records the raw `transcript_path`, which under `~/.claude/projects/<dash-escaped-project-path>/…` embeds the OS username and the full project directory name (client / employer / codename). `amiral-doctor:90` then points users at that file ("see $BE"), nudging it into bug reports. Fix: log a basename or hash; or document "do not paste publicly." [agent-verified]

---

## LOW

- **L1** `bin/amiral-butin:5,133` · The script exports `LC_ALL=C`, which makes its own `printf "%'d"` thousands-grouping permanently inert. The premium-token number never gets separators. Fix: drop the flag or group manually in awk. [reproduced]
- **L2** `lib/butin/core.awk:6-8` · `j()`'s string regex doesn't understand JSON backslash-escaping; a value containing `\"` truncates at that byte. Low impact today (agent names are a controlled vocabulary), but it is the same class of bug as C3. [agent-verified]
- **L3** `bin/amiral-butin:99-100`, `lib/butin/core.awk:54,57` · Dead code: `GROSS` and `TASKS` are parsed and never used (and `core.awk` never emits a `TASKS` tag at all); two distinct version-skip counters both print under the identical `SKIPPED_V` tag, and neither is ever consumed. [code-read]
- **L4** `bin/amiral-doctor:81-82` · Same `grep -c || echo 0` double-zero bug as C5; here it only garbles the display (`(0\n0/0\n0 tasks measured)`). [agent-verified]
- **L5** `bin/amiral-trust:11`, `hooks/subagent-verify.sh:17`, `bin/amiral-doctor:99` · The non-git fallback `|| pwd` returns the logical path while git returns the physical one; on macOS (`/tmp` → `/private/tmp`) the same directory can produce two different trust fingerprints. Fix: `pwd -P`. [agent-verified]
  **FIXED v0.15.1**: all three fallbacks changed to `|| pwd -P`. Structural regression test in `tests/test-trust.sh`.
- **L6** `bin/amiral-butin:71` · Stale comment describing an init/rebaseline block that moved to line 25. `bin/amiral-journal:5` · header comment omits the `note` arm. [code-read]
- **L7** `adapters/claude-code/butin-collect.sh:111` · The comment justifies append atomicity with `PIPE_BUF`, which governs **pipes**, not regular files. The behavior is fine — `printf` issues one `write(2)` and `O_APPEND` makes offset-and-write atomic — but the stated reason is wrong, and the thing actually protecting it is the 4000-char cap keeping the line inside one stdio buffer. Fix the comment so the next person doesn't "optimize" the guard away. [reproduced — see N1]
- **L8** 7 call sites · Bare `shasum` with no `sha256sum`/`openssl` fallback, in a codebase that otherwise carefully chains BSD/GNU alternatives. Breaks on minimal containers. [code-read]
- **L9** `bin/amiral-journal:89` · The badge URL hardcodes `%2B` ("+") before `$NET`; a net-negative period renders `net_%2B$-22.5000` — double-signed and confusing. Correctly *not* hidden (honest), just malformed. Fix: pick the sign glyph from NET's sign. [agent-verified]
- **L10** `hooks/subagent-verify.sh:19-26` · Beyond the ACE in H9, the fingerprint is `repo_root + verify.sh hash` only, so a *different* repo later checked out at a previously-trusted path with a byte-identical verify.sh (e.g. a copy of this project's own public template) silently inherits trust. Fix: bind trust to the remote URL/commit too. [code-read]
  **FIXED v0.15.1**: the fingerprint gained a third field, `repo_root::sha::identity`, where identity is the remote origin URL, or failing that the root (first) commit, or else empty (unanchored). All three files (`bin/amiral-trust`, `hooks/subagent-verify.sh`, `bin/amiral-doctor`) compute the identity identically and match whole-line (`grep -qxF`), never parsing fields — a remote URL legitimately contains colons. Old two-field entries no longer match; previously-trusted repos must re-run `amiral-trust` once (the safe direction). Repro'd in `tests/test-trust.sh`. **Scope (post-review honesty)**: this closes the *accidental* collision (a public-template clone landing where a real project was once trusted). It is NOT an authentication boundary — the origin URL is a local, unauthenticated string, so a local attacker who already controls the checkout can forge it (`git remote add origin <old-url>`); that adversary is outside what any path-scoped trust file can defend, and the docs/code now say so explicitly rather than implying otherwise.

---

## Doc drift

| # | Doc claim | Code truth | Fix |
|---|---|---|---|
| D1 | `docs/butin.md` (whole file) documents only hook wiring | `init`, `rebaseline`, `add-model`, `refresh-pricing`, `--haircut=N`, `--detail` all ship and are documented **nowhere** a user would look | Add a commands section |
| D2 | `docs/butin-spec-v2.md:21-22` — verify marker "implemented in v0.10" | No producer exists (H2) | Fix code, or demote to roadmap |
| D3 | `docs/butin-spec-v2.md:22` — marker fresh "< 5 min" | Collector uses 300s; the journal hook uses `-mmin -60` (12× looser) | Unify on one constant |
| D4 | `README.fr.md:52` — "6 fichiers markdown" | `README.md:322` says 7; `CHANGELOG.md:108` records fixing this lie in EN and **missed the FR** | 7 |
| D5 | `bin/amiral-setup:20`, `shell/amiral-profiles.ps1:26` — Fable metered "after Jul 7, 2026" | Rest of repo says Jul 11/12. **Today is Jul 11** — the stale string tells users metering began 4 days ago | Fix both strings |
| D6 | `adapters/claude-code/adapter.sh:8` advertises `statusline_surface` + `quota_snapshot`; `ports/BUTIN.md:14-15` describes capability negotiation | Neither capability exists; `adapter_capabilities()` is never called by anything | Drop the claims until built (see DESIGN-NOTES.md §1) |
| D7 | `README.md:178,189-201` — plugin install, "no scripts to run" | The plugin route installs **no** `bin/`, `butin/`, or hooks — no butin, journal, doctor, trust, savings, report | One explicit line saying so |
| D8 | `docs/hooks.md:30` — "wraps execution in a 300s `timeout`" | No timeout binary on macOS (H5) | Fix code |
| D9 | `bin/amiral-journal:91` usage string | omits nothing, but `bin/amiral-butin` has **no** top-level help at all listing its own subcommands | Add `-h` |
| D10 | `README.md:359` — "`amiral doctor`" | Command is `amiral-doctor` | Hyphen |
| D11 | `docs/butin.md:3` — "Add to `~/.claude/settings.json`" wiring snippet | Wires the collector that C1 shows has never worked | Fix C1 before anyone follows this doc |

---

## Attacked and held (non-findings, stated so they are not re-litigated)

- **N1 — Parallel appends are safe.** 200 concurrent 400-byte appends: all 200 lines intact, no interleaving. `O_APPEND` + single `write(2)` is the real guarantee (not `PIPE_BUF` — see L7). **[reproduced]**
- **N2 — Transcript *content* cannot poison token extraction.** A tool result containing `{"input_tokens": 999999999}` as text does not match the extractor: JSONL escapes the inner quotes (`\"input_tokens\"`), so the regex misses it. I tried and it did not fire. The real poisoning vector is C2, which needs no attacker at all. **[reproduced]**
- **N3 — Brain premium can only ever be a penalty.** `core.awk:25-28` computes `p = real − cf` and adds it only when `p > 0`; brain events are excluded from `n[]`/`real_sum`/`cf_sum`, and `brain_prem` only ever enters `net` as a subtrahend. A cheap brain earns no credit. **Holds.** **[code-read + their own T6b]**
- **N4 — `rebaseline` does not re-price history.** The counterfactual is computed at write time and stored per event; nothing recomputes it. The "future-only" promise is real. **[code-read]**
- **N5 — `LC_ALL=C` holds end to end in the shipped CLI.** All three callers export it before any awk runs, including inside the generated commit hook. Safe today — but by convention, not by construction (M7).
- **N6 — No *command* injection found** (but structured-data injection exists — M11). Model/agent/session values reach `grep -oE` patterns, `awk -v`, and `printf %s`; there is no `eval` and no unquoted expansion into a command position. `SESSION` interpolates into a state-file path, but it originates from the harness (a UUID), not attacker-controlled input. The one place hostile bytes *do* cause damage is the un-escaped JSON write (M11) — a data-integrity bug, not code execution.

---

## What blocks wiring the collector on real data

**C1 blocks it outright**, and C2 blocks it again immediately after. Until both are fixed, every event written to `butin.jsonl` is a fabrication — wrong agent, wrong model, wrong tokens, and the brain's context re-billed once per subagent. Wiring the hook today does not produce a small error; it produces a ledger with no relationship to what the fleet actually did, which then feeds the badge (C5), the commit trailers (H3, H4), and any published benchmark.

The fixes that must land together before any number is trusted or published:
1. **C1** — read `agent_type` + `agent_transcript_path`, and rewrite the fixtures so the tests can fail.
2. **C2 + H10** — take the model from the same line as the tokens, and sum *all* usage blocks, not the last.
3. **C7 + C4** — a lost event must never be able to masquerade as full coverage, and a corrupt state file must never delete an event.
4. **H8** — the escalation formula. This is the one defect that inflates the headline number through the accounting engine itself rather than through bad input: a *failed* cheap route books a *profit*. Both corsaire passes reproduced it independently against the shipped `pricing.tsv` (haiku→sonnet: reported +$0.02 / +$0.08 depending on token mix, truth −$0.01; haiku→opus baseline: +$0.80). It holds for every model pair in the table, because every baseline is >2× its cheap tier.

Separately, before the **journal/attestation** surface is presented as provenance anyone can defend: **H9** (the trust gate is one `source` away from arbitrary code execution — reproduced), **H2** (a `green` Verified trailer is forgeable from any stray marker — reproduced), **H3** (amend attests the hash of nothing and stacks trailers 3-deep — reproduced), and **H4/C6** (routing leaks cross-repo by default; the cost-consent gate is a no-op without a TTY). These do not block the *butin* math, but they block calling the journal "proof."

Note on process: C5/C7/H7/H8 were each reproduced independently by two separate adversarial passes and by my own battery — three-way agreement. H8 in particular is not a corner case; it is the design's signature workflow (route cheap, escalate on failure) producing a fabricated gain.
