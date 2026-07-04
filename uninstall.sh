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
      "$CLAUDE_DIR/amiral-profiles.sh" \
      "$CLAUDE_DIR/amiral-profiles.ps1" \
      "$CLAUDE_DIR/amiral-doctor"
rm -rf "$CLAUDE_DIR/skills/plan-ship"

if [ -f "$CLAUDE_MD" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%s)"
  grep -v 'amiral-policy.md' "$CLAUDE_MD" > "$CLAUDE_MD.tmp" && mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
  echo "  ok  import removed from CLAUDE.md (backup created)"
fi

echo "Done. Remove the 'source .../amiral-profiles.sh' line from your rc file manually."
