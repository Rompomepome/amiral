#!/usr/bin/env bash
set -euo pipefail

# amiral installer — the admiral doesn't row.
# Copies the routing config from this repo to ~/.claude/ (global scope).
# Idempotent: safe to re-run. Never overwrites your CLAUDE.md (backup +
# @-import instead).
# Prefer the plugin route? See README: /plugin marketplace add + install.

if ! command -v claude >/dev/null 2>&1; then
  echo "!!  'claude' not found in PATH. Install Claude Code first:"
  echo "    https://code.claude.com/docs  (then re-run this installer)"
  echo "    Continuing anyway — the config will be picked up once installed."
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
POLICY_FILE="$CLAUDE_DIR/amiral-policy.md"

echo "-> Installing amiral into: $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills/plan-ship"

# Back up any pre-existing file we are about to overwrite (once, timestamped).
STAMP="$(date +%s)"
backup_if_exists() { [ -f "$1" ] && cp "$1" "$1.amiral-bak.$STAMP" && echo "  bak $1 -> $1.amiral-bak.$STAMP"; return 0; }

# 1. Policy (persistent memory)
cp "$REPO_DIR/CLAUDE.md" "$POLICY_FILE"
echo "  ok  $POLICY_FILE"

if [ -f "$CLAUDE_MD" ]; then
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%s)"
  if ! grep -q 'amiral-policy.md' "$CLAUDE_MD"; then
    printf '\n@amiral-policy.md\n' >> "$CLAUDE_MD"
    echo "  ok  import added to CLAUDE.md (backup created)"
  else
    echo "  =   import already present in CLAUDE.md"
  fi
else
  printf '# Global Claude Code memory\n\n@amiral-policy.md\n' > "$CLAUDE_MD"
  echo "  ok  CLAUDE.md created"
fi

# 2. Agents
for a in implementer grunt reviewer corsaire advisor; do
  backup_if_exists "$CLAUDE_DIR/agents/$a.md"
  cp "$REPO_DIR/agents/$a.md" "$CLAUDE_DIR/agents/$a.md"
  echo "  ok  agents/$a.md"
done

# 3. Skill
backup_if_exists "$CLAUDE_DIR/skills/plan-ship/SKILL.md"
cp "$REPO_DIR/skills/plan-ship/SKILL.md" "$CLAUDE_DIR/skills/plan-ship/SKILL.md"
echo "  ok  skills/plan-ship/SKILL.md"

# 4. Shell profiles
cp "$REPO_DIR/shell/amiral-profiles.sh" "$CLAUDE_DIR/amiral-profiles.sh"
echo "  ok  amiral-profiles.sh"
cp "$REPO_DIR/shell/amiral-profiles.ps1" "$CLAUDE_DIR/amiral-profiles.ps1"
echo "  ok  amiral-profiles.ps1 (Windows/PowerShell)"

# 5. Doctor
cp "$REPO_DIR/bin/amiral-doctor" "$CLAUDE_DIR/amiral-doctor"
chmod +x "$CLAUDE_DIR/amiral-doctor"
echo "  ok  amiral-doctor"
cp "$REPO_DIR/bin/amiral-trust" "$CLAUDE_DIR/amiral-trust"
chmod +x "$CLAUDE_DIR/amiral-trust"
echo "  ok  amiral-trust"
cp "$REPO_DIR/bin/amiral-setup" "$CLAUDE_DIR/amiral-setup"
chmod +x "$CLAUDE_DIR/amiral-setup"
echo "  ok  amiral-setup"
cp "$REPO_DIR/bin/amiral-savings" "$CLAUDE_DIR/amiral-savings"
chmod +x "$CLAUDE_DIR/amiral-savings"
echo "  ok  amiral-savings"
cp "$REPO_DIR/bin/amiral-report" "$CLAUDE_DIR/amiral-report"
chmod +x "$CLAUDE_DIR/amiral-report"
echo "  ok  amiral-report"
cp "$REPO_DIR/bin/amiral-butin" "$CLAUDE_DIR/amiral-butin"
chmod +x "$CLAUDE_DIR/amiral-butin"
mkdir -p "$CLAUDE_DIR/butin"
cp "$REPO_DIR/lib/butin/core.awk" "$CLAUDE_DIR/butin/core.awk"
cp "$REPO_DIR/lib/butin/pricing.tsv" "$CLAUDE_DIR/butin/pricing.tsv"
cp "$REPO_DIR/adapters/claude-code/butin-receipt.sh" "$CLAUDE_DIR/butin/butin-receipt.sh"
chmod +x "$CLAUDE_DIR/butin/butin-receipt.sh"
cp "$REPO_DIR/lib/butin/measure.py" "$CLAUDE_DIR/butin/measure.py"
cp "$REPO_DIR/lib/butin/backfill.py" "$CLAUDE_DIR/butin/backfill.py"
cp "$REPO_DIR/adapters/claude-code/butin-collect.sh" "$CLAUDE_DIR/butin/butin-collect.sh"
cp "$REPO_DIR/adapters/claude-code/adapter.sh" "$CLAUDE_DIR/butin/adapter.sh"
chmod +x "$CLAUDE_DIR/butin/butin-collect.sh"
cp "$REPO_DIR/bin/amiral-journal" "$CLAUDE_DIR/amiral-journal"
chmod +x "$CLAUDE_DIR/amiral-journal"
echo "  ok  amiral-butin (+ core, collector, journal)"

# statusline (v0.13): opt-in, wired via `amiral statusline install`
cp "$REPO_DIR/bin/amiral-statusline" "$CLAUDE_DIR/butin/amiral-statusline.sh"
chmod +x "$CLAUDE_DIR/butin/amiral-statusline.sh"
cp "$REPO_DIR/bin/amiral-statusline.ps1" "$CLAUDE_DIR/butin/amiral-statusline.ps1"
cp "$REPO_DIR/lib/butin/cache.sh" "$CLAUDE_DIR/butin/cache.sh"
chmod +x "$CLAUDE_DIR/butin/cache.sh"
echo "  ok  butin statusline (renderer + cache producer — opt-in, not wired yet)"

case "${SHELL:-}" in
  */zsh) RC_FILE="~/.zshrc" ;;
  */bash) RC_FILE="~/.bashrc" ;;
  *) RC_FILE="~/.zshrc (or your shell's rc file)" ;;
esac

cat << EOF

============================================================
Installed. The admiral doesn't row.

Final steps (2 min):

1) Load the profiles in your shell (skip if already present):
     grep -qF 'amiral-profiles.sh' $RC_FILE 2>/dev/null || echo 'source $CLAUDE_DIR/amiral-profiles.sh' >> $RC_FILE
     source $RC_FILE
   PowerShell (Windows): add to \$PROFILE:
     . "\$HOME\\.claude\\amiral-profiles.ps1"

2) Update Claude Code (Sonnet 5 needs v2.1.197+):
     claude update

3) Run the doctor, then VERIFY the worker routing (once):
     amiral-doctor
     cd <a project> && amiral
     # ask for something that delegates, then check /agents or the
     # transcript: workers must run on Sonnet, not the brain model.

That is it. To use amiral, type ONE word and just talk:

  amiral
  > add email validation to the signup form

The admiral judges each task and routes it; you never pick a model,
effort, or agent. Optional variants (amiral-fine, amiral-ultra, matelot)
and /plan-ship exist for power users, but you never need them to start.

Fleet config (env): AMIRAL_BRAIN (default opus), AMIRAL_HANDS (default sonnet)
  Defaults: brain=opus (included on Max; Pro serves Sonnet in-plan),
  hands=sonnet. On Pro and want all-Sonnet? use  amiral-solo
  Want the premium planning brain?  AMIRAL_BRAIN=fable amiral

Statusline is opt-in — amiral statusline install (backs up + restores any existing statusline)
============================================================
EOF
