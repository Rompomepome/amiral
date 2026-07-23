#!/usr/bin/env python3
"""butin cold measurement (v0.12).

Reads receipts, measures each one from now-stable transcripts, and writes
measured events. Correct by construction:

  * DEDUP BY message.id — a streaming transcript writes the same turn many
    times (observed: the same id 6x). The LAST record of an id carries the
    turn's final usage. Summing every line over-counted 6.7x in v0.11.
  * MIXED-MODEL AWARE — a `/model` switch mid-session (e.g. opus -> fable)
    used to let ONE `model` variable, overwritten by every usage-bearing
    line, price ALL deduped turns at the LAST model's rate (AUDIT-FABLE C2,
    resurrected on the brain path — a real-money lie). Turns are grouped BY
    MODEL instead, and ONE EVENT PER MODEL is written per receipt, each
    priced at its own rates over exactly the tokens attributed to it. A
    mixed-model session therefore counts one measured event per model that
    priced tokens — coverage counts priced SLICES, not tasks. Single-model
    receipts are unaffected: 1 receipt = 1 event, byte-compatible with
    pre-v0.14 behavior.
  * IDENTITY FROM THE SIDECAR — .meta.json carries agentType (and
    spawnDepth), so a worker is never a nameless "worker" fallback.
  * PENDING, NOT INVENTED — if a transcript isn't there yet, the receipt
    stays pending and is retried next run. But pending isn't forever: every
    absent-transcript receipt observed on real data (20/20) pointed at a
    path that was NEVER written (a dead SubagentStop firing for an
    internal/ephemeral agent), not one that existed and was later GC'd — the
    flush race a transcript can legitimately be mid-write for is minutes,
    not hours. A receipt whose transcript is absent past
    BUTIN_RECEIPT_TTL_HOURS (default 6h — far above any real flush delay,
    far below the old 48h's pending inflation) becomes unmeasurable instead
    of being silently forgotten or advertised as pending forever. v0.16.0
    PHANTOM/LOSS SPLIT: the receipt's own "observed" field (set at mint time
    by butin-receipt.sh — true iff the transcript was seen on disk then)
    decides which of two reasons is emitted: observed=true means the
    transcript existed and is now gone ("transcript removed after it was
    recorded (existed at mint, measurement lost)" — a real LOSS, stays in
    the coverage denominator); observed=false/missing means it was never
    written at all ("transcript never written (phantom — SubagentStop path,
    v0.14)" — noise, excluded). Coverage tells the truth: measured / pending
    / unmeasurable. Likewise,
    if any model group in a receipt has no pricing_id (or the baseline
    itself is unpriced), the WHOLE receipt becomes ONE unmeasurable event —
    pricing only the known slice would undercount the transcript, an
    invented "measured" figure. No partial events.
  * REPRODUCIBLE — the same receipts + transcripts always yield the same
    number. Anyone can re-run it.
  * DUPLICATE RECEIPTS ARE DROPPED, NEVER DOUBLE-BILLED — a worker
    transcript already carrying a measured event (from an earlier run, or
    earlier in this same run) gets no second event for a later receipt
    pointing at the same path; it's counted in `dup_receipts`, not
    re-measured and not kept pending. This is belt-and-braces: the source
    (adapters/claude-code/butin-receipt.sh) now also dedups a plain worker
    receipt against receipts.jsonl + butin.jsonl before it's ever written.
    Brain is exempt — the Stop hook legitimately re-references the SAME
    main transcript every turn (the supersede flow above).
  * DATED MODEL IDS ARE NORMALIZED ONCE, NEVER GUESSED — the platform
    reports ids like "claude-haiku-4-5-20251001" (verified on real
    transcripts) while pricing.tsv holds the undated "claude-haiku-4-5". A
    pricing-table MISS retries exactly once after stripping a trailing
    -YYYYMMDD (resolve_rate()); if the stripped id isn't priced either, the
    id stays unmeasurable — never a fallback to a neighbouring model. An
    undated unknown id is never touched (no 8-digit suffix, no retry).
    chosen_model always stays the id the platform actually billed; a
    normalized slice additionally carries billed_pricing_id (the stripped
    id whose rate was used) and pricing_normalized:true — added only when
    normalization actually fired, so single-model undated events remain
    byte-compatible with pre-v0.15 output.
  * DATE-AWARE PRICING — pricing.tsv rows may carry an OPTIONAL 6th column,
    effective_from (ISO YYYY-MM-DD): a pricing_id can now have several rows,
    one undated BASE row (applies from the beginning of time) plus any
    number of dated cutover rows (e.g. an intro-pricing period followed by
    a standard rate). The rate that prices a slice is chosen by the EVENT'S
    OWN ts (the receipt's ts -- resolve_rate()/cost() take it explicitly),
    never by the date the measurement happens to run: history is never
    repriced, so the same receipts + transcripts always reprice to the same
    dollar (REPRODUCIBLE, above). A malformed effective_from (anything not
    exactly YYYY-MM-DD) skips that ROW ENTIRELY at load time -- never a
    guessed cutover date; the pricing_id's other row(s), if any, still
    work. If NO row is eligible for an event's date (e.g. a model whose
    only row is dated in the future), that's a miss exactly like an unknown
    pricing_id -- unmeasurable, never a guessed rate. A future cutover for
    any model = add one dated row to pricing.tsv, zero code changes.
"""
import calendar, json, os, re, sys, glob, time, shutil

HOME = os.environ.get("AMIRAL_HOME", os.path.expanduser("~/.amiral"))
RECEIPTS = os.path.join(HOME, "receipts.jsonl")
EVENTS = os.path.join(HOME, "butin.jsonl")
CFG = os.path.join(HOME, "butin-config.json")
PRICES = os.environ.get("BUTIN_PRICES") or os.path.expanduser("~/.claude/butin/pricing.tsv")

EFFECTIVE_FROM_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')   # ISO date, exact shape only

def load_prices():
    """rates[pricing_id] is a LIST of (effective_from_or_empty, rate_tuple)
    — a pricing_id may have one undated BASE row ("") plus any number of
    dated cutover rows (the OPTIONAL 6th TSV column). A 6th field is
    accepted only if it matches EFFECTIVE_FROM_RE exactly; a malformed date
    skips that ROW ENTIRELY (never guess a cutover date) without touching
    the pricing_id's other row(s)."""
    rates, ver = {}, "unknown"
    for line in open(PRICES, encoding="utf-8"):
        if line.startswith("#"):
            if "pricing_version:" in line: ver = line.split("pricing_version:")[1].strip()
            continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 5: continue
        eff = ""
        if len(p) >= 6:
            eff = p[5]
            if not EFFECTIVE_FROM_RE.match(eff): continue   # malformed: skip row entirely
        try: rate = tuple(float(x) for x in p[1:5])
        except ValueError: continue
        rates.setdefault(p[0], []).append((eff, rate))
    return rates, ver

def pick_rate(rows, event_date):
    """rows: the (effective_from_or_empty, rate_tuple) list for ONE
    pricing_id. Eligible rows are effective_from == "" (the undated base,
    always eligible) or effective_from <= event_date (ISO strings compare
    safely lexicographically — no date parsing needed). Among eligible
    rows, the one with the lexicographically GREATEST effective_from wins
    ("" loses to any date, so a reached cutover always outranks the base).
    If event_date is falsy (missing/empty ts), only the undated base row is
    eligible — never guess a rate for an event with no known date. Returns
    a rate_tuple, or None if no row is eligible (e.g. a model whose only
    row is a future cutover) — a miss, exactly like an unknown pricing_id."""
    best = None   # (effective_from, rate)
    for eff, rate in rows:
        if not event_date:
            if eff == "" and best is None: best = (eff, rate)
            continue
        if eff == "" or eff <= event_date:
            if best is None or eff > best[0]: best = (eff, rate)
    return best[1] if best else None

def measure_transcript(path):
    """Group deduped turns BY MODEL: a `/model` switch mid-session (e.g.
    opus -> fable) must bill each turn at the model that was active when it
    ran, not at whichever model happens to write the transcript's LAST
    usage line (AUDIT-FABLE C2, resurrected on the brain path — a single
    `model` variable overwritten by every usage-bearing line billed EVERY
    deduped turn at the final model's rate).

    turns[mid] holds the (model, usage) of that id's LAST occurrence — last
    -write-wins for BOTH, consistent with the existing dedup rule (a
    streaming transcript writes the same turn many times; only the final
    record carries the turn's true totals AND the model that produced them).

    Returns {model: [in, out, cache_read, cache_write]}, grouped and
    deduped. Returns None if the file can't be read, has no usage-bearing
    lines, or no id ever carried a model — exactly today's
    unreadable/empty/no-model None semantics."""
    if not path or not os.path.isfile(path): return None
    turns = {}   # message.id -> (model, usage) of its LAST occurrence
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if not line.startswith("{"): continue
            try: d = json.loads(line)
            except json.JSONDecodeError: continue          # torn/partial line: skip, never guess
            m = d.get("message") or {}
            mid, usage = m.get("id"), m.get("usage")
            if mid and isinstance(usage, dict):
                turns[mid] = (m.get("model"), usage)        # last write wins = final totals AND final model
    except OSError:
        return None
    if not turns: return None
    groups = {}   # model -> [in, out, cache_read, cache_write]
    for mdl, u in turns.values():
        key = mdl or "unknown"
        g = groups.setdefault(key, [0, 0, 0, 0])
        g[0] += u.get("input_tokens", 0) or 0
        g[1] += u.get("output_tokens", 0) or 0
        g[2] += u.get("cache_read_input_tokens", 0) or 0
        g[3] += u.get("cache_creation_input_tokens", 0) or 0
    if all(k == "unknown" for k in groups): return None    # no id ever carried a model
    return groups

def agent_name(transcript, hint, role):
    """Identity from the platform's own sidecar; hint is only a fallback."""
    if role == "brain": return "brain"
    side = (transcript or "")[:-6] + ".meta.json" if (transcript or "").endswith(".jsonl") else ""
    if side and os.path.isfile(side):
        try:
            meta = json.load(open(side, encoding="utf-8"))
            if meta.get("agentType"): return meta["agentType"]
        except Exception: pass
    return hint or "worker"

DATED_SUFFIX = re.compile(r'-\d{8}$')   # e.g. -20251001, exactly 8 digits

def resolve_rate(rates, model, event_date):
    """A pricing-table MISS on the platform's own reported id retries ONCE
    after stripping a trailing -YYYYMMDD (verified on real transcripts:
    the platform reports "claude-haiku-4-5-20251001" while pricing.tsv
    holds the undated "claude-haiku-4-5"). Never a second guess: if the
    stripped id isn't in the table either, stay unmeasurable. An undated
    unknown id (no 8-digit suffix) is never touched — straight miss, no
    normalization attempted, never a neighbouring model's rate.

    "Miss" now also covers a pricing_id that IS in the table but has no row
    eligible for event_date (e.g. only a future-dated cutover row) — that's
    unmeasurable exactly like an unknown id, so the same -YYYYMMDD retry
    (and, failing that, the same never-guessed outcome) applies uniformly.

    Returns (rate_tuple_or_None, billed_id, normalized_bool)."""
    r = pick_rate(rates.get(model, []), event_date)
    if r is not None: return r, model, False
    if DATED_SUFFIX.search(model):
        stripped = model[:-9]   # drop "-YYYYMMDD" (dash + 8 digits = 9 chars)
        # A model shaped LITERALLY "-YYYYMMDD" (e.g. "-20251001") strips to
        # "" — never look that up, a blank pricing-table key must never be
        # matched as if it were a real id.
        if stripped:
            r2 = pick_rate(rates.get(stripped, []), event_date)
            if r2 is not None: return r2, stripped, True
    return None, model, False

def cost(rates, model, tk, event_date):
    """Returns (cost_or_None, billed_pricing_id, normalized_bool). billed_id
    is the id whose rate was actually used (may differ from `model` when a
    dated id was normalized); normalized is True only in that case.
    event_date (the receipt's own ts, sliced to YYYY-MM-DD) picks the rate
    — REAL and counterfactual costs for the same slice always use the SAME
    event_date, so a receipt is priced consistently regardless of when it's
    measured (REPRODUCIBLE)."""
    r, billed_id, normalized = resolve_rate(rates, model, event_date)
    if r is None: return None, model, False
    c = tk[0]*r[0] + tk[1]*r[1] + tk[3]*r[2] + tk[2]*r[3]   # in, out, cache_write, cache_read
    return c, billed_id, normalized

def main():
    # LOCK: measure.py can now be invoked concurrently (hooks + report/cache.sh).
    # A crashed measurer must not wedge cold measurement forever: a lock dir
    # older than 600s is reclaimed once, then retried; otherwise we back off
    # (receipts stay pending — retried later, nothing lost).
    # This whole preamble is best-effort: any unexpected OSError (e.g. HOME's
    # parent not writable) falls back to running _measure() UNLOCKED rather
    # than crashing — locking must only ever ADD safety over the pre-v0.13
    # behavior, never subtract robustness from it (the original first line
    # of this function, `os.path.isfile(RECEIPTS)`, tolerates a missing HOME
    # gracefully; os.mkdir(lockdir) alone would not).
    lockdir = os.path.join(HOME, ".measure.lock")
    got_lock = False
    try:
        os.makedirs(HOME, exist_ok=True)
        try:
            os.mkdir(lockdir)
            got_lock = True
        except FileExistsError:
            stale = False
            try:
                stale = (time.time() - os.path.getmtime(lockdir)) > 600
            except OSError:
                stale = True   # lock vanished mid-check: treat as gone, safe to retry
            if stale:
                shutil.rmtree(lockdir, ignore_errors=True)
                try:
                    os.mkdir(lockdir)
                    got_lock = True
                except FileExistsError:
                    print("busy: another measurement is running")
                    return 0
            else:
                print("busy: another measurement is running")
                return 0
    except OSError:
        got_lock = False   # couldn't even attempt the lock — proceed unlocked, best-effort
    try:
        return _measure()
    finally:
        if got_lock:
            shutil.rmtree(lockdir, ignore_errors=True)

def _measure():
    if not os.path.isfile(RECEIPTS):
        print("no receipts yet"); return 0
    cfg = json.load(open(CFG)) if os.path.isfile(CFG) else {}
    baseline = cfg.get("baseline_model", "claude-sonnet-4-6")
    rates, pver = load_prices()
    # STABLE-GATE: 0 (default) = today's exact behavior, tests unaffected.
    # cache.sh sets this to 60 when calling from a hook.
    STABLE = int(os.environ.get("BUTIN_STABLE_SECS", "0") or 0)
    # RECEIPT TTL: 20/20 historical absent-transcript receipts were paths
    # that were NEVER written (a dead SubagentStop firing for an
    # internal/ephemeral agent, verified 2026-07-18) — not files that once
    # existed and were later GC'd. The only legitimate reason a transcript
    # is briefly absent is the flush race (minutes). A receipt can't stay
    # pending forever once its transcript is provably absent — that's false
    # completeness, not honesty. Default dropped 48h -> 6h: still far above
    # any real flush delay, while killing the old default's pending
    # inflation from phantom (never-written) receipts. 0 is legal (test
    # knob): expire immediately once the transcript is absent.
    try:
        TTL_HOURS = float(os.environ.get("BUTIN_RECEIPT_TTL_HOURS", "6"))
        # NaN != NaN — a "nan" knob must fall back to the documented default,
        # not silently mean "never expire" (every NaN comparison is False).
        if TTL_HOURS < 0 or TTL_HOURS != TTL_HOURS: TTL_HOURS = 6.0
    except (TypeError, ValueError):
        TTL_HOURS = 6.0

    done = set()
    brain_sessions = {}   # session -> True if a brain event already exists
    existing = []
    if os.path.isfile(EVENTS):
        for l in open(EVENTS, encoding="utf-8"):
            try: e = json.loads(l)
            except Exception: continue
            existing.append(e)
            if e.get("receipt"): done.add(e["receipt"])
            if e.get("agent") == "brain" and e.get("session"):
                brain_sessions[e["session"]] = True

    # F1 belt-and-braces: a receipt for a transcript that ALREADY carries a
    # measured (non-brain) event is a duplicate receipt for work already
    # priced, not a new task — e.g. a SubagentStop firing and the discovery
    # scan both recording the same transcript before butin-receipt.sh's own
    # source-side dedup existed (or any other way a duplicate line slips
    # through). Never re-measure it, never keep it pending, never write a
    # second event — just count it. Brain is EXEMPT: the Stop hook
    # legitimately re-references the SAME main transcript every turn (the
    # supersede flow below) — transcript dedup must never apply to
    # role=brain.
    measured_transcripts = set()
    for e in existing:
        if e.get("agent") != "brain" and e.get("transcript") and "real_cost_usd" in e:
            measured_transcripts.add(e["transcript"])

    kept, measured, pending, unmeasurable, dup_receipts = [], 0, 0, 0, 0
    new_events = []
    brain_replace = {}   # session -> LIST of new brain events (one per model seen
                          # on this session's latest receipt) that supersede ALL
                          # existing brain events for that session
    for line in open(RECEIPTS, encoding="utf-8"):
        try: r = json.loads(line)
        except Exception:
            # F3(b): never destroy what we can't parse. An unparseable line
            # used to be silently dropped on rewrite (permanent data loss,
            # contradicting "pending, not invented") — keep it verbatim; it
            # stays in the file for a human or a future parser.
            kept.append(line); pending += 1; continue
        if r.get("id") in done: continue
        # An id-less receipt can never be deduped against the done set, so no
        # event may ever be written for it (re-runs would double-write), and
        # r["id"] below must never raise: one malformed line crashing the run
        # would wedge EVERY other receipt in the batch forever. Keep it.
        if not r.get("id"):
            kept.append(line); pending += 1; continue
        role = r.get("role")
        transcript = r.get("transcript")
        # F1: a receipt whose transcript already has a measured (non-brain)
        # event — either from an earlier run (measured_transcripts seeded
        # above) or earlier in THIS SAME run (added below as we go) — is a
        # duplicate for work already priced. Drop it outright: not kept
        # pending, not re-measured, no second event, just counted.
        if role != "brain" and transcript and transcript in measured_transcripts:
            dup_receipts += 1
            continue
        # STABLE-GATE: a transcript still being flushed measures low — pending,
        # not invented, beats under-counting forever (the v0.11 lesson).
        # F4(b): a FUTURE mtime (age < 0, clock skew) is not "still being
        # flushed" — it's not mid-write at all. Only 0 <= age < STABLE holds
        # a receipt pending; a negative age must not satisfy that forever.
        if STABLE > 0 and transcript and os.path.isfile(transcript):
            try:
                age = time.time() - os.path.getmtime(transcript)
            except OSError:
                age = None
            if age is not None and 0 <= age < STABLE:
                kept.append(line); pending += 1; continue
        # RECEIPT TTL: absent transcript (never existed, or gc'd by the
        # platform) is a DIFFERENT case than exists-but-unparseable — the
        # latter must keep today's stay-pending behavior forever (it may
        # still be mid-flush). Only "not there at all" ages out.
        if not transcript or not os.path.isfile(transcript):
            ts = r.get("ts")
            receipt_age_h = None
            if ts:
                try:
                    receipt_age_h = (time.time() - calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))) / 3600.0
                    # F4(c): a future ts (clock skew, or a receipt minted
                    # before butin-receipt.sh started clamping at source)
                    # makes this negative — clamp to 0 so it starts aging
                    # once now catches up, instead of parking the receipt
                    # pending forever. Mint-side clamping prevents new
                    # cases; this covers any that already exist.
                    if receipt_age_h < 0: receipt_age_h = 0.0
                except (ValueError, OverflowError):
                    receipt_age_h = None   # unparseable ts: never guess an age, keep pending
            if receipt_age_h is not None and receipt_age_h > TTL_HOURS:
                ag = agent_name(transcript, r.get("agent_hint"), r.get("role"))
                # v0.16.0 PHANTOM/LOSS SPLIT: "observed" (set at mint time by
                # butin-receipt.sh) is the signal — both mint sites only fire
                # when the file exists on disk THEN, so observed=true means a
                # real transcript existed and was later removed (a genuine
                # loss, must stay in the coverage denominator); observed
                # false/missing (includes every pre-v0.16 receipt, minted
                # before this field existed) means it was never written at
                # all (SubagentStop's own noise, excluded from coverage).
                if r.get("observed") is True:
                    reason = "transcript removed after it was recorded (existed at mint, measurement lost)"
                else:
                    reason = "transcript never written (phantom — SubagentStop path, v0.14)"
                new_events.append({"v": 2, "receipt": r["id"], "ts": r["ts"], "agent": ag,
                      "transcript": transcript, "unmeasurable": True,
                      "reason": reason})
                unmeasurable += 1; continue
            kept.append(line); pending += 1; continue
        # BRAIN dedup: the Stop hook fires once per turn, each receipt points at
        # the SAME growing main transcript. Only ONE brain event PER MODEL SEEN
        # per session is correct (the latest state). A new brain receipt for a
        # session that already has brain events REPLACES the WHOLE set instead
        # of adding duplicates (a mid-session /model switch means the set of
        # models — and therefore the set of events — can grow between receipts).
        groups = measure_transcript(transcript)
        if groups is None:
            kept.append(line); pending += 1; continue
        ag = agent_name(transcript, r.get("agent_hint"), r.get("role"))

        # DATE-AWARE PRICING: the rate is picked by the EVENT'S OWN ts (this
        # receipt's ts), never by "now" — the same receipts + transcripts
        # always reprice to the same dollar, whenever measure.py happens to
        # run (REPRODUCIBLE). Real cost and its counterfactual baseline both
        # use this SAME event_date. A missing/empty ts leaves event_date ""
        # — pick_rate() then only allows an undated base row.
        event_date = (r.get("ts") or "")[:10]

        # MIXED-MODEL PRICING (v0.14): price each model group at ITS OWN rates
        # — a /model switch mid-session must never let the last model billed
        # price tokens it didn't generate (AUDIT-FABLE C2). ALL-OR-NOTHING: if
        # ANY group's model (or the baseline itself) has no pricing_id, the
        # whole receipt becomes ONE unmeasurable event. Pricing only the known
        # slice would emit a real_cost_usd that UNDERCOUNTS the transcript —
        # an invented "measured" figure. Unmeasurable-with-reason is honest
        # and visible; no partial events are ever written for one receipt.
        priced, unpriced = {}, set()
        for mdl, tok in groups.items():
            tk = (tok[0], tok[1], tok[2], tok[3])
            real, real_billed, real_norm = cost(rates, mdl, tk, event_date)
            # baseline is normalized for the counterfactual math too (never
            # let a dated baseline id go unpriced when its undated twin is
            # known) but its normalization is never stamped on the event —
            # baseline_model stays exactly what's configured.
            cf, _, _ = cost(rates, baseline, tk, event_date)
            if real is None: unpriced.add(mdl)
            if cf is None: unpriced.add(baseline)
            if real is not None and cf is not None:
                priced[mdl] = (tk, real, cf, real_billed, real_norm)
        if unpriced:
            new_events.append({"v": 2, "receipt": r["id"], "ts": r["ts"], "agent": ag,
                  "transcript": transcript, "model": ",".join(sorted(unpriced)),
                  "unmeasurable": True, "reason": "unknown pricing_id"})
            unmeasurable += 1; continue

        # ONE EVENT PER MODEL: each event stays schema-v2-pure by construction
        # — chosen_model prices EXACTLY the tokens grouped under it (the
        # invariant holds by construction, not by convention). core.awk needs
        # zero changes (no second accounting implementation — it just sums
        # events), and the report's per-agent rows aggregate the slices
        # automatically (same agent on every slice of one receipt).
        slice_events = []
        for mdl, (tk, real, cf, real_billed, real_norm) in priced.items():
            i, o, cr, cw = tk
            prem_i = i if (ag != "brain" and mdl != baseline and real < cf) else 0
            prem_o = o if (ag != "brain" and mdl != baseline and real < cf) else 0
            ev = {"v": 2, "receipt": r["id"], "ts": r["ts"], "session": r.get("session"),
                  "cwd": r.get("cwd"), "transcript": transcript, "agent": ag, "chosen_model": mdl,
                  "tokens": {"in": i, "out": o, "cache_read": cr, "cache_write": cw},
                  "real_cost_usd": round(real, 6), "baseline_model": baseline,
                  "counterfactual_cost_usd": round(cf, 6), "pricing_version": pver,
                  "outcome": "ok", "prem_in_avoided": prem_i, "prem_out_avoided": prem_o}
            # AUDITABILITY: chosen_model stays the id the platform actually
            # reported (what was billed) — these two fields are added ONLY
            # when the dated-suffix strip actually fired for this slice, so
            # a single-model undated receipt's event stays byte-compatible
            # with pre-v0.15 output (no new keys at all).
            if real_norm:
                ev["billed_pricing_id"] = real_billed
                ev["pricing_normalized"] = True
            slice_events.append(ev)

        if ag == "brain" and r.get("session"):
            sess = r["session"]
            if sess in brain_sessions or sess in brain_replace:
                brain_replace[sess] = slice_events   # supersede: the WHOLE prior
                                                      # brain event set for this
                                                      # session is replaced by this
                                                      # receipt's full (possibly
                                                      # multi-model) measurement
                measured += 0                         # not new measured tasks, a refresh
            else:
                brain_replace[sess] = slice_events; measured += len(slice_events)
        else:
            new_events.extend(slice_events); measured += len(slice_events)
            # F1: mark this transcript measured WITHIN this same run too — a
            # second worker receipt for it later in this same batch (not
            # just from a prior run via measured_transcripts' initial seed
            # above) must also be caught as a duplicate, not double-billed.
            if transcript: measured_transcripts.add(transcript)

    # rewrite EVENTS: keep existing (minus superseded brains), add new + replacements
    final = []
    for e in existing:
        if e.get("agent") == "brain" and e.get("session") in brain_replace:
            continue   # dropped: a fresher (possibly multi-model) brain measurement replaces it
        final.append(e)
    final.extend(new_events)
    for evs in brain_replace.values():
        final.extend(evs)
    # ATOMIC REWRITES: EVENTS/RECEIPTS are read concurrently (core.awk passes,
    # the report) — a torn read of a bare open(path,"w") could see a partial
    # file mid-rewrite. PID-unique tmp + os.replace (atomic rename) instead.
    events_tmp = f"{EVENTS}.tmp.{os.getpid()}"
    with open(events_tmp, "w", encoding="utf-8") as f:
        for e in final: f.write(json.dumps(e) + "\n")
    os.replace(events_tmp, EVENTS)
    receipts_tmp = f"{RECEIPTS}.tmp.{os.getpid()}"
    with open(receipts_tmp, "w", encoding="utf-8") as f: f.writelines(kept)
    os.replace(receipts_tmp, RECEIPTS)
    print(f"measured {measured} · pending {pending} · unmeasurable {unmeasurable} · dup_receipts {dup_receipts}")
    return 0

if __name__ == "__main__": sys.exit(main())
