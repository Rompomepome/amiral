#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

echo "-> Removing amiral from: $CLAUDE_DIR"
rm -f "$CLAUDE_DIR/amiral-policy.md" \
      "$CLAUDE_DIR/agents/implementer.md" \
      "$CLAUDE_DIR/agents/grunt.md" \
      "$CLAUDE_DIR/agents/reviewer.md" \
      "$CLAUDE_DIR/agents/corsaire.md" \
      "$CLAUDE_DIR/agents/advisor.md" \
      "$CLAUDE_DIR/amiral-profiles.sh" \
      "$CLAUDE_DIR/amiral-profiles.ps1" \
      "$CLAUDE_DIR/amiral-doctor" \
      "$CLAUDE_DIR/amiral-trust" \
      "$CLAUDE_DIR/amiral-setup" \
      "$CLAUDE_DIR/amiral-savings" \
      "$CLAUDE_DIR/amiral-report" \
      "$CLAUDE_DIR/amiral-butin" \
      "$CLAUDE_DIR/amiral-journal" \
      "$CLAUDE_DIR/amiral.env"
rm -f "$CLAUDE_DIR/skills/plan-ship/SKILL.md"
rmdir "$CLAUDE_DIR/skills/plan-ship" 2>/dev/null || true   # only if now empty

# Offer to restore the most recent pre-install backups of our agents/skill.
for f in "$CLAUDE_DIR/agents/implementer.md" "$CLAUDE_DIR/agents/grunt.md" \
         "$CLAUDE_DIR/agents/reviewer.md" "$CLAUDE_DIR/agents/corsaire.md"; do
  bak="$(ls -t "$f".amiral-bak.* 2>/dev/null | head -1 || true)"
  if [ -n "$bak" ]; then
    echo "  note: a pre-install backup exists: $bak (restore manually if it was yours)"
  fi
done

if [ -f "$CLAUDE_MD" ]; then
  if grep -q 'amiral-policy.md' "$CLAUDE_MD"; then
    cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%s)"
    grep -v 'amiral-policy.md' "$CLAUDE_MD" > "$CLAUDE_MD.tmp" && mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
    echo "  ok  import removed from CLAUDE.md (backup created)"
  else
    echo "  =   no amiral import in CLAUDE.md, nothing to remove"
  fi
fi

echo "Done. Remove the 'source .../amiral-profiles.sh' line from your rc file manually."
