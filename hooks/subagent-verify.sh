#!/usr/bin/env bash
# amiral optional hook — deterministic verification gate.
# On SubagentStop: if the project has a ./verify.sh, run it. Exit code 2
# blocks the subagent from finishing and feeds stderr back to it, so the
# worker must fix the build before its result reaches the orchestrator.
# Opt-in: see docs/hooks.md. Not installed by default.
set -uo pipefail
[ -x ./verify.sh ] || exit 0   # no gate defined -> allow
if OUT=$(./verify.sh 2>&1); then
  exit 0
else
  echo "verify.sh failed — fix before finishing:" >&2
  echo "$OUT" | tail -20 >&2
  exit 2
fi
