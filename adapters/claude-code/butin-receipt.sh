#!/usr/bin/env bash
# butin receipt hook (v0.12) — writes a RECEIPT, never a measurement.
# The transcript is written asynchronously by the platform and is still
# streaming when this fires, so measuring here is structurally wrong
# (that produced a 6.7x over-count in v0.11). We record only what the
# payload already knows, and measure later, cold, from stable files.
export LC_ALL=C
set -uo pipefail
AMIRAL_HOME="${AMIRAL_HOME:-$HOME/.amiral}"
RECEIPTS="$AMIRAL_HOME/receipts.jsonl"
mkdir -p "$AMIRAL_HOME"

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

# One atomic line. No file reads, no arithmetic — nothing that can race.
printf '{"v":2,"id":"%s","ts":"%s","role":"%s","session":"%s","agent_hint":"%s","transcript":"%s","cwd":"%s","measured":false}\n' \
  "$ID" "$TS" "$ROLE" "$SESSION" "${AGENT:-}" "${TRANSCRIPT:-}" "${CWD:-}" >> "$RECEIPTS"

# v0.13: refresh the statusline cache. Sibling in the installed layout
# (~/.claude/butin/cache.sh), lib/butin/ from the repo root in a checkout.
# cache.sh self-gates on the opt-in flag (no-op for non-statusline users)
# and takes its own lock — the receipt append above is already done, so
# this hook's "nothing that can race" property is untouched.
CACHESH="$(dirname "${BASH_SOURCE[0]}")/cache.sh"
[ -f "$CACHESH" ] || CACHESH="$(dirname "${BASH_SOURCE[0]}")/../../lib/butin/cache.sh"
bash "$CACHESH" >/dev/null 2>&1 || true
exit 0
