#!/usr/bin/env bash
# butin receipt hook (v0.12) — writes a RECEIPT, never a measurement.
# The transcript is written asynchronously by the platform and is still
# streaming when this fires, so measuring here is structurally wrong
# (that produced a 6.7x over-count in v0.11). We record only what the
# payload already knows, and measure later, cold, from stable files.
#
# v0.14 DISCOVERY (why): verified live 2026-07-18 that Claude Code 2.1.214
# does NOT fire SubagentStop for Task-tool agents at all — a controlled
# experiment ran a synchronous agent to completion; its transcript+sidecar
# were written instantly, receipts.jsonl never moved. 9 real transcripts in
# that session, 0 receipts: butin has been blind to ~100% of worker output
# on this build. The ONLY SubagentStop firings observed came from
# internal/ephemeral agents whose agent_transcript_path is minted but NEVER
# written (20/20 historical orphan receipts: the session dirs were alive
# with 6-13 OTHER real agent-*.jsonl each, the named file simply never
# existed — "the platform GCs it after some days" was the wrong read of
# that data). The Stop hook (this script's --brain branch) DOES fire
# reliably every turn with the main transcript_path, so THAT'S where we
# discover real worker transcripts that the dead SubagentStop path can no
# longer tell us about: after recording the brain receipt, scan the
# session's subagents/ dir for agent-*.jsonl files that exist on disk but
# have no receipt yet, and mint worker receipts for them ourselves. The
# worker branch below dedups ITSELF against BOTH receipts.jsonl and
# butin.jsonl before appending (the SKIP guard a few lines down) — if a
# future build restores SubagentStop, its receipts and discovery's now
# mutually exclude each other by transcript path, in BOTH directions (not
# just discovery skipping paths SubagentStop already claimed, but also a
# late SubagentStop firing skipping a path discovery already recorded or
# measured).
export LC_ALL=C
set -uo pipefail
AMIRAL_HOME="${AMIRAL_HOME:-$HOME/.amiral}"
RECEIPTS="$AMIRAL_HOME/receipts.jsonl"
EVENTS="$AMIRAL_HOME/butin.jsonl"
mkdir -p "$AMIRAL_HOME"

# F3(a): guard both receipt-minting sites in this file (the plain branch
# right below, and the discovery scan further down) against a transcript
# path containing a double-quote, backslash, or control character (which
# includes a literal newline/CR — checked by the shell's own case-pattern
# match against the whole string, not a line-based tool, so an embedded
# newline can't slip past). Any of those would break the printf-built JSON
# line outright, or worse, forge a field via a JSON duplicate-key override
# (demonstrated). Platform transcript names are hex ids; a hostile name
# here means a hostile actor placed the file (compromised worker, prompt
# injection with Bash access) — skip it: no receipt (unmeasured work),
# never a corrupted line or a forged field.
_hostile_path() {
  case "$1" in
    *'"'*|*'\'*|*[[:cntrl:]]*) return 0 ;;
  esac
  return 1
}

ROLE="worker"; [ "${1:-}" = "--brain" ] && ROLE="brain"
IN="$(cat 2>/dev/null || true)"
g() { echo "$IN" | grep -oE "\"$1\"[ ]*:[ ]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)"$/\1/'; }

SESSION="$(g session_id)"
TS="$(date -u +%FT%TZ)"
if [ "$ROLE" = "brain" ]; then
  TRANSCRIPT="$(g transcript_path)"; AGENT="brain"; AID="main"
else
  TRANSCRIPT="$(g agent_transcript_path)"; AGENT="$(g agent_type)"
  AID="$(basename "${TRANSCRIPT:-unknown}" .jsonl)"
fi
CWD="$(g cwd)"
ID="$(printf '%s' "$SESSION-$AID-$TS-$$-${RANDOM:-0}" | shasum 2>/dev/null | awk '{print substr($1,1,12)}')"

# F1: dedup the PLAIN branch (a genuine SubagentStop/Stop firing) against
# BOTH receipts.jsonl and butin.jsonl BEFORE appending — if the platform
# ever fires SubagentStop for a transcript the discovery scan already
# receipted (or already measured), or vice versa, this kills the
# double-bill (verified repro pre-fix: 2 events, same transcript, 2 costs).
# Brain is NEVER gated here: the Stop hook legitimately re-references the
# SAME main transcript every turn (the supersede flow in measure.py) —
# transcript dedup applies to role=worker only. An empty/absent transcript
# can't be deduped (nothing to match against): keep today's behavior, no
# dedup possible.
SKIP=0
if [ -n "${TRANSCRIPT:-}" ] && _hostile_path "$TRANSCRIPT"; then
  SKIP=1
elif [ "$ROLE" = "worker" ] && [ -n "${TRANSCRIPT:-}" ] \
     && { grep -qF -- "$TRANSCRIPT" "$RECEIPTS" 2>/dev/null || grep -qF -- "$TRANSCRIPT" "$EVENTS" 2>/dev/null; }; then
  SKIP=1
fi

# One atomic line. No file reads, no arithmetic — nothing that can race
# (bar the dedup/hostile checks just above, needed to kill the double-bill).
if [ "$SKIP" = "0" ]; then
  printf '{"v":2,"id":"%s","ts":"%s","role":"%s","session":"%s","agent_hint":"%s","transcript":"%s","cwd":"%s","measured":false}\n' \
    "$ID" "$TS" "$ROLE" "$SESSION" "${AGENT:-}" "${TRANSCRIPT:-}" "${CWD:-}" >> "$RECEIPTS"
fi

# v0.14 DISCOVERY SCAN (brain branch only — see header for the why). The
# main transcript's directory is .../<session>/<session>.jsonl; its worker
# transcripts live alongside it under .../<session>/subagents/agent-*.jsonl.
# Assumption: subagents run in the main session's project, so the payload's
# cwd is reused for the discovered receipts too.
if [ "$ROLE" = "brain" ] && [ -n "${TRANSCRIPT:-}" ]; then
  SUBDIR="${TRANSCRIPT%.jsonl}/subagents"
  if [ -d "$SUBDIR" ]; then
    # F2: one pass instead of two greps PER FILE (200 files -> 3.2s, 1000
    # files -> 18s, every single turn — the O(N)-per-turn cost this
    # restructure kills). Extract every already-known "transcript" value
    # from BOTH receipts.jsonl and butin.jsonl ONCE into a small tmp list,
    # then test each dir entry against that small list instead — one
    # listing + two file reads per turn regardless of dir size (new-file
    # count per turn is normally 0-2, so the per-entry lookups below stay
    # cheap too).
    KNOWN="$(mktemp 2>/dev/null || echo "$AMIRAL_HOME/.discover-known.$$")"
    grep -ho '"transcript"[ ]*:[ ]*"[^"]*"' "$RECEIPTS" "$EVENTS" 2>/dev/null \
      | sed 's/.*"\([^"]*\)"$/\1/' > "$KNOWN" 2>/dev/null
    for AT in "$SUBDIR"/agent-*.jsonl; do
      [ -f "$AT" ] || continue   # unmatched glob, or a non-file: never fabricate a receipt
      # Dedup against the small KNOWN list built above (replaces the old
      # 2-greps-of-the-full-files-PER-FILE scan).
      grep -qF -- "$AT" "$KNOWN" 2>/dev/null && continue
      # F3(a): same hostile-path guard as the plain branch above — a file
      # dropped in subagents/ is not necessarily trustworthy.
      _hostile_path "$AT" && continue
      # ts = the TRANSCRIPT'S MTIME (the task's actual completion time, not
      # discovery time — matters for day-slicing), BSD first, GNU fallback.
      # Non-numeric/empty epoch never crashes: fall back to now. F4(a): a
      # FUTURE mtime (clock skew) is clamped to now too — it can't be the
      # task's real completion time either, and an uncorrected future ts
      # would make measure.py's absent-transcript TTL gate (negative age)
      # hold the receipt pending forever.
      WEPOCH="$(stat -f %m "$AT" 2>/dev/null || stat -c %Y "$AT" 2>/dev/null)"
      NOWEPOCH="$(date -u +%s)"
      case "${WEPOCH:-}" in
        ''|*[!0-9]*) WTS="$TS" ;;
        *)
          if [ "$WEPOCH" -gt "$NOWEPOCH" ]; then
            WTS="$TS"   # clock skew: a future mtime can't be the real completion time
          else
            WTS="$(date -u -r "$WEPOCH" +%FT%TZ 2>/dev/null || date -u -d "@$WEPOCH" +%FT%TZ 2>/dev/null)"
            [ -n "$WTS" ] || WTS="$TS"
          fi ;;
      esac
      WID="$(printf '%s' "$SESSION-$(basename "$AT" .jsonl)-$WTS-$$-${RANDOM:-0}" | shasum 2>/dev/null | awk '{print substr($1,1,12)}')"
      # agent_hint is deliberately EMPTY: identity comes from the .meta.json
      # sidecar at measure time (agent_name() in measure.py), never a hint.
      printf '{"v":2,"id":"%s","ts":"%s","role":"worker","session":"%s","agent_hint":"","transcript":"%s","cwd":"%s","measured":false}\n' \
        "$WID" "$WTS" "$SESSION" "$AT" "${CWD:-}" >> "$RECEIPTS"
    done
    rm -f "$KNOWN"
  fi
fi

# v0.13: refresh the statusline cache. Sibling in the installed layout
# (~/.claude/butin/cache.sh), lib/butin/ from the repo root in a checkout.
# cache.sh self-gates on the opt-in flag (no-op for non-statusline users)
# and takes its own lock — the receipt append above is already done, so
# this hook's "nothing that can race" property is untouched.
CACHESH="$(dirname "${BASH_SOURCE[0]}")/cache.sh"
[ -f "$CACHESH" ] || CACHESH="$(dirname "${BASH_SOURCE[0]}")/../../lib/butin/cache.sh"
bash "$CACHESH" >/dev/null 2>&1 || true
exit 0
