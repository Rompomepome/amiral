# --- amiral : the admiral doesn't row ---
# ONE command. Type `amiral`, then just talk. The admiral judges each
# task and routes it — you never pick a model, effort, or agent.
#
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
# Configurable fleet (optional — sensible defaults, nothing to set):
#   AMIRAL_BRAIN  - the admiral's model  (default: fable; e.g. opus)
#   AMIRAL_HANDS  - the workers' model   (default: sonnet)
# If Fable is metered/unavailable: `export AMIRAL_BRAIN=opus` and forget it.
#
# Permissions: default prompts (safe). See docs/permissions.md.

# THE command. Capable brain at high reasoning, workers forced cheap,
# admiral routes everything. This is all 99% of people ever need.
amiral() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" --effort xhigh "$@"
}

# --- Optional variants (you never need these to start) ---

# Let each worker follow its own frontmatter (Haiku for grunt work)
# instead of forcing them all to one model. Marginally cheaper.
amiral-fine() {
  claude --model "${AMIRAL_BRAIN:-fable}" --effort xhigh "$@"
}

# Big multi-agent audits. QUOTA INCINERATOR (a 5h window can vanish in
# ~7 min). Launch, then type /effort and pick ultracode.
amiral-ultra() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# A pure worker session (no admiral), for throwaway small stuff on the
# cheap model. Optional.
matelot() {
  claude --model "${AMIRAL_HANDS:-sonnet}" --effort high "$@"
}

# Fleet health check.
amiral-doctor() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-doctor" "$@"
}
