# --- amiral : the admiral doesn't row ---
# Orchestrator/worker profiles for Claude Code.
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
#
# Configurable fleet (survives model suspensions and renames):
#   AMIRAL_BRAIN  - orchestrator model  (default: fable;  e.g. opus)
#   AMIRAL_HANDS  - forced worker model (default: sonnet; e.g. claude-sonnet-5)
# Example: `AMIRAL_BRAIN=opus amiral` for a pure-subscription fleet.
#
# Why `--effort` and NOT CLAUDE_CODE_EFFORT_LEVEL: the env var takes
# precedence over agent frontmatter, which would force every worker
# (including the low-effort grunt) to think at xhigh — a silent token
# leak. The --effort flag sets the session level, which per-agent
# frontmatter can override. Exactly what we want.
#
# Permissions: default prompts (safe by default). See docs/permissions.md.

# Daily driver: brain at xhigh, ONE window, all workers FORCED cheap.
amiral() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" --effort xhigh "$@"
}

# Fine-grained: workers follow their frontmatter
# (implementer=sonnet, grunt=haiku+low, reviewer=sonnet).
amiral-fine() {
  claude --model "${AMIRAL_BRAIN:-fable}" --effort xhigh "$@"
}

# Big multi-agent audits: brain + ultracode. QUOTA INCINERATOR (a 5h
# window can vanish in ~7 min). ultracode is not settable via env/flag:
# launch, then type /effort and pick ultracode.
# Caution: verify in /agents that dynamic-workflow workers honor the
# hands model — do not assume it on your first big run.
amiral-ultra() {
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# Pure worker session, for everything that doesn't deserve the brain.
matelot() {
  claude --model "${AMIRAL_HANDS:-sonnet}" --effort high "$@"
}

# Fleet health check: install, routing config, live-check instructions.
amiral-doctor() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-doctor" "$@"
}
