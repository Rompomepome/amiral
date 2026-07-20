#!/usr/bin/env bash
# trust-gate battery (v0.15.1 PART A — H9/L5/L10/TOCTOU). Real repos
# (mktemp + git init), real bin/amiral-trust and hooks/subagent-verify.sh
# runs: a regression of any of these fails here. Every test uses a
# hermetic CLAUDE_CONFIG_DIR via mktemp — never touches the caller's real
# ~/.claude/amiral-trusted-repos.
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

GIT="git -c user.email=t@t -c user.name=t"

# ─── H9-honesty regression: docs/hooks.md must not over-claim ───
if ! grep -q "tamper-evident" "$HERE/docs/hooks.md" \
   && grep -q "trusting a repo means trusting its entire build" "$HERE/docs/hooks.md"; then
  ok "H9-honesty: docs/hooks.md drops the unqualified 'tamper-evident' claim and states the sourced/invoked-code caveat"
else
  ko "H9-honesty regression in docs/hooks.md (bare tamper-evident claim, or caveat missing)"
fi

# ─── L10 repro: identity binding — a DIFFERENT repo at the SAME path,    ───
# ─── with byte-identical verify.sh, must NOT inherit trust               ───
L10_HOME="$(mktemp -d)"
L10_REPO="$(mktemp -d)"
PWN_L10="$L10_REPO/PWNED"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWN_L10" > "$L10_REPO/verify.sh"
chmod +x "$L10_REPO/verify.sh"
( cd "$L10_REPO" && git init -q && $GIT commit -q -m init --allow-empty && git remote add origin https://example.com/A.git )
( cd "$L10_REPO" && CLAUDE_CONFIG_DIR="$L10_HOME" bash "$HERE/bin/amiral-trust" >/dev/null )
# swap the repo at the SAME path: different history, different remote,
# IDENTICAL verify.sh bytes (still the touch-PWNED payload).
( cd "$L10_REPO" && rm -rf .git && git init -q && $GIT commit -q -m different --allow-empty && git remote add origin https://example.com/B.git )
( cd "$L10_REPO" && CLAUDE_CONFIG_DIR="$L10_HOME" bash "$HERE/hooks/subagent-verify.sh" >/dev/null 2>&1 )
if [ ! -f "$PWN_L10" ]; then
  ok "L10: a different repo at repo A's trusted path (identical verify.sh bytes) does NOT inherit trust — PWNED not created"
else
  ko "L10 FAILED: PWNED created — repo identity was not enforced"
fi

# ─── TOCTOU/checksum: verify.sh swapped AFTER trust, without re-trusting ───
TOCTOU_HOME="$(mktemp -d)"
TOCTOU_REPO="$(mktemp -d)"
printf '#!/bin/sh\necho benign\nexit 0\n' > "$TOCTOU_REPO/verify.sh"
chmod +x "$TOCTOU_REPO/verify.sh"
( cd "$TOCTOU_REPO" && git init -q && $GIT commit -q -m init --allow-empty )
( cd "$TOCTOU_REPO" && CLAUDE_CONFIG_DIR="$TOCTOU_HOME" bash "$HERE/bin/amiral-trust" >/dev/null )
PWN_TOCTOU="$TOCTOU_REPO/PWNED"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWN_TOCTOU" > "$TOCTOU_REPO/verify.sh"
chmod +x "$TOCTOU_REPO/verify.sh"
( cd "$TOCTOU_REPO" && CLAUDE_CONFIG_DIR="$TOCTOU_HOME" bash "$HERE/hooks/subagent-verify.sh" >/dev/null 2>&1 )
if [ ! -f "$PWN_TOCTOU" ]; then
  ok "TOCTOU/checksum: verify.sh swapped after trust (without re-trusting) is refused, not run"
else
  ko "TOCTOU FAILED: swapped verify.sh executed"
fi
SHASUM_COUNT=$(grep -c 'shasum ./verify.sh' "$HERE/hooks/subagent-verify.sh")
if [ "$SHASUM_COUNT" -ge 2 ]; then
  ok "structural: hooks/subagent-verify.sh re-hashes verify.sh a second time before exec (TOCTOU guard present, $SHASUM_COUNT shasum calls)"
else
  ko "structural: hooks/subagent-verify.sh does not appear to re-hash before exec (found $SHASUM_COUNT shasum calls)"
fi

# ─── L5 structural: all three fingerprint sites use pwd -P (physical path) ───
for f in bin/amiral-trust hooks/subagent-verify.sh bin/amiral-doctor; do
  if grep -q 'pwd -P' "$HERE/$f"; then
    ok "L5: $f uses pwd -P in its fingerprint fallback"
  else
    ko "L5: $f does NOT use pwd -P"
  fi
done

# ─── Fingerprint agreement (A5 drift guard): amiral-trust, the hook, and  ───
# ─── amiral-doctor must all compute the SAME fingerprint for one repo     ───
AGREE_HOME="$(mktemp -d)"
AGREE_REPO="$(mktemp -d)"
PWN_AGREE="$AGREE_REPO/RAN"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWN_AGREE" > "$AGREE_REPO/verify.sh"
chmod +x "$AGREE_REPO/verify.sh"
( cd "$AGREE_REPO" && git init -q && $GIT commit -q -m init --allow-empty && git remote add origin https://example.com/agree.git )
( cd "$AGREE_REPO" && CLAUDE_CONFIG_DIR="$AGREE_HOME" bash "$HERE/bin/amiral-trust" >/dev/null )
( cd "$AGREE_REPO" && CLAUDE_CONFIG_DIR="$AGREE_HOME" bash "$HERE/hooks/subagent-verify.sh" >/dev/null 2>&1 )
if [ -f "$PWN_AGREE" ]; then
  ok "fingerprint agreement: bin/amiral-trust's entry is recognized by the hook (verify.sh ran)"
else
  ko "fingerprint agreement FAILED: the hook did not recognize bin/amiral-trust's entry"
fi
DOCTOR_OUT=$( cd "$AGREE_REPO" && CLAUDE_CONFIG_DIR="$AGREE_HOME" HOME="$AGREE_HOME" bash "$HERE/bin/amiral-doctor" 2>&1 )
if echo "$DOCTOR_OUT" | grep -q "this verify.sh is trusted for the SubagentStop hook"; then
  ok "fingerprint agreement: bin/amiral-doctor computes the SAME fingerprint and reports the repo trusted"
else
  ko "fingerprint agreement FAILED: bin/amiral-doctor did not recognize the trust entry"
fi

# ─── Positive control: a trusted, unchanged verify.sh still runs under   ───
# ─── the hook — the hardening above must not break the happy path        ───
POS_HOME="$(mktemp -d)"
POS_REPO="$(mktemp -d)"
PWN_POS="$POS_REPO/RAN2"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$PWN_POS" > "$POS_REPO/verify.sh"
chmod +x "$POS_REPO/verify.sh"
( cd "$POS_REPO" && git init -q )
( cd "$POS_REPO" && CLAUDE_CONFIG_DIR="$POS_HOME" bash "$HERE/bin/amiral-trust" >/dev/null )
( cd "$POS_REPO" && CLAUDE_CONFIG_DIR="$POS_HOME" bash "$HERE/hooks/subagent-verify.sh" >/dev/null 2>&1 )
if [ -f "$PWN_POS" ]; then
  ok "positive control: a trusted, unchanged verify.sh still runs under the hook (happy path intact)"
else
  ko "positive control FAILED: trusted verify.sh did not run"
fi

# ─── FIFO DoS (post-review): a verify.sh that is an executable FIFO must   ───
# ─── NOT hang the hook. `-x` alone is true for a FIFO; shasum on it blocks  ───
# ─── forever, upstream of the timeout wrapper. The `-f` guard exits fast.   ───
FIFO_HOME="$(mktemp -d)"
FIFO_REPO="$(mktemp -d)"
( cd "$FIFO_REPO" && git init -q )
mkfifo "$FIFO_REPO/verify.sh" 2>/dev/null && chmod +x "$FIFO_REPO/verify.sh"
( cd "$FIFO_REPO" && CLAUDE_CONFIG_DIR="$FIFO_HOME" bash "$HERE/hooks/subagent-verify.sh" >/dev/null 2>&1 ) &
FIFO_PID=$!
FIFO_DONE=0
for _ in 1 2 3 4 5 6 7 8; do kill -0 "$FIFO_PID" 2>/dev/null || { FIFO_DONE=1; break; }; sleep 0.5; done
if [ "$FIFO_DONE" = 1 ]; then
  ok "FIFO DoS: an executable-FIFO verify.sh does not hang the hook (exits fast, never shasum'd)"
else
  ko "FIFO DoS FAILED: the hook hung on a FIFO verify.sh"; kill -9 "$FIFO_PID" 2>/dev/null
fi
wait "$FIFO_PID" 2>/dev/null || true

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
