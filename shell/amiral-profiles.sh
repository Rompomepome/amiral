# --- amiral : the admiral doesn't row ---
# ONE command. Type `amiral`, then just talk. The admiral judges each
# task and routes it — you never pick a model, effort, or agent.
#
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
#
# DEFAULTS (chosen for the plans most people actually have):
#   brain  = opus    -> included in Max; on Pro, Claude Code serves
#                       Sonnet within your plan. Nothing to pay, nothing
#                       to set.
#   hands  = sonnet  -> the workhorse, ~1/5 the cost of the frontier.
#
# Override only if you want to:
#   AMIRAL_BRAIN=fable amiral   # premium planning brain (metered after Jul 7)
#   AMIRAL_BRAIN=sonnet amiral  # all-Sonnet, lightest on a Pro plan
#   AMIRAL_HANDS=haiku  amiral  # even cheaper hands
#
# Permissions: default prompts (safe). See docs/permissions.md.

# THE command. Capable brain, workers forced cheap, admiral routes all.
# This is everything 99% of people need.
amiral() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-opus}" --effort high "$@"
}

# --- Optional variants (never needed to start) ---

# All-Sonnet fleet: lightest footprint, ideal on a Pro plan. Brain and
# hands both Sonnet; the admiral still triages and delegates.
amiral-solo() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-sonnet}" --effort high "$@"
}

# Let each worker follow its own frontmatter (Haiku for grunt work).
amiral-fine() {
  claude --model "${AMIRAL_BRAIN:-opus}" --effort high "$@"
}

# Premium multi-agent audits with the frontier brain + ultracode.
# QUOTA/CREDIT INCINERATOR. Launch, then type /effort and pick ultracode.
amiral-ultra() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# A pure worker session (no admiral), throwaway small stuff, cheap model.
matelot() {
  claude --model "${AMIRAL_HANDS:-sonnet}" --effort high "$@"
}

# Fleet health check.
amiral-doctor() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-doctor" "$@"
}
