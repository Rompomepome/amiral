#!/usr/bin/env bash
# amiral butin — statusline cache producer (v0.13). The ONLY writer of
# butin-cache.tsv. Hangs off BOTH adapters (butin-receipt.sh, butin-collect.sh)
# and amiral-butin's own cold pass, so whichever path produced new data
# leaves the statusline in sync.
#
# HONESTY INVARIANT (DESIGN-NOTES.md §1.2): core.awk is the only calculator.
# This script never computes a dollar or token figure itself — it only
# orchestrates (cold measurement) and transcribes core.awk's own output into
# the cache. No second accounting implementation.
#
# This script is invoked from hooks (receipt/collect) and must NEVER let a
# failure become visible to its caller: every path below ends at `exit 0`.
export LC_ALL=C
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$HERE/core.awk"
MEASURE="$HERE/measure.py"

AMIRAL_HOME="${AMIRAL_HOME:-$HOME/.amiral}"
LOG="$AMIRAL_HOME/butin.jsonl"
CONFIG="$AMIRAL_HOME/butin-config.json"
RECEIPTS="$AMIRAL_HOME/receipts.jsonl"
CACHE="$AMIRAL_HOME/butin-cache.tsv"
FLAG="$AMIRAL_HOME/statusline-on"
LOCK="$AMIRAL_HOME/.butin-cache.lock"

# --- gate: opt-in only. Zero behavior change for anyone who never ran
# `amiral statusline install`. BUTIN_CACHE_FORCE=1 overrides for tests and
# for amiral-butin's own cold-pass (which wants the cache to stay in sync
# with what it just printed, but only when the feature IS installed —
# amiral-butin itself checks the flag before calling this script).
if [ ! -f "$FLAG" ] && [ "${BUTIN_CACHE_FORCE:-0}" != "1" ]; then
  exit 0
fi

# core.awk is a sibling in both the repo (lib/butin/) and the installed
# layout (~/.claude/butin/) by construction (install.sh copies both next
# to each other). If it's somehow missing, we cannot compute honestly —
# write nothing rather than invent or run a second calculator.
[ -f "$CORE" ] || exit 0

mkdir -p "$AMIRAL_HOME" 2>/dev/null || exit 0

# --- lock: serialize producers (concurrent hooks, concurrent cache.sh
# invocations). A crashed producer must not wedge the statusline forever:
# a lock dir older than 600s is reclaimed once, then retried. ---
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ ! -d "$LOCK" ]; then
    # A symlink or plain file at the lock path (a sync-tool conflict artifact,
    # or a planted object) can never be a valid lock and `rmdir` won't clear
    # it — without this the producer would `exit 0` on every future run and
    # freeze the cache forever, the exact "wedged" state the design forbids.
    rm -f "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    LOCK_MTIME=$(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0)
    case "$LOCK_MTIME" in (*[!0-9]*|"") LOCK_MTIME=0 ;; esac
    NOW_T=$(date +%s)
    AGE=$(( NOW_T - LOCK_MTIME ))
    if [ "$AGE" -gt 600 ]; then
      rmdir "$LOCK" 2>/dev/null || rm -f "$LOCK" 2>/dev/null
      mkdir "$LOCK" 2>/dev/null || exit 0   # someone else just grabbed it: bail quietly, it will write a complete snapshot
    else
      exit 0   # another producer is running right now; it will write a complete snapshot
    fi
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# --- cold measurement: receipts -> measured events, stable-gated. ---
# Safe to call from a hook precisely because measure.py's own BUTIN_STABLE_SECS
# gate keeps a transcript modified <60s ago PENDING (never measured warm —
# the v0.11 6.7x lesson); it is retried on a later event or report run.
if [ -s "$RECEIPTS" ] && [ -f "$MEASURE" ] && command -v python3 >/dev/null 2>&1; then
  PRICES="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/butin/pricing.tsv"
  [ -f "$PRICES" ] || PRICES="$HERE/pricing.tsv"
  BUTIN_STABLE_SECS="${BUTIN_STABLE_SECS:-60}" BUTIN_PRICES="$PRICES" \
    python3 "$MEASURE" >/dev/null 2>&1 || true
fi

# Fresh install / nothing measured yet -> never nag, write no cache at all.
[ -f "$LOG" ] || exit 0

# --- config: MODE + BASELINE, same grep idiom as bin/amiral-butin. ---
MODE="api"; BASELINE="claude-sonnet-4-6"
if [ -f "$CONFIG" ]; then
  T=$(grep -oE '"mode"[ ]*:[ ]*"[^"]*"' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/'); [ -n "$T" ] && MODE="$T"
  T=$(grep -oE '"baseline_model"[ ]*:[ ]*"[^"]*"' "$CONFIG" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/'); [ -n "$T" ] && BASELINE="$T"
fi

# --- compute: core.awk is the only calculator, run TWICE (full log + a
# today-filtered slice). No date logic lives inside core.awk itself. ---
FULL=$(awk -v MODE="$MODE" -f "$CORE" < "$LOG" 2>/dev/null)
TODAY="$(date -u +%F)"
# "today" = UTC day, matching the collector's `date -u` ts stamps; local
# midnight would silently disagree with the data plane.
# The ts-prefix grep is an approximation, not a second calculator: an
# escalation marker whose TARGET event is from a previous day contributes
# only its own-day pieces to this slice; the FULL pass above is always
# exact (unfiltered), so totals never drift from the report.
# grep rc 1 (no match today yet) is fine — empty input still makes core.awk's
# END block print zero-valued rows (guarded here so pipefail never surfaces).
# NOTE: NOT a plain `grep -F "\"ts\":\"$TODAY"` — measure.py rewrites
# butin.jsonl through Python's json.dumps() (the FIRST cold-measurement
# pass onward), which serializes as `"ts": "..."` (space after the colon),
# while the bash collector writes `"ts":"..."` (no space). A fixed-string
# match on the no-space form silently stops matching EVERY event after the
# first cold pass — verified live during implementation. Same tolerant
# `[ ]*` idiom already used everywhere else in this codebase for JSON
# field extraction (bin/amiral-butin, butin-collect.sh).
TODAY_REPORT=$( (grep -E "\"ts\"[ ]*:[ ]*\"$TODAY" "$LOG" 2>/dev/null || true) | awk -v MODE="$MODE" -f "$CORE" 2>/dev/null)

NET_TOTAL=$(echo "$FULL" | awk -F'\t' '/^NET/{print $2}')
PREM_TOTAL=$(echo "$FULL" | awk -F'\t' '/^PREM_AVOIDED/{print $2}')
MEASURED=$(echo "$FULL" | awk -F'\t' '/^MEASURED/{print $2}')
UNMEASURED=$(echo "$FULL" | awk -F'\t' '/^UNMEASURED/{print $2}')

NET_TODAY=$(echo "$TODAY_REPORT" | awk -F'\t' '/^NET/{print $2}')
PREM_TODAY=$(echo "$TODAY_REPORT" | awk -F'\t' '/^PREM_AVOIDED/{print $2}')
ESC_TODAY=$(echo "$TODAY_REPORT" | awk -F'\t' '/^ESC/{print $2}')

: "${NET_TOTAL:=0}"; : "${PREM_TOTAL:=0}"; : "${MEASURED:=0}"; : "${UNMEASURED:=0}"
: "${NET_TODAY:=0}"; : "${PREM_TODAY:=0}"; : "${ESC_TODAY:=0}"

# PENDING = receipts still awaiting measurement, EXCLUDING any whose id is
# already a measured event in the log. That exclusion matters: measure.py
# updates butin.jsonl and receipts.jsonl in two separate atomic renames, so
# a crash (OOM, forced quit, lid-close) between them can leave one receipt
# both measured (in the log) AND still "measured":false (in receipts) — a
# blind count would then show the SAME task as "1 meas · 1 pending", a
# self-contradiction this tool exists to never print. The set-difference is
# honest through that torn window; it self-heals on the next measure.py run.
# (No `grep -c … || echo 0`: under pipefail grep -c prints "0" and exits 1
# on zero matches, so the fallback would append a second "0" line.)
PENDING=0
if [ -f "$RECEIPTS" ]; then
  PENDING=$(awk '
    FNR==NR {
      if ($0 ~ /"measured"[ ]*:[ ]*false/ && match($0, /"id"[ ]*:[ ]*"[^"]*"/)) {
        s=substr($0,RSTART,RLENGTH); sub(/^.*"id"[ ]*:[ ]*"/,"",s); sub(/".*/,"",s); pend[s]=1 }
      next }
    match($0, /"receipt"[ ]*:[ ]*"[^"]*"/) {
      s=substr($0,RSTART,RLENGTH); sub(/^.*"receipt"[ ]*:[ ]*"/,"",s); sub(/".*/,"",s); done[s]=1 }
    END { c=0; for (k in pend) if (!(k in done)) c++; print c }
  ' "$RECEIPTS" "$LOG" 2>/dev/null)
  PENDING=${PENDING:-0}
fi

GEN_TS="$(date -u +%FT%TZ)"
GEN_EPOCH="$(date +%s)"

# --- write: PID-unique tmp name is MANDATORY (a fixed .tmp would reintroduce
# the clobber race the audit already found once), then mv (atomic same-fs
# rename) onto the live cache. Readers never see a partial file. Format v1,
# extensible: readers must ignore unknown keys (this is where `last_receipt`
# / `last` land later, per DESIGN-NOTES.md §3 — out of scope here). ---
TMP="$AMIRAL_HOME/butin-cache.tsv.tmp.$$"
{
  printf 'v\t1\n'
  printf 'generated_ts\t%s\n' "$GEN_TS"
  printf 'generated_epoch\t%s\n' "$GEN_EPOCH"
  printf 'day\t%s\n' "$TODAY"
  printf 'mode\t%s\n' "$MODE"
  printf 'baseline\t%s\n' "$BASELINE"
  printf 'net_total\t%s\n' "$NET_TOTAL"
  printf 'net_today\t%s\n' "$NET_TODAY"
  printf 'prem_avoided_total\t%s\n' "$PREM_TOTAL"
  printf 'prem_avoided_today\t%s\n' "$PREM_TODAY"
  printf 'measured\t%s\n' "$MEASURED"
  printf 'unmeasured\t%s\n' "$UNMEASURED"
  printf 'pending\t%s\n' "$PENDING"
  printf 'esc_today\t%s\n' "$ESC_TODAY"
} > "$TMP" 2>/dev/null && mv "$TMP" "$CACHE" 2>/dev/null

rm -f "$TMP" 2>/dev/null || true
exit 0
