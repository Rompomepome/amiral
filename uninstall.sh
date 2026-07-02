#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

echo "-> Removing fable-lean from: $CLAUDE_DIR"
rm -f "$CLAUDE_DIR/fable-lean-policy.md" \
      "$CLAUDE_DIR/agents/implementer.md" \
      "$CLAUDE_DIR/agents/grunt.md" \
      "$CLAUDE_DIR/agents/reviewer.md" \
      "$CLAUDE_DIR/fable-aliases.sh" \
      "$CLAUDE_DIR/fable-profiles.ps1"
rm -rf "$CLAUDE_DIR/skills/plan-ship"

# Remove the @-import line, keep the rest of CLAUDE.md untouched
if [ -f "$CLAUDE_MD" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%s)"
  grep -v 'fable-lean-policy.md' "$CLAUDE_MD" > "$CLAUDE_MD.tmp" && mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
  echo "  ok  import removed from CLAUDE.md (backup created)"
fi

echo "Done. Remove the 'source .../fable-aliases.sh' line from your ~/.zshrc manually."
