#!/usr/bin/env bash
# amiral optional hook — deterministic verification gate (opt-in).
# On SubagentStop: run THIS project's ./verify.sh, but ONLY if the repo
# was explicitly trusted. Exit 2 blocks the subagent and feeds stderr
# back so it must fix the build. See docs/hooks.md.
#
# SECURITY: a hook wired globally would otherwise run ./verify.sh from
# ANY repo you open — including a malicious one shipping a booby-trapped
# verify.sh (rm -rf, ssh exfil, curl|bash), silently, with full shell
# privileges. This gate refuses to run until you trust the repo:
#   amiral-trust        # run once, inside a repo you trust
# and it wraps execution in a timeout so a hung verify can't freeze you.
set -uo pipefail

[ -x ./verify.sh ] || exit 0                      # nothing to gate -> allow

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TRUST_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-trusted-repos"
FINGERPRINT="$REPO_ROOT::$(shasum ./verify.sh 2>/dev/null | awk '{print $1}')"

if [ ! -f "$TRUST_FILE" ] || ! grep -qxF "$FINGERPRINT" "$TRUST_FILE" 2>/dev/null; then
  # Not trusted (or verify.sh changed since you trusted it): DO NOT RUN.
  echo "amiral: ./verify.sh here is not trusted, skipping the gate." >&2
  echo "If you trust this repo, run:  amiral-trust" >&2
  exit 0                                            # skip, never execute untrusted code
fi

# Trusted: run it, but never let it hang the session.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
if [ -n "$TIMEOUT_BIN" ]; then
  OUT="$("$TIMEOUT_BIN" 300 ./verify.sh 2>&1)"; CODE=$?
else
  OUT="$(./verify.sh 2>&1)"; CODE=$?
fi

if [ "$CODE" -eq 0 ]; then
  exit 0
else
  echo "verify.sh failed (exit $CODE) — fix before finishing:" >&2
  echo "$OUT" | tail -20 >&2
  exit 2
fi
