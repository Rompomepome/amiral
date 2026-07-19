#!/usr/bin/env python3
"""butin backfill (v0.15) — mint worker receipts for PAST sessions' real
subagent transcripts.

WHY: live discovery (adapters/claude-code/butin-receipt.sh, --brain branch)
only scans the CURRENT session's subagents/ dir each turn — every session
that already ended before this feature shipped has its real
agent-*.jsonl transcripts sitting on disk, invisible to butin forever,
because no future Stop hook will ever fire for a session that's over.
backfill walks the project directories directly and mints receipts for
transcripts that live discovery would have caught had it been running —
SAME rules: same hostile-path guard, same stable-gate, same dedup against
BOTH receipts.jsonl and butin.jsonl, same "identity comes from the
sidecar, never a hint" contract enforced at measure time. This module
ONLY mints receipts. It never measures — the user's next plain
`amiral-butin` (or `amiral-butin backfill` itself, which does not invoke
measure.py) leaves that to the existing cold-measure pass in
bin/amiral-butin, unchanged.

Real on-disk layout (verified 2026-07-18):
  ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<mangled-cwd>/<session-id>/subagents/agent-*.jsonl
  with a sibling agent-*.meta.json sidecar carrying agentType. <mangled-cwd>
  is the project's cwd with every '/' and '.' replaced by '-' (Claude Code's
  own naming, not amiral's).
"""
import glob, hashlib, json, os, shutil, sys, time

AMIRAL_HOME = os.environ.get("AMIRAL_HOME", os.path.expanduser("~/.amiral"))
RECEIPTS = os.path.join(AMIRAL_HOME, "receipts.jsonl")
EVENTS = os.path.join(AMIRAL_HOME, "butin.jsonl")
CLAUDE_CONFIG_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
PROJECTS = os.path.join(CLAUDE_CONFIG_DIR, "projects")


def mangle(cwd):
    """Claude Code's own project-dir naming: '/' and '.' -> '-'."""
    return "".join("-" if c in ("/", ".") else c for c in cwd)


def hostile_path(p):
    """Mirror _hostile_path() in butin-receipt.sh: a quote, backslash, or
    control char in the path could break a hand-built JSON line, or forge a
    field via a duplicate-key override. Skip it — no receipt, never a
    corrupted line."""
    if '"' in p or "\\" in p:
        return True
    return any(ord(c) < 0x20 or c == "\x7f" for c in p)


def load_known_transcripts():
    """Every 'transcript' value already known, from BOTH receipts.jsonl
    (not yet measured) and butin.jsonl (already measured) — built once,
    tolerant of unparseable lines (never crash on a torn/partial line)."""
    known = set()
    for fp in (RECEIPTS, EVENTS):
        if not os.path.isfile(fp):
            continue
        try:
            with open(fp, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line.startswith("{"):
                        continue
                    try:
                        d = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    t = d.get("transcript")
                    if t:
                        known.add(t)
        except OSError:
            continue
    return known


def select_project_dirs(all_projects):
    if not os.path.isdir(PROJECTS):
        return []
    if all_projects:
        return sorted(p for p in glob.glob(os.path.join(PROJECTS, "*")) if os.path.isdir(p))
    pdir = os.path.join(PROJECTS, mangle(os.getcwd()))
    return [pdir] if os.path.isdir(pdir) else []


def find_transcripts(pdirs):
    paths = []
    for pdir in pdirs:
        paths.extend(sorted(glob.glob(os.path.join(pdir, "*", "subagents", "agent-*.jsonl"))))
    return paths


def find_cwd(path, cap=20):
    """The transcript's own 'cwd' field, read from the first N lines only
    (never slurp a giant file whole just to find one field). Empty string
    if unreadable or absent — never guessed from the (unreliable) project
    dir name."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i >= cap:
                    break
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                c = d.get("cwd")
                if c:
                    return c
    except OSError:
        pass
    return ""


def mint(at, session, mtime, idx):
    """Build the receipt dict for one discovered transcript. ts is the
    transcript's OWN mtime (the task's real completion time, for correct
    day-slicing) — a FUTURE mtime (clock skew) is clamped to now, exactly
    like the live discovery scan, so it can't wedge measure.py's TTL gate."""
    now = time.time()
    ts_epoch = mtime if mtime <= now else now
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts_epoch))
    cwd = find_cwd(at)
    uniq = f"{session}|{os.path.basename(at)}|{mtime}|{idx}"
    rid = hashlib.sha1(uniq.encode("utf-8", "replace")).hexdigest()[:12]
    # agent_hint deliberately empty: identity comes from the .meta.json
    # sidecar at measure time (agent_name() in measure.py), never a hint —
    # same contract as the live discovery scan.
    return {"v": 2, "id": rid, "ts": ts, "role": "worker", "session": session,
            "agent_hint": "", "transcript": at, "cwd": cwd, "measured": False}


def _stable_secs():
    """BUTIN_STABLE_SECS, guarded exactly like measure.py guards
    BUTIN_RECEIPT_TTL_HOURS: a non-numeric knob must fall back to the
    documented default (60) instead of crashing the whole run, and a
    negative value clamps to 0 rather than holding every transcript out
    forever (a negative window would satisfy `0 <= age < STABLE` for no
    age at all, which is a silent behavior change, not a crash — clamp it
    explicitly so the knob's only effect is "0 or more seconds")."""
    try:
        v = int(os.environ.get("BUTIN_STABLE_SECS", "60") or 60)
    except (TypeError, ValueError):
        return 60
    return 0 if v < 0 else v


def _scan_and_mint(dry_run, all_projects, stable):
    """Core dedup+mint pass, shared by the locked (real run) and unlocked
    (--dry-run) callers in main(). Building the known-set and the
    mint/append loop are ONE unit for locking purposes — see FIX 1 in
    main()."""
    known = load_known_transcripts()
    pdirs = select_project_dirs(all_projects)
    transcripts = find_transcripts(pdirs)

    minted = []
    skipped = {"already_known": 0, "streaming": 0, "hostile": 0}
    now = time.time()
    idx = 0
    for at in transcripts:
        if hostile_path(at):
            skipped["hostile"] += 1
            continue
        if not os.path.isfile(at):
            continue  # unmatched glob / non-file: never fabricate a receipt
        try:
            mtime = os.path.getmtime(at)
        except OSError:
            continue
        age = now - mtime
        if 0 <= age < stable:
            skipped["streaming"] += 1
            continue
        if at in known:
            skipped["already_known"] += 1
            continue
        session = os.path.basename(os.path.dirname(os.path.dirname(at)))
        idx += 1
        rec = mint(at, session, mtime, idx)
        known.add(at)   # never mint the same path twice within one run
        minted.append(rec)

    if not dry_run:
        with open(RECEIPTS, "a", encoding="utf-8") as f:
            for rec in minted:
                f.write(json.dumps(rec) + "\n")

    return minted, skipped, pdirs


def report(minted, skipped, dry_run, pdirs, all_projects):
    sessions = sorted({m["session"] for m in minted})
    dates = sorted(m["ts"][:10] for m in minted)
    date_range = f"{dates[0]} .. {dates[-1]}" if dates else "—"
    print("")
    print("⚓ butin backfill")
    if dry_run:
        print(f"  would mint: {len(minted)} receipt(s) across {len(sessions)} session(s)")
    else:
        print(f"  minted: {len(minted)} receipt(s) across {len(sessions)} session(s)")
    print(f"  date range: {date_range}")
    print(f"  skipped: already_known={skipped['already_known']} "
          f"· streaming={skipped['streaming']} · hostile={skipped['hostile']}")
    # Default scope (no --all) matching NO project dir is otherwise a
    # silent "0 minted" — easy to mistake for "nothing to backfill" when
    # really the cwd just never mangled to an existing project dir.
    if not all_projects and not pdirs:
        print("  note: no project directory matches the current directory — try: amiral-butin backfill --all")
    if dry_run:
        print("  (dry-run — nothing written)")
    print("")


def main():
    argv = sys.argv[1:]
    dry_run = False
    all_projects = False
    for a in argv:
        if a == "--dry-run":
            dry_run = True
        elif a == "--all":
            all_projects = True
        else:
            print(f"usage: amiral-butin backfill [--dry-run] [--all]  (unknown arg: {a})",
                  file=sys.stderr)
            return 1

    # STABLE-GATE: default 60s here (unlike measure.py's own default of 0)
    # — backfill runs against files that may still be flushing (the most
    # recent session), and minting a receipt for a mid-write transcript is
    # the same mistake measuring one warm would be. cache.sh/bin wiring can
    # override for tests.
    STABLE = _stable_secs()

    if dry_run:
        # Read-only by contract: no lock, no append, no other file touched.
        minted, skipped, pdirs = _scan_and_mint(dry_run, all_projects, STABLE)
        report(minted, skipped, dry_run, pdirs, all_projects)
        return 0

    # FIX 1 (receipt loss race): measure.py reads receipts.jsonl whole, then
    # atomically rewrites it (os.replace) — a rewrite whose snapshot was
    # taken BEFORE this appended a new receipt would silently wipe that
    # append when it lands after. Taking measure.py's OWN lock
    # (${AMIRAL_HOME}/.measure.lock) around BOTH the known-set load and the
    # whole mint/append loop makes the two operations mutually exclusive —
    # os.mkdir is atomic across processes on the same filesystem. This is
    # ADDITIONAL to (not a replacement for) measure.py's F1
    # measured_transcripts dedup, which stops double-COUNTING; this lock
    # specifically stops a real append from being erased mid-flight.
    # Best-effort, same discipline as measure.py's own lock: a stale lock
    # (>600s old) is reclaimed once; any unexpected OSError acquiring it
    # falls back to proceeding UNLOCKED rather than crashing (locking must
    # only ever ADD safety, never subtract robustness).
    lockdir = os.path.join(AMIRAL_HOME, ".measure.lock")
    got_lock = False
    try:
        os.makedirs(AMIRAL_HOME, exist_ok=True)
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
                    print("busy: measurement in progress — retry later")
                    return 0
            else:
                print("busy: measurement in progress — retry later")
                return 0
    except OSError:
        got_lock = False   # couldn't even attempt the lock — proceed unlocked, best-effort

    try:
        minted, skipped, pdirs = _scan_and_mint(dry_run, all_projects, STABLE)
        report(minted, skipped, dry_run, pdirs, all_projects)
        return 0
    finally:
        if got_lock:
            shutil.rmtree(lockdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
