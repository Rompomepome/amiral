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
#
# v0.18.1 GROUND TRUTH UPDATE: verified live 2026-07-22 on Claude Code
# 2.1.217 that SubagentStop is NOT dead after all — it fires again for real
# Agent-tool subagents, both synchronous and background. Background is the
# platform's own default as of v2.1.198 (the v0.14 finding above was true
# for the build it was verified on; the platform has moved since — v0.14's
# discovery scan stays exactly as it was, it is still what finds and
# receipts a worker transcript this revived path might otherwise miss or
# double up on). A background firing's SubagentStop payload carries a
# background_tasks[] array whose entries repeat "agent_type" alongside the
# real top-level field of the same name — g()'s old whole-payload grep
# couldn't tell the two apart, matched BOTH occurrences, and the printf
# further down wrote the second match as a literal embedded newline inside
# "agent_hint", tearing one JSON receipt into two physical lines (a corrupt
# line — never silently dropped or repaired; see the torn-line guards on
# both transcript-claiming sites below, and measure.py's "corrupt" counter,
# and bin/amiral-butin's report warning). g() is now a top-level-only
# extractor: a character-by-character JSON scan (string/escape/depth aware,
# BSD-awk-safe — no gensub, no split(...,"")) that only ever considers a
# key at depth 1 (directly inside the outer object), so a same-named field
# nested inside an array or object (background_tasks[].agent_type, or any
# future lookalike) can never again be mistaken for the platform's own
# top-level field.
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
# v0.18.1: top-level-ONLY field extractor (see the header paragraph above
# for the bug this replaces). printf, never echo — echo's behavior on a
# leading/embedded backslash varies by shell/build config, and a backslash
# inside a JSON string value (last_assistant_message in particular) must
# reach awk byte-for-byte or the escape-aware scan below desyncs.
#
# The scan is a 3-state machine: in_string (are we inside a "..." token),
# escape (the char after a backslash IN a string is consumed literally,
# never re-examined — this is what keeps \" and \\ from ever closing a
# string early or late), and depth (incremented on { or [ OUTSIDE a string,
# decremented on } or ]; strings never touch it). A string that CLOSES
# while depth==1 is either a top-level KEY (if a bare ':' follows) or a
# top-level VALUE (if it directly follows a top-level key's ':') — anything
# that opens/closes at depth>1 (an array/object member, e.g. the bg-task
# entries' own "agent_type") is invisible to this logic by construction, no
# matter what its key is named. A non-string value (number/bool/null/nested
# array/object) is simply walked over by the same depth/string state
# machine and never printed, matching what the old whole-payload regex
# would have matched anyway (it only ever captured quoted values).
# substr()-based iteration only — split($0,"",arr) is not BSD-awk portable.
#
# SINGLE-PASS (v0.18.1 hardening): a hook firing used to call this scanner
# 4-5 times (once per wanted field), each an INDEPENDENT full traversal of
# IN — cheap today only because every wanted key happens to precede
# last_assistant_message in the platform's current field order. If that
# order ever changes (or a hostile payload deliberately front-loads a huge
# last_assistant_message), each of those 4-5 calls pays the full-payload
# cost separately: a multiplier on top of an already worst-case scan. g_all()
# replaces all of them with ONE traversal that collects every wanted
# top-level string field in a single pass, printing "key<TAB>value" per
# field found (a raw, unescaped TAB is an illegal byte inside a JSON
# string — the scanner preserves escaping byte-for-byte, so an escaped \t
# in a value stays the two characters \ and t, never a real tab — the
# output's own field separator can never collide with a value). FIRST
# occurrence per key still wins (same threat model as the F3(a)
# duplicate-key note elsewhere in this file: a later forged duplicate top-
# level key can never override one already found) — enforced by the
# `found[]` gate below, not by scan order. The scan EXITS as soon as every
# wanted key has been found at least once: with today's field ordering
# that happens well before last_assistant_message's content is reached, so
# the common case stays exactly as cheap as a single g() call was. Residual
# worst case: a payload where the wanted keys are absent or reordered AFTER
# a huge field (a role=brain payload that legitimately never carries
# agent_type/agent_transcript_path, for instance) never satisfies the
# early-exit and pays one FULL scan of IN — but only ONE, not a 4-5x
# multiplier of one, which is the bound this restructure exists to
# guarantee regardless of what the platform ever reorders.
g_all() {
  printf '%s' "$IN" | awk '
  BEGIN {
    wanted["session_id"] = 1; wanted["transcript_path"] = 1
    wanted["agent_transcript_path"] = 1; wanted["agent_type"] = 1; wanted["cwd"] = 1
    need = 5
  }
  { full = full $0 }
  END {
    depth = 0; instr = 0; esc = 0; want = ""; key = ""; pendkey = ""; buf = ""
    n = length(full)
    for (i = 1; i <= n; i++) {
      c = substr(full, i, 1)
      if (instr) {
        if (esc) { buf = buf c; esc = 0; continue }
        if (c == "\\") { buf = buf c; esc = 1; continue }
        if (c == "\"") {
          instr = 0
          if (strdepth == 1) {
            if (want == "value") {
              if ((key in wanted) && !(key in found)) {
                print key "\t" buf
                found[key] = 1; need--
                if (need <= 0) exit
              }
              want = ""
            } else {
              pendkey = buf; want = "key_pending"
            }
          }
          continue
        }
        buf = buf c; continue
      }
      if (c == "\"") { instr = 1; esc = 0; buf = ""; strdepth = depth; continue }
      if (c == "{" || c == "[") { depth++; continue }
      if (c == "}" || c == "]") { depth--; if (depth == 1) want = ""; continue }
      if (depth == 1) {
        if (c == ":" && want == "key_pending") { key = pendkey; want = "value"; continue }
        if (c == ",") { want = "" }
      }
    }
  }
  '
}

# Parse g_all()'s key<TAB>value stream ONCE into staging variables, then
# apply the existing role-based selection below — every downstream variable
# name (SESSION, TRANSCRIPT, AGENT, CWD, TS, AID) and its semantics are
# unchanged from the 4-5-call version. Process substitution (not a pipe into
# the loop) so the assignments land in THIS shell, not a subshell.
_SESSION_ID=""; _TRANSCRIPT_PATH=""; _AGENT_TRANSCRIPT_PATH=""; _AGENT_TYPE=""; _CWD=""
while IFS=$'\t' read -r _GK _GV; do
  case "$_GK" in
    session_id) _SESSION_ID="$_GV" ;;
    transcript_path) _TRANSCRIPT_PATH="$_GV" ;;
    agent_transcript_path) _AGENT_TRANSCRIPT_PATH="$_GV" ;;
    agent_type) _AGENT_TYPE="$_GV" ;;
    cwd) _CWD="$_GV" ;;
  esac
done < <(g_all)

SESSION="$_SESSION_ID"
TS="$(date -u +%FT%TZ)"
if [ "$ROLE" = "brain" ]; then
  TRANSCRIPT="$_TRANSCRIPT_PATH"; AGENT="brain"; AID="main"
else
  TRANSCRIPT="$_AGENT_TRANSCRIPT_PATH"; AGENT="$_AGENT_TYPE"
  AID="$(basename "${TRANSCRIPT:-unknown}" .jsonl)"
fi
CWD="$_CWD"
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
     && { grep -E '^\{.*\}$' "$RECEIPTS" 2>/dev/null | grep -qF -- "$TRANSCRIPT" \
          || grep -E '^\{.*\}$' "$EVENTS" 2>/dev/null | grep -qF -- "$TRANSCRIPT"; }; then
  # v0.18.1: only a physical line matching ^{.*}$ (starts with { AND ends
  # with }) can claim a transcript here. A torn line (the v0.18.1 bug —
  # background_tasks[]'s duplicate agent_type turning into an embedded
  # newline) fails this anchor on BOTH of its physical halves — the first
  # half never reaches the closing }, the second never opens with { — so it
  # claims nothing, and the transcript it names stays unclaimed instead of
  # silently blocking a clean re-mint forever.
  SKIP=1
elif [ "$ROLE" = "worker" ] && [ -n "${TRANSCRIPT:-}" ] && [ ! -f "$TRANSCRIPT" ]; then
  # v0.16 PHANTOM FIX: per the header's v0.14 discovery, SubagentStop on this
  # build fires ONLY for internal/ephemeral agents whose named transcript is
  # minted but NEVER written to disk — every REAL worker transcript is
  # already covered by the discovery scan a few lines down (the brain
  # branch), which only mints a receipt once the file exists. Minting here
  # for a named-but-absent transcript therefore loses nothing: it can only
  # ever resolve to measure.py's "transcript absent" unmeasurable event,
  # noise the tool would generate about itself. If a future build revives
  # SubagentStop and the file is merely still-streaming (not phantom), the
  # transcript will exist by the next brain turn and discovery mints it
  # then. Does NOT touch the brain branch, the discovery scan, or the
  # empty-transcript case (nothing to check existence of).
  SKIP=1
fi

# One atomic line. No file reads, no arithmetic — nothing that can race
# (bar the dedup/hostile checks just above, needed to kill the double-bill).
# v0.16.0 PHANTOM/LOSS SPLIT: "observed" records whether the transcript was
# seen on disk AT MINT TIME — the signal measure.py later uses to tell a
# never-written phantom (SubagentStop noise, excluded from coverage) apart
# from a transcript that DID exist and was later removed (a real loss, must
# stay in the coverage denominator). The worker branch above only reaches
# here when the file exists (the SKIP guard just above catches the absent
# case), and the brain branch's main transcript always exists by the time
# the Stop hook fires — so this is normally true; the one lingering false
# case is an empty $TRANSCRIPT (nothing to observe).
OBSERVED=false; [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && OBSERVED=true
if [ "$SKIP" = "0" ]; then
  printf '{"v":2,"id":"%s","ts":"%s","role":"%s","session":"%s","agent_hint":"%s","transcript":"%s","cwd":"%s","measured":false,"observed":%s}\n' \
    "$ID" "$TS" "$ROLE" "$SESSION" "${AGENT:-}" "${TRANSCRIPT:-}" "${CWD:-}" "$OBSERVED" >> "$RECEIPTS"
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
    # v0.18.1: only harvest "transcript" kvs from lines matching ^{.*}$ (same
    # anchor as the plain-branch dedup above) — one extra grep stage in the
    # SAME pipeline, still one pass over the files, not a per-file re-read
    # (the O(N)-per-turn cost F2 above exists to kill). A torn line (see the
    # v0.18.1 header paragraph) fails that anchor on both of its physical
    # halves, so the transcript it names is never harvested into KNOWN here
    # either — it stays undiscovered-as-known and gets a fresh clean receipt
    # minted for it below, same as if no receipt had ever existed.
    grep -hE '^\{.*\}$' "$RECEIPTS" "$EVENTS" 2>/dev/null \
      | grep -o '"transcript"[ ]*:[ ]*"[^"]*"' \
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
      # GNU form FIRST, then VALIDATE digits-only, then the BSD form, validate
      # again. Order matters and MUST NOT be flipped back: on GNU `stat -f`
      # means --file-system, so `%m` is parsed as a FILENAME — stat errors on
      # it, still PRINTS filesystem info for the real file to stdout, and exits
      # non-zero. A BSD-first `|| stat -c` chain then appends the epoch to that
      # garbage, yielding a multi-line non-numeric WEPOCH. BSD is the safe
      # fallback (rejects `-c` with nothing on stdout). Rule: never chain on
      # exit status alone when the failing branch can write to stdout.
      WEPOCH="$(stat -c %Y "$AT" 2>/dev/null)"
      case "$WEPOCH" in ''|*[!0-9]*) WEPOCH="$(stat -f %m "$AT" 2>/dev/null)" ;; esac
      NOWEPOCH="$(date -u +%s)"
      case "${WEPOCH:-}" in
        ''|*[!0-9]*) WTS="$TS" ;;   # invalid/empty epoch degrades to discovery ts
        *)
          if [ "$WEPOCH" -gt "$NOWEPOCH" ]; then
            WTS="$TS"   # clock skew: a future mtime can't be the real completion time
          else
            # Same GNU-first-then-validate rule for epoch->ISO: GNU `date -d`
            # first, then BSD `date -r`, and only accept an ISO-shaped result.
            WTS="$(date -u -d "@$WEPOCH" +%FT%TZ 2>/dev/null)"
            case "$WTS" in [0-9][0-9][0-9][0-9]-*) ;; *) WTS="$(date -u -r "$WEPOCH" +%FT%TZ 2>/dev/null)" ;; esac
            case "$WTS" in [0-9][0-9][0-9][0-9]-*) ;; *) WTS="$TS" ;; esac
          fi ;;
      esac
      WID="$(printf '%s' "$SESSION-$(basename "$AT" .jsonl)-$WTS-$$-${RANDOM:-0}" | shasum 2>/dev/null | awk '{print substr($1,1,12)}')"
      # agent_hint is deliberately EMPTY: identity comes from the .meta.json
      # sidecar at measure time (agent_name() in measure.py), never a hint.
      # observed:true literally — the `[ -f "$AT" ]` loop guard just above
      # already confirmed the file is present on disk.
      printf '{"v":2,"id":"%s","ts":"%s","role":"worker","session":"%s","agent_hint":"","transcript":"%s","cwd":"%s","measured":false,"observed":true}\n' \
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
