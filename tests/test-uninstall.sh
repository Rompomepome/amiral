#!/usr/bin/env bash
# uninstall completeness battery (AUDIT-FABLE M10, finished). install.sh
# copies the ENTIRE butin layer (core.awk, measure.py, backfill.py,
# agents.sh, amiral-agents.txt, butin-receipt.sh, pricing.tsv,
# butin-collect.sh, adapter.sh, the statusline renderer + cache, ...) into
# $CLAUDE_DIR/butin and nowhere else. Pre-fix, uninstall.sh only rm -f'd
# three of those names — this battery proves nothing survives a real
# install -> uninstall round-trip, hermetically (temp HOME + temp
# CLAUDE_CONFIG_DIR, never the caller's real ~/.claude).
export LC_ALL=C
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ok  $1"; PASS=$((PASS+1)); }
ko(){ echo "  KO  $1"; FAIL=$((FAIL+1)); }

TMP_HOME="$(mktemp -d)"
CLAUDE_DIR="$TMP_HOME/.claude"

# ─── install populates $CLAUDE_DIR/butin (sanity: uninstall has something ───
# ─── real to clean up, not an accidental pass on an empty dir)             ───
( HOME="$TMP_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_DIR" bash "$HERE/install.sh" >/dev/null 2>&1 )

if [ -f "$CLAUDE_DIR/butin/core.awk" ] && [ -f "$CLAUDE_DIR/butin/measure.py" ] \
   && [ -f "$CLAUDE_DIR/butin/butin-receipt.sh" ] && [ -f "$CLAUDE_DIR/butin/pricing.tsv" ]; then
  ok "install.sh populates \$CLAUDE_DIR/butin (core.awk, measure.py, butin-receipt.sh, pricing.tsv present)"
else
  ko "install.sh did not populate \$CLAUDE_DIR/butin as expected — cannot exercise uninstall meaningfully"
fi

# ─── uninstall must remove the ENTIRE butin dir, not just the three names ───
# ─── the pre-fix version rm -f'd (amiral-statusline.sh/.ps1, cache.sh)    ───
( HOME="$TMP_HOME" CLAUDE_CONFIG_DIR="$CLAUDE_DIR" bash "$HERE/uninstall.sh" >/dev/null 2>&1 )

LEFTOVER="$(find "$CLAUDE_DIR/butin" 2>/dev/null)"
if [ ! -d "$CLAUDE_DIR/butin" ]; then
  ok "uninstall.sh removes \$CLAUDE_DIR/butin entirely"
elif [ -z "$(ls -A "$CLAUDE_DIR/butin" 2>/dev/null)" ]; then
  ok "uninstall.sh leaves \$CLAUDE_DIR/butin empty"
else
  ko "uninstall.sh leaves files behind under \$CLAUDE_DIR/butin: $LEFTOVER"
fi

# individually name the files the pre-fix three-name rm -f used to miss —
# a regression back to that narrower list must fail loudly here.
for f in core.awk measure.py backfill.py agents.sh amiral-agents.txt \
         butin-receipt.sh pricing.tsv butin-collect.sh adapter.sh; do
  if [ -f "$CLAUDE_DIR/butin/$f" ]; then
    ko "orphaned after uninstall: \$CLAUDE_DIR/butin/$f"
  else
    ok "removed: \$CLAUDE_DIR/butin/$f"
  fi
done

# ─── uninstall also removes the top-level scripts/agents/skill it claims to ───
for f in amiral-butin amiral-journal amiral-doctor amiral-trust amiral.env amiral-policy.md; do
  if [ -f "$CLAUDE_DIR/$f" ]; then
    ko "orphaned after uninstall: \$CLAUDE_DIR/$f"
  else
    ok "removed: \$CLAUDE_DIR/$f"
  fi
done

for a in implementer grunt reviewer corsaire advisor; do
  if [ -f "$CLAUDE_DIR/agents/$a.md" ]; then
    ko "orphaned after uninstall: \$CLAUDE_DIR/agents/$a.md"
  else
    ok "removed: \$CLAUDE_DIR/agents/$a.md"
  fi
done

if [ -d "$CLAUDE_DIR/skills/plan-ship" ]; then
  ko "orphaned after uninstall: \$CLAUDE_DIR/skills/plan-ship (dir still present)"
else
  ok "removed: \$CLAUDE_DIR/skills/plan-ship"
fi

echo ""; echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
