# --- amiral : the admiral doesn't row ---
# ONE command. Type `amiral`. First time, it asks your plan once and
# remembers it. After that, just talk — the admiral routes every task
# (model, effort, agent) itself.
#
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
# Preferences live in ~/.claude/amiral.env (written by amiral-setup).
# Defaults if you skip setup: brain=opus (in-plan on Max; Pro serves
# Sonnet), hands=sonnet. Override per-run with AMIRAL_BRAIN/AMIRAL_HANDS.
# Permissions: default prompts (safe). See docs/permissions.md.

# Load saved preferences if present (sets AMIRAL_BRAIN / AMIRAL_HANDS).
_amiral_load_prefs() {
  local p="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral.env"
  [ -f "$p" ] && . "$p"
}

# First-run: if no prefs yet and setup exists, run it once.
_amiral_first_run() {
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  if [ ! -f "$dir/amiral.env" ] && [ -x "$dir/amiral-setup" ]; then
    bash "$dir/amiral-setup"
  fi
}

# --- Statusline profile marker (v0.13.1) ---
# Every profile function below prefixes its `claude` invocation with
# AMIRAL_PROFILE=<name> — scoped to that ONE command line, never `export`ed
# — so bin/amiral-statusline can show "this session was launched via
# <profile>". Why not just read AMIRAL_BRAIN/AMIRAL_HANDS instead? Verified
# live: _amiral_load_prefs sources ~/.claude/amiral.env with `export`, which
# then pollutes the CURRENT interactive shell — a later BARE `claude` launch
# in that same shell still carries AMIRAL_BRAIN/AMIRAL_HANDS from the
# earlier amiral() call and would render a FALSE "amiral on" marker. A
# dedicated, never-exported, per-command variable is the only honest
# signal; guessing from those vars is forbidden.
#
# Scope note (see docs/butin.md): the routing POLICY in this file is
# imported into ~/.claude/CLAUDE.md, so it is GLOBAL — it governs every
# Claude Code session, including a bare `claude` launch that carries no
# marker at all. Only the PROFILE marker is per-session: it means "this
# session's `claude` was launched by <profile>", nothing more, and its
# absence does not mean the policy is off.

# THE command. Capable brain, workers forced cheap, admiral routes all.
amiral() {
  case "${1:-}" in statusline)
    shift
    bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-butin" statusline "$@"; return $? ;;
  esac
  _amiral_first_run
  _amiral_load_prefs
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" AMIRAL_PROFILE=amiral \
  claude --model "${AMIRAL_BRAIN:-opus}" --effort high "$@"
}

# --- Optional variants (never needed to start) ---

# All-Sonnet fleet: lightest footprint, ideal on a Pro plan.
amiral-solo() {
  _amiral_load_prefs
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" AMIRAL_PROFILE=solo \
  claude --model sonnet --effort high "$@"
}

# ADVISOR MODE. You run on the cheap model the whole time; it consults
# the expensive brain (the `advisor` agent) only for hard calls. This is
# the "executor + on-demand advisor" pattern: most tokens billed at the
# worker rate, frontier reasoning only where it changes the outcome.
amiral-advisor() {
  _amiral_load_prefs
  AMIRAL_PROFILE=advisor \
  claude --model "${AMIRAL_HANDS:-sonnet}" --effort high "$@"
}

# Workers follow their own frontmatter (Haiku for grunt work).
amiral-fine() {
  _amiral_load_prefs
  AMIRAL_PROFILE=fine \
  claude --model "${AMIRAL_BRAIN:-opus}" --effort high "$@"
}

# Premium multi-agent audits, frontier brain + ultracode.
# QUOTA/CREDIT INCINERATOR. Launch, then type /effort and pick ultracode.
amiral-ultra() {
  _amiral_load_prefs
  CLAUDE_CODE_SUBAGENT_MODEL="${AMIRAL_HANDS:-sonnet}" AMIRAL_PROFILE=ultra \
  claude --model "${AMIRAL_BRAIN:-fable}" "$@"
}

# Pure worker session (no admiral), throwaway small stuff, cheap model.
matelot() {
  _amiral_load_prefs
  AMIRAL_PROFILE=matelot \
  claude --model "${AMIRAL_HANDS:-sonnet}" --effort high "$@"
}

# Re-run the one-time plan setup anytime.
amiral-setup() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-setup" "$@"
}

# Estimate what the pattern saves vs all-frontier (local math).
amiral-savings() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-savings" "$@"
}

# Prove amiral's ROI from your own routed tasks (local, net, auditable).
amiral-butin() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-butin" "$@"
}

# Package YOUR benchmark numbers into a shareable issue (local, voluntary).
amiral-report() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-report" "$@"
}

# Provenance for AI-assisted commits (opt-in, per repo).
amiral-journal() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-journal" "$@"
}

# Fleet health check.
amiral-doctor() {
  bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/amiral-doctor" "$@"
}
