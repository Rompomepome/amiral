# --- amiral : the admiral doesn't row ---
# Orchestrator/worker profiles for Claude Code.
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
#
# Configurable fleet (survives model suspensions and renames):
#   AMIRAL_BRAIN  - orchestrator model  (default: fable;  e.g. opus)
#   AMIRAL_HANDS  - forced worker model (default: sonnet; e.g. claude-sonnet-5)
# Example: `AMIRAL_BRAIN=opus amiral` if Fable is ever unavailable again.
#
# Permissions: default prompts (safe by default). See docs/permissions.md
# for faster modes, from allowlists to full bypass (which we do not ship).

# Daily driver: brain at xhigh, ONE window, all workers FORCED cheap.
amiral() {
  CLAUDE_CODE_EFFORT_LEVEL=xhigh \
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# Fine-grained: workers follow their frontmatter
# (implementer=sonnet, grunt=haiku, reviewer=sonnet).
amiral-fine() {
  CLAUDE_CODE_EFFORT_LEVEL=xhigh \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# Big multi-agent audits: brain + ultracode. QUOTA INCINERATOR (a 5h
# window can vanish in ~7 min). ultracode is not settable via env:
# launch, then type /effort and pick ultracode.
amiral-ultra() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# Pure worker session, for everything that doesn't deserve the brain.
matelot() {
  CLAUDE_CODE_EFFORT_LEVEL=high \
  claude --model "${AMIRAL_HANDS:-sonnet}" "$@"
}
