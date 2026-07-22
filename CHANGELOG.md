# Changelog

## v0.17.0 - 2026-07-21
**npm distribution — `npm i -g @rompomepome/amiral` puts two commands on
PATH and does NOTHING else; config still only lands in `~/.claude` when
you knowingly run `amiral-install`.**
- **The name is `@rompomepome/amiral`, not `amiral`.** Bare `amiral` is
  already taken on npm (v0.3.2, an unrelated author's package); the
  scoped name was free. First publish of a scoped package defaults to
  **restricted** (a paid-plan requirement that would silently fail), so
  both `package.json`'s `publishConfig.access: "public"` AND an explicit
  `--access public` on `npm publish` are required — either alone is not
  enough.
- **No `postinstall`, ever — this is the whole point, not an oversight.**
  `npm i -g @rompomepome/amiral` installs the package and exposes
  `amiral-install`/`amiral-uninstall` on PATH. That's it. It does not
  touch `~/.claude`, your shell rc, or `settings.json`. A package that
  rewrites agent config the moment `npm i` runs is exactly what security
  teams block and contradicts "nothing surprising, nothing hosted" — so
  installing into `~/.claude` stays a second, explicit, knowing command
  (`amiral-install`), same effect as the git-clone `./install.sh` route.
  A new battery (`tests/test-npm-pack.sh`) makes this a regression test,
  not a promise: it packs the real tarball, `npm i -g`s it into a
  hermetic temp prefix + temp HOME, and asserts `~/.claude` stays empty
  until `amiral-install` is actually run — plus it greps the packed
  `package.json` for `postinstall`/`preinstall`/`install` scripts and
  fails loudly if any exist.
- **`files:` allowlist ships what `install.sh` needs, not the audit
  trail.** The tarball carries `install.sh`, `uninstall.sh`, `CLAUDE.md`,
  `agents/`, `skills/`, `shell/`, `bin/`, `lib/`, `adapters/` (plus the
  README/LICENSE npm always includes) — and explicitly NOT `tests/`,
  `AUDIT-FABLE*.md`, `DESIGN-NOTES.md`, `IDEAS.md`, `docs/`,
  `BENCHMARKS.md`, `CHANGELOG.md`, `examples/`, `.claude-plugin/`, or
  `.github/`. The pack test spot-checks both directions (critical files
  present, audit/docs cruft absent) so the allowlist can't silently drift
  wider or narrower.
- **`install.sh`'s `REPO_DIR` is now symlink-safe.** npm invokes
  `amiral-install` through a symlink in its global bin dir; the old
  `dirname "${BASH_SOURCE[0]}"` resolved to npm's bin dir instead of the
  installed package, which would have made every `cp "$REPO_DIR/..."`
  fail silently on first real use. Replaced with a portable symlink-chain
  walk (POSIX `readlink`, not GNU `readlink -f`, which BSD/macOS lacks)
  that still no-ops correctly for the plain `git clone && ./install.sh`
  path (a non-symlink `BASH_SOURCE` just skips the loop).
  `uninstall.sh` needed no change — it only ever reads `$CLAUDE_DIR`, never
  a `REPO_DIR`.
- **Publish is tag-gated and provenance-signed.** A new, separate
  `.github/workflows/publish.yml` triggers only on `v*` tag pushes (never
  on every commit/PR, unlike `ci.yml`) — so npm's version/download
  counter only moves on real releases. `permissions: id-token: write` on
  this public repo makes `npm publish --provenance` free (no signing keys
  to manage); a guard step fails the run if the pushed tag doesn't match
  `package.json`'s version, so a mistagged release can't publish the
  wrong (permanent) version to npm. The pack test runs first as a
  pre-publish gate.
- **CI now catches version drift between the two distribution
  channels.** A new step fails if `package.json`'s version and
  `.claude-plugin/plugin.json`'s version disagree — the same class of
  drift the existing agents-manifest guard catches for `core.awk`'s
  attribution list. `plugin.json` bumped 0.16.0 → 0.17.0 to match.
- **README gets an honest "Option C — npm"**, same tone as the
  Plugin-manifests table row: states the scoped name (not the unrelated
  bare `amiral` package), what npm install gives you (two PATH commands)
  and explicitly does NOT do (touch `~/.claude`/rc/settings.json), then
  the explicit `amiral-install` step, with the one-line WHY for the
  two-step split.
- **IDEAS.md's adoption-counting note updated from aspiration to
  shipped:** npm download counts + Claude Code plugin-marketplace
  installs + `gh api repos/Rompomepome/amiral/traffic/clones` are the
  honest signals (stars undercount — people copy a repo URL to their
  agent, they don't star). A home-grown telemetry ping stays permanently
  off the table.

## v0.16.0 - 2026-07-21
**Phantom receipts stop depressing coverage — WITHOUT hiding real data
loss; the front door leads with measured numbers instead of borrowed
ones; and the uninstall/new-user paths finally get tested.**
- **Phantom (noise) split from LOSS (real gap), and only the noise leaves
  the coverage denominator.** A large share of the log was unmeasurable
  events reading `transcript absent…`. v0.14.0 established why: on this
  build SubagentStop fires only for internal/ephemeral agents whose
  `agent_transcript_path` is minted but NEVER written — pure phantoms.
  But "never written" and "removed" are opposite cases: a transcript that
  DID exist (discovery only mints for files on disk) and was later
  garbage-collected is a REAL task whose measurement was lost, and
  excluding *that* would make genuine data loss invisible. So the fix is a
  split, not a blanket exclusion:
  - **source** — the receipt hook records `"observed"` on each receipt
    (both mint sites only fire when the transcript exists on disk), and
    the plain worker branch no longer mints for an absent transcript at
    all (discovery covers every real one, so nothing is lost);
  - **measure** — at TTL expiry, `observed:true` → reason `transcript
    removed…` (a **LOSS**, which STAYS in the coverage denominator,
    surfaced not hidden); otherwise → `transcript never written
    (phantom…)`;
  - **display** — `core.awk` counts phantoms in a separate `PHANTOM`
    bucket (out of the denominator) but keeps `removed`/LOSS and every
    other reason (e.g. `unknown pricing_id`) IN it. Phantoms are still
    shown on their own labelled line and in `--detail`; nothing is hidden.
    Events minted before the split carry the old combined reason and
    can't be re-split (their receipt is already drained) — presumed
    phantom on the v0.14 evidence, and `--detail` says so.
  Net effect on the author's real log: coverage stopped counting the
  self-generated phantom noise as missed work, printed in the tool's own
  shape (`measured/total · pending · unmeasurable`, phantoms excluded) —
  see BENCHMARKS.md for a dated figure. Statusline inherits it (one
  calculator).
- **`core.awk` is locale-safe by construction (audit M7).** It has no
  locale guard of its own and printed comma-decimals (`848,00`) under a
  non-C `LC_NUMERIC` — safe only by the convention that callers export
  `LC_ALL=C`, a convention that had already failed on the doc author and
  on third parties `ports/BUTIN.md` invites to call it directly. Every
  `%.4f` field now routes through a helper that forces a `.`, so the
  output is correct regardless of the caller's locale; a regression test
  runs it under `fr_FR.UTF-8`.
- **`examples/` — five real routed tasks, end to end.** Each is an actual
  task from this repo's own build, with the verbatim request, the triage,
  the agent+model, and the measured cost vs the Opus baseline (every
  dollar a real `butin.jsonl` event; usernames/paths stripped). Includes
  the one where the admiral **refused to delegate** — trivial tier, the
  hand-off costs more than the edit, no worker spawned, no receipt
  written. Linked from the README with a before/after trace at the top.
- **BENCHMARKS.md leads with a measured row, not a borrowed one.** A
  **dated, explicitly still-growing** observational row from the author's
  multi-week backfill (baseline Opus, ~70 amiral-routed tasks and
  climbing, other-subagent activity excluded, decomposition-bias caveat),
  stated plainly as OBSERVATIONAL — what was actually spent vs the same
  tokens at baseline — NOT the A/B protocol below it, and never "amiral
  saves you". Two rules keep it honest against a reader who runs the
  command: coverage is quoted in the tool's OWN shape (`measured/total`,
  pending included — no invented prettier ratio), and the aggregate is
  marked a point-in-time snapshot of an append-only log (a re-run reads
  higher — that's the ledger growing; the stable, checkable data is the
  per-task events in `examples/`). Reproduce your own in two commands
  (`amiral-butin backfill --all`, then `amiral-butin`). The pavillon badge
  (≥20 tasks) is **generated on demand** via `amiral-journal flag` — NOT a
  hardcoded shields.io image, which would drift out of date permanently
  and no CI could catch it.
- **Uninstall completeness (AUDIT-FABLE M10, closed).** `uninstall.sh`
  removed three files from `~/.claude/butin/` and orphaned the rest
  (measure.py, backfill.py, agents.sh, core.awk, pricing.tsv, …); it now
  `rm -rf`s the whole `butin/` dir (after the statusline restore, which
  still runs first). A new battery fails if any file survives.
- **The new-user path is finally tested.** Everything had only ever been
  validated on a machine with six weeks of state; a new battery walks a
  clean install end to end against a temp HOME (install → wire → `init`
  → one measured task → first report) and fails if any step needs
  undocumented manual intervention. It found none — `init` on a clean
  HOME falls back to the conservative Sonnet baseline without prompting.
- Fix: `amiral-journal flag` now resolves `core.awk` installed-first then
  repo-checkout (the fallback `amiral-butin`/`cache.sh` already had), so
  the badge works from a fresh clone and never pins to a stale installed
  calculator.

## v0.15.2 - 2026-07-20
**Front-door truth pass — the README sold guarantees the code no longer
backs, the same class of defect as a false provenance trailer.**
- **Trust gate claim rewritten to the guarantee that holds.** The README
  pitched `amiral-trust` as "checksum-pinned … so it never runs an
  untrusted repo's verify.sh" — the exact guarantee AUDIT-FABLE H9
  disproved and v0.15.1 already removed from docs/hooks.md. Now matches
  the code: the checksum pins verify.sh's own bytes + the repo identity;
  anything it sources or execs runs unfingerprinted, so trusting a repo
  means trusting its whole build. "tamper-evident" and "never runs
  untrusted" are gone from both READMEs.
- **Default brain corrected fable → opus.** The fleet table said
  `AMIRAL_BRAIN=fable` while the code (`${AMIRAL_BRAIN:-opus}`) and
  install.sh both default opus. Fixed in the model-agnostic example and
  the table; `amiral-ultra` is the one profile that still falls back to
  Fable, and is now stated as the exception rather than the rule.
- **Plugin route stated honestly.** "Install as a native plugin — no
  scripts to run" overstated what it gives you: the plugin ships the
  agents + `/amiral:plan-ship` only. The row now says plainly it does
  NOT install butin, the journal, the statusline, doctor, backfill, the
  shell profiles, or the global routing policy — those need
  `./install.sh`.
- **The measurement/provenance layer was invisible at the front door.**
  Added a statusline row to "What's inside", and fixed the journal row
  (plus a takeaways bullet) that still named the removed
  `Verified`/`Attest` trailers instead of the live
  `Route`/`Diff-Digest` — the same dead-trailer claim v0.14.0 fixed
  elsewhere, missed here because the CI guard only grepped for the
  hyphenated `Amiral-`-prefixed forms.
- **The Fable cliff rewritten as past-tense fact.** It was future-framed
  ("why this matters right now", "metered after July 11") past the
  July 12 cutover — now the redeployment terms read as the event that
  already happened.
- **README.fr.md carried the same drift** (dead trailers, future tense,
  plugin overclaim, a stale "6 fichiers") and got the parallel
  corrections. It drifted before because the trailer CI guard only
  grepped the English README.
- **Two drift guards so this can't come back.** The dead-trailer guard
  is now case-insensitive, and a new guard fails CI if either README
  claims the trust gate prevents running untrusted code or calls it
  tamper-evident — order-agnostic, so it catches rewordings ("never runs
  untrusted", "untrusted code never runs", "tamper evident" without the
  hyphen) while still allowing the honest scoped "refuses to run
  untrusted … until you trust it".
- **`AMIRAL_CONSENT_TIMEOUT`** (default 60, digits-only-validated, min 1,
  else 60): the `--with-cost` consent `read` opens the real `/dev/tty`,
  so a redirected stdin doesn't neutralize it — J-17/J-20/J-21 each
  blocked ~60s on a developer machine (CI has no controlling tty, so it
  never showed there). The tests set it to 1. Shortening the timeout
  only makes the gate fail closed FASTER — it can NEVER skip the prompt;
  the sole non-interactive consent path remains the explicit `--yes`.
  Journal battery: ~3 min → ~4.5 s.
- Consistency: the "N markdown files" framing is now uniformly 7
  (5 agents + CLAUDE.md + SKILL.md) across both READMEs, and
  `.claude-plugin/plugin.json` bumped 0.12.2 → 0.15.2 to match the
  shipped version.

## v0.15.1 - 2026-07-20
**Security lot (C6/H9/L5/L10 + TOCTOU + a FIFO DoS), and a BSD-first
`stat` chain that corrupted the discovery ts on Linux — the validation,
not the ordering, is what protects.**
- **C6: the `--with-cost` consent gate now fails closed on ANY network
  remote.** The old check only matched `github.com|gitlab.com`, so
  publishing the `Amiral-Net-Saved` cost trailer onto a Bitbucket,
  Codeberg, self-hosted, or `git@host:` ssh remote skipped the consent
  warning entirely — a hostname denylist can never enumerate every
  public forge. Inverted: any remote pointing at a network host is
  consent-worthy; only filesystem paths and loopback are skipped
  (over-asking on a private host is harmless, missing a public one is
  the leak). No controlling terminal and no explicit `--yes` now
  REFUSES — the hook is not written — instead of the warning printing
  and being instantly swallowed.
- **H9: the trust gate's docs now state the guarantee that actually
  holds.** docs/hooks.md and the amiral-trust / hook headers dropped
  "tamper-evident": the checksum pins verify.sh's OWN bytes only, and
  anything it sources or execs (helper scripts, `npm test`, a Makefile,
  node_modules) runs unfingerprinted. Static `source`/`exec` detection
  and hashing the transitive read-set were both rejected as unsound in
  shell (a build reads files chosen at runtime by `$PATH`/`npm`/`make`);
  the honest scope is "trusting a repo means trusting its build."
- **TOCTOU:** the hook re-hashes verify.sh immediately before running
  it and refuses on mismatch, shrinking the check→run window where the
  file could be swapped after the trust match.
- **L10: trust bound to repo identity.** The fingerprint gained a third
  field (`repo_root::sha::identity`, identity = remote origin URL, else
  the root commit), so a DIFFERENT repo checked out at a
  previously-trusted path with a byte-identical verify.sh no longer
  inherits trust ACCIDENTALLY. Stated honestly in docs and
  AUDIT-FABLE: this is NOT an authentication boundary — a local attacker
  who already controls the checkout can forge the origin URL; it closes
  the accidental collision, not a deliberate repo-swap. Old two-field
  entries stop matching; previously-trusted repos re-run `amiral-trust`
  once (the safe direction).
- **L5:** the non-git `|| pwd` fallback returned the logical path while
  git returns the physical one (`/tmp` → `/private/tmp` on macOS),
  yielding two fingerprints for one directory — now `pwd -P` in all
  three sites (trust, hook, doctor).
- **FIFO DoS:** `[ -x ./verify.sh ]` was true for an executable FIFO,
  and `shasum` on a FIFO with no writer blocks forever — upstream of the
  300s timeout wrapper. A `-f` regular-file guard closes it in the hook
  and doctor (git can't check out a FIFO, but a build step or a tar
  entry can drop one).
- **BSD-first `stat` chain corrupted the discovery ts on Linux**
  (surfaced by test-butin D-5 going red on ubuntu). `stat -f %m … ||
  stat -c %Y` is unsafe in that order: on GNU, `-f` means
  `--file-system`, so `%m` is parsed as a FILENAME — stat prints
  filesystem info to stdout AND exits non-zero, so the `||` appends the
  epoch to that garbage (multi-line, non-numeric), and `date` then fails
  both ways. Flipped to GNU-first, and — the load-bearing part —
  VALIDATE the result is digits-only after each form (same for the
  `date -d @epoch` / `date -r epoch` pair): it is the validation, not
  the ordering, that protects; empty/invalid degrades to the documented
  default instead of propagating. Never chain on exit status alone when
  the failing branch can write to stdout. A D-5b regression fails if a
  non-numeric epoch is ever accepted.
- A new `tests/test-trust.sh` battery (H9-honesty, L10 repro, TOCTOU,
  L5, FIFO, fingerprint agreement across the three sites) and
  consent-gate journal tests (Bitbucket + ssh repros); CI runs the trust
  battery on both ubuntu and macOS.

## v0.15.0 - 2026-07-19
**Attribution split — the report credited amiral for routing it never
performed, the single most attackable claim in the tool.**
- **The headline NET summed every worker agent**, including subagents
  Claude Code (or a user's own custom agent) spawned on their own — so
  "net saved" attributed savings to amiral that it never routed. A live
  backfill over six weeks surfaced 9 agent types; only 5 are amiral's
  (the ones it ships in `agents/`). `core.awk` now partitions every
  worker event (and its escalation cost) into an amiral bucket and an
  "other" bucket, and the report hero, the statusline (`net_total`), the
  pavillon badge, AND the `--with-cost` commit trailer all show
  amiral-routed savings ONLY.
- **Other subagent activity is still measured** — it is real data — and
  shown on its own clearly-labelled line, never mixed into the amiral
  figure. The brain keeps its own premium accounting, in neither bucket.
  A user's own custom agent falls in "other" (amiral did not route it).
- **The amiral agent set is derived from what the repo actually ships,
  not a hardcoded list that can drift.** It is materialized in
  `lib/butin/amiral-agents.txt` and read through a shared
  `lib/butin/agents.sh`, with a CI drift guard that fails if the
  manifest and `agents/*.md` diverge — so the set can't silently widen
  or narrow. An unset agent set degrades to legacy all-amiral output,
  byte-identical to pre-split (every existing caller stays correct
  without change).
- **The `--with-cost` commit trailer was the fourth consumer** and was
  emitting the mixed total; it now resolves the same manifest so the
  `Amiral-Net-Saved` git trailer is amiral-routed only too, and the
  pavillon badge's task count is amiral-routed (advertising a mixed
  count next to an amiral-only net was the same over-claim one column
  over). Documented in DESIGN-NOTES.md and docs/butin-spec-v2.md;
  +9 butin / +2 statusline / +2 journal battery tests.

## v0.14.1 - 2026-07-19
**Backfill — past sessions were invisible; plus dated model-id
normalization (strip the date once, never guess).**
- **`amiral-butin backfill` mints receipts for PAST sessions' real
  subagent transcripts.** Live discovery (v0.14.0) only ever scans the
  CURRENT session's `subagents/` dir each turn, so every worker
  transcript from a session you've since closed sat on disk invisible to
  the butin forever. Backfill walks the project transcript dirs, finds
  the `agent-*.jsonl` files with no receipt, and mints one each under the
  SAME rules as live discovery (hostile-path guard, stable-gate, dedup
  against both `receipts.jsonl` and `butin.jsonl`) — it MINTS only, never
  measures, so a `--dry-run` writes nothing at all. Scope defaults to the
  current directory's project; `--all` covers every project. The author's
  own first run recovered **87 receipts across 18 sessions, six weeks of
  history** that had been uncounted.
- **Dated model-id normalization** (`measure.py`): a pricing-table miss
  on the platform's own reported id (e.g. `claude-haiku-4-5-20251001`)
  now retries ONCE after stripping a trailing `-YYYYMMDD`, then prices at
  the dated id if that hits — it never guesses a base model from a
  partial match. A model that is genuinely unpriced stays one honest
  `unknown pricing_id` unmeasurable event, not a fabricated rate.
- **Review fixes (fresh context):** the receipts file gained a lock so a
  concurrent backfill and a live receipt append can't interleave a line;
  the stable-gate honors `BUTIN_STABLE_SECS` on the backfill path too
  (a transcript touched in the last 60s stays pending, same 6.7x lesson);
  and an empty-after-strip model id can no longer produce an empty-string
  receipt field. `+269` lines of battery coverage.

## v0.14.0 - 2026-07-18
**Receipt-by-discovery (the butin was blind to workers), mixed-model
pricing, an evidence-gated diagnostic, and journal wave 2 — stop
claiming, don't fake proving.**
- **CRITICAL fix: worker receipts are now produced by DISCOVERY, because
  SubagentStop does not fire for Task agents on this platform build.**
  Investigated live (2026-07-18, Claude Code 2.1.214): 9 real subagent
  transcripts on disk, 0 receipts for them — a controlled synchronous-
  agent experiment wrote its transcript instantly and receipts.jsonl
  did not move. The only SubagentStop events observed came from
  internal/ephemeral agents whose `agent_transcript_path` is minted but
  NEVER written (20/20 historical orphan receipts + 2/2 live: session
  dirs still alive holding 6–13 other real transcripts, the named file
  never existed — the earlier "platform GC'd them" explanation was
  wrong). The Stop hook, which does fire every turn, now scans the
  session's `subagents/` dir and mints receipts for real transcripts:
  ts = transcript mtime (actual completion time), identity from the
  `.meta.json` sidecar as before, dedup by transcript path against both
  receipts and events (events now carry `"transcript"` — additive,
  readers ignore unknown keys). The SubagentStop path is kept as a
  fallback that dedup absorbs if a future build revives it. Validated
  against this session's own data: 8 workers measured on the first
  pass, 3 streaming ones honestly pending, 1 honestly unmeasurable
  (re-validated after review fixes: 12 workers, +$102.90 net surfaced).
  `BUTIN_RECEIPT_TTL_HOURS` default drops 48 → 6 and the expiry reason
  becomes "transcript absent (never written or removed)" — the flush
  race is minutes, and the old wording claimed the file once existed,
  which the evidence refuted. ports/BUTIN.md platform findings
  rewritten accordingly.
- **Fix: mixed-model transcripts priced at ONE model's rate**
  (AUDIT-FABLE C2, resurrected on the brain path): measure.py kept a
  single `model` variable overwritten per line, so a mid-session
  `/model` switch (opus → fable) billed EVERY deduped turn at the final
  model's rate. Turns are now grouped BY MODEL and ONE EVENT PER MODEL
  is written — each schema-pure (`chosen_model` prices exactly the
  tokens attributed to it, counterfactual at baseline over the same
  slice), core.awk unchanged (no second accounting implementation).
  Coverage counts priced slices; single-model receipts are unchanged.
  ALL-OR-NOTHING: any unpriced model in the mix makes the whole receipt
  ONE unmeasurable event (pricing only the known slice would undercount
  — an invented "measured" figure). Brain dedup supersedes the whole
  per-session event SET now, not a single event.
- **Fix: the report's tier diagnostic lied twice** (AUDIT-FABLE M8
  class): "brain and hands are on the same tier" printed in two
  wordings (a rewrite forgot to remove the original), and its trigger
  (zero grunt tasks + net ≈ 0) fired on ONE measured brain event with
  2 workers pending — a specific conclusion from near-zero data, and
  factually wrong on the live log. The no-data trigger is gone; the
  single remaining diagnostic (core.awk's DEGENERATE flag) prints only
  with ≥3 measured worker events AND pending under 25% of total.
  Silence beats a wrong diagnosis.
- **Journal wave 2 (AUDIT-FABLE H2/H3/H4) — stop claiming:**
  - H2: `Amiral-Verified` REMOVED — nothing ever produced its marker,
    and the consumer matched any session's marker via a global glob, so
    a bare `touch` forged "green" in a repo with no verify.sh. A real
    gate-backed producer can come later; a forgeable claim cannot ship.
  - H3: `Amiral-Attest` renamed **`Amiral-Diff-Digest`** — it is a
    recomputable digest of verify.sh's bytes + the commit's diff:
    proves what was PRESENT, not what was RUN. Amend (`--no-edit`/
    editor path) now folds in the committed diff (`git show $3`), so a
    message-only amend no longer degenerates to the hash of nothing;
    if the diff is empty AND verify.sh absent, the trailer is omitted
    entirely. Known residual, documented: `--amend -m` reaches the hook
    as source "message" (a git limitation) and keeps the staged-diff
    digest — it can miss content, never fabricate.
  - H4: `Amiral-Route` scoped to THIS repo — events are filtered by
    their recorded `cwd` (repo root or under it) before extraction;
    cwd-less events (pre-v0.12) are excluded, never guessed. Residual
    documented: the window is still the last 50 lines of the global
    log, filtered; scoping is by recorded cwd, not a git-verified fact.
    Also fixed: the extraction grep required adjacent no-space keys and
    silently missed every measure.py (json.dumps) event.
  - Found while implementing: the hook could ABORT a commit (a trailing
    conditional's false exit became the hook's exit status) — explicit
    exit 0; plus a bash 3.2 case-in-command-substitution parser trap.
- **Corsaire pre-mortem fixes (journal, post-implementation):**
  - README.md still advertised `Amiral-Verified`/`Amiral-Attest` — the
    pitch document showing a trailer the code no longer emits is itself
    a false provenance claim. Updated to the real trailers; CI now
    greps READMEs for the dead names (the spec's honest negative
    mention is exempt).
  - Route values are echoed into the commit message from an
    unauthenticated local file: a crafted `chosen_model` could smuggle
    a fake first-position `Amiral-Diff-Digest:` line past naive greps.
    Both fields are now sanitized to `[A-Za-z0-9._-]` — inert token
    characters only, never message structure.
  - `git worktree`: `.git` is a file there, the hook write failed to
    stderr yet `enable` printed the success banner — a silent false
    claim of protection. `hook_path()` now resolves the REAL hooks dir
    via `git rev-parse --git-path hooks` (journal genuinely works from
    worktrees now), and `enable` verifies the hook landed before
    claiming success.
  - One oversized butin.jsonl line (50MB) made every `git commit` take
    16s via the per-line route loop: input is now byte-capped
    (200KB) + per-line capped (8KB) — a pathological log degrades to
    fewer routes, never a stalled commit.
  - Documented, not changed: cwd casing mismatches on case-insensitive
    filesystems can under-report (never over-report) a route; an
    unreadable verify.sh contributes zero digest bytes exactly like an
    absent one.
- **Final-review fixes (fresh context, post-implementation):**
  - Double-billing seam: the plain SubagentStop branch had no dedup —
    if the platform ever re-fires for a discovered transcript, the same
    work was billed twice. Now two layers: the hook refuses a worker
    receipt whose transcript is already receipted/measured, and
    measure.py skips (and counts, `dup_receipts`) any duplicate worker
    receipt. Brain receipts exempt — same-transcript resupersede is
    their normal flow.
  - The discovery scan grepped both logs PER FILE, every turn
    (O(dir×logs): 200 files ≈ 2.2s per turn, growing) — now one
    known-paths extraction per turn, membership checked against the
    small list (~2.3x now, gap widens with backlog).
  - Future transcript mtime (clock skew) made the stable-gate hold a
    receipt pending FOREVER (negative age < STABLE always): mint-side
    ts clamp to now, gate holds only 0 ≤ age < STABLE, TTL age clamps
    negative to 0.
  - Filenames containing quotes/backslashes/control chars would mint
    invalid-JSON receipts that measure.py then silently DROPPED on
    rewrite (permanent invisible loss + a duplicate-key field-override
    primitive): hostile names are now skipped at mint (never a corrupt
    line), and unparseable receipt lines are preserved verbatim, never
    destroyed.
  - Diagnostic gate: slice-inflation documented (a mixed-model worker
    task counts one event per model — rare, accepted); coverage label
    reworded to "N/M measured" (slices, not tasks); journal's
    `grep -v unmeasured` never matched `"unmeasurable"` — fixed.
- New `tests/test-journal.sh` battery (16 checks incl. smuggle/
  worktree/big-line/README-drift), wired into CI (ubuntu + macOS).
  Batteries: butin 28 → 53, statusline 71 unchanged.

## v0.13.2 - 2026-07-18
**Statusline: the anchor becomes the profile flag + a strict-semantics
spinner.**
- **The ⚓ anchor now leads the segment ONLY when an amiral profile
  launched the session.** Real-world check found the v0.13.1 marker
  correct but not evident: both a profiled and a bare `claude` session
  opened with ⚓, the profile name grey among grey. Now the glance IS
  the signal: anchor present = launched via a profile (exactly what the
  sanitized `AMIRAL_PROFILE` var proves — no wider claim), anchor
  absent = bare session whose butin numbers still render, unflagged.
  A text-level distinction also survives `NO_COLOR`, where any
  color-only cue dies. The profile token itself is now bold cyan
  (`\033[1;36m`) — weight plus a hue that carries no good/bad meaning
  (green/amber stay reserved for today's sign).
- **New: pending spinner with strict semantics** — a braille glyph
  (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏) next to the pending count, its frame derived from the
  cache's `generated_epoch` (frame = epoch % 10). It appears ONLY while
  `pending > 0`, and since the epoch only changes when the producer
  writes a new snapshot, the frame advances exactly when a NEW
  measurement pass lands while work is in flight — motion means "fresh
  data", never a decorative loop (same epoch = same frame on every
  re-render; proven by test). `pending == 0` with real coverage shows a
  static ⠿ ("settled" — deliberately not in the frame set); no data at
  all shows nothing. Garbage `generated_epoch` degrades to frame 0,
  never a crash. True per-second animation would need
  `"refreshInterval"` in settings.json — documented in docs/butin.md,
  deliberately not wired (our data only changes on task events).
- Amber-on-negative-day, the mute rule (a negative day is never
  hidden), corrupt-cache silence, chaining, the trust pin and the 2s
  watchdog: all unchanged.
- **Fresh-context review fixes (post-implementation):**
  - A huge ALL-DIGIT `generated_epoch` (19+ digits) passed the spinner's
    digits check but overflowed awk's C-double integer precision: `%d`
    of the modulo could land outside 0-9 (observed `-32` on macOS
    onetrueawk) and the armless case table silently dropped the glyph
    while `pending > 0` — motion gone, exactly the invariant violation.
    Epochs are length-capped (>10 digits — corrupt until year 2286 —
    degrade to frame 0, glyph still shown: its PRESENCE means pending,
    only its MOTION needs a trustworthy epoch), and the case table
    gained a default arm that fails toward frame 0, never toward
    disappearance.
  - The battery asserted SGR PRESENCE in three tests without
    neutralizing an ambient `NO_COLOR` (a growing shell convention) —
    the renderer was right, the harness fragile. `unset NO_COLOR` at
    the top, next to the existing `unset AMIRAL_PROFILE` hermeticity.
  - Plan mode showed the spinner without the pending count that
    explains it (api-mode asymmetry): plan's coverage parens now carry
    `· N pending` too — motion is never an unexplained animation.
- Battery: statusline 57 → 71 (anchor semantics incl. no-⚓-without-
  profile, bold-cyan SGR presence, spinner frame determinism/motion/
  settled/garbage-epoch/corrupt-cache cases, huge-epoch no-vanish,
  plan-mode pending parity).

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
