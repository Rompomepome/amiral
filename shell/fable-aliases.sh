# --- fable-lean : quota-optimized Claude Code profiles ---
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
# If `sonnet`/`haiku` are not resolved as SUBAGENT_MODEL on your version,
# replace with the full model ID (e.g. claude-sonnet-5).
# NOTE: profiles run with --dangerously-skip-permissions for zero-friction
# agentic work. Remove that flag if you prefer permission prompts.

# Daily driver: Fable brain, xhigh reasoning, ONE window (no ruinous
# auto-fan-out), all subagents FORCED onto Sonnet.
alias fable-lean='CLAUDE_CODE_EFFORT_LEVEL=xhigh CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model fable --dangerously-skip-permissions'

# Fine-grained: same, but workers follow their frontmatter
# (implementer=sonnet, grunt=haiku, reviewer=sonnet).
alias fable-fine='CLAUDE_CODE_EFFORT_LEVEL=xhigh claude --model fable --dangerously-skip-permissions'

# Big multi-agent audits: Fable + ultracode. QUOTA INCINERATOR (a 5h
# window can vanish in ~7 min). ultracode is not settable via env:
# launch, then type /effort and pick ultracode.
alias fable-ultra='CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model fable --dangerously-skip-permissions'

# Pure-Sonnet daily workhorse, for everything that doesn't deserve Fable.
alias sonnet-fast='CLAUDE_CODE_EFFORT_LEVEL=high claude --model sonnet --dangerously-skip-permissions'
