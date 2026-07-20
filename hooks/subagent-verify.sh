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
# HONEST SCOPE (docs/hooks.md "Security model"): the fingerprint covers
# verify.sh's OWN BYTES + this repo's identity — NOT anything it sources,
# execs, or invokes (helper scripts, npm/make targets, node_modules).
# Trusting a repo means trusting its entire build, not just this file.
set -uo pipefail

# Must be a REGULAR executable file. `-x` alone is true for a directory or an
# executable FIFO; a FIFO named verify.sh (planted by a build step / tar entry
# — git itself can't check one out) would hang the `shasum` below forever,
# upstream of the timeout wrapper. `-f` closes that DoS.
{ [ -f ./verify.sh ] && [ -x ./verify.sh ]; } || exit 0   # nothing to gate -> allow

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
TRUST_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-trusted-repos"
SHA="$(shasum ./verify.sh 2>/dev/null | awk '{print $1}')"
# repo identity: prefer the remote origin URL; else the root (first) commit;
# else empty (unanchored — path+hash only, honestly weaker). Must compute
# IDENTICALLY to bin/amiral-trust and bin/amiral-doctor (L10 fix): binds
# trust to the REPO, not just path+hash, so a different repo later checked
# out at a previously-trusted path — even with byte-identical verify.sh —
# does not ACCIDENTALLY inherit trust. This is NOT an authentication boundary:
# the origin URL is a local, unauthenticated string, so an attacker who already
# controls what is written to that path can forge it (git remote add origin
# <old-url>). It closes the accidental-collision case, not the deliberate-swap
# one — see docs/hooks.md "Security model".
IDENTITY="$(git config --get remote.origin.url 2>/dev/null)"
[ -z "$IDENTITY" ] && IDENTITY="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
IDENTITY="$(printf '%s' "$IDENTITY" | tr -d '\n')"
FINGERPRINT="$REPO_ROOT::$SHA::$IDENTITY"

if [ ! -f "$TRUST_FILE" ] || ! grep -qxF "$FINGERPRINT" "$TRUST_FILE" 2>/dev/null; then
  # Not trusted (verify.sh changed since you trusted it, or this is a
  # different repo at a previously-trusted path): DO NOT RUN.
  echo "amiral: ./verify.sh here is not trusted, skipping the gate." >&2
  echo "If you trust this repo, run:  amiral-trust" >&2
  exit 0                                            # skip, never execute untrusted code
fi

# TOCTOU guard: re-hash verify.sh immediately before exec. Shrinks (does not
# eliminate) the check->run window where verify.sh could be swapped between
# the trust match above and the exec below.
SHA_NOW="$(shasum ./verify.sh 2>/dev/null | awk '{print $1}')"
if [ "$SHA_NOW" != "$SHA" ]; then
  echo "amiral: verify.sh changed between the trust check and now — refusing." >&2
  exit 0
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
