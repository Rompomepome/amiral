#!/usr/bin/env bash
set -euo pipefail

# fable-lean installer
# Copies the routing config from this repo to ~/.claude/ (global scope).
# Idempotent: safe to re-run. Never overwrites your CLAUDE.md (backup +
# @-import instead).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
POLICY_FILE="$CLAUDE_DIR/fable-lean-policy.md"

echo "-> Installing fable-lean into: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills/plan-ship"

# 1. Policy (persistent memory)
cp "$REPO_DIR/CLAUDE.md" "$POLICY_FILE"
echo "  ok  $POLICY_FILE"

# Non-destructive import into global CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%s)"
  if ! grep -q 'fable-lean-policy.md' "$CLAUDE_MD"; then
    printf '\n@fable-lean-policy.md\n' >> "$CLAUDE_MD"
    echo "  ok  import added to CLAUDE.md (backup created)"
  else
    echo "  =   import already present in CLAUDE.md"
  fi
else
  printf '# Global Claude Code memory\n\n@fable-lean-policy.md\n' > "$CLAUDE_MD"
  echo "  ok  CLAUDE.md created"
fi

# 2. Agents
for a in implementer grunt reviewer; do
  cp "$REPO_DIR/.claude/agents/$a.md" "$CLAUDE_DIR/agents/$a.md"
  echo "  ok  agents/$a.md"
done

# 3. Skill
cp "$REPO_DIR/.claude/skills/plan-ship/SKILL.md" "$CLAUDE_DIR/skills/plan-ship/SKILL.md"
echo "  ok  skills/plan-ship/SKILL.md"

# 4. Aliases
cp "$REPO_DIR/shell/fable-aliases.sh" "$CLAUDE_DIR/fable-aliases.sh"
echo "  ok  fable-aliases.sh"

cat << EOF

============================================================
Installed.

Final steps (2 min):

1) Load the aliases in your shell:
     echo 'source $CLAUDE_DIR/fable-aliases.sh' >> ~/.zshrc && source ~/.zshrc
   (bash users: use ~/.bashrc)

2) Update Claude Code (Sonnet 5 needs v2.1.197+):
     claude update

3) VERIFY the worker routing (once):
     cd <a project> && fable-lean
     # ask for something that delegates, then check /agents or the
     # transcript: workers must run on Sonnet, not Fable.

Commands:
  fable-lean            -> Fable xhigh, workers forced to Sonnet (daily default)
  fable-fine            -> Fable xhigh, workers per frontmatter (haiku for grunt)
  fable-ultra           -> Fable + ultracode (then /effort -> ultracode): big audits only
  sonnet-fast           -> pure Sonnet, for everything else
  /plan-ship <feature>  -> plan -> delegate -> verify -> review, in one session
============================================================
EOF
