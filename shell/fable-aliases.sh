# --- fable-lean : quota-optimized Claude Code profiles ---
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
# If `sonnet`/`haiku` are not resolved as SUBAGENT_MODEL on your version,
# replace with the full model ID (e.g. claude-sonnet-5).
#
# Permissions: these profiles use Claude Code's DEFAULT permission
# prompts (safe by default). See docs/permissions.md for faster modes,
# from allowlists and `--permission-mode acceptEdits` up to the risks
# of full permission bypass (YOLO mode) — which we do not ship.

# Daily driver: Fable brain, xhigh reasoning, ONE window (no ruinous
# auto-fan-out), all subagents FORCED onto Sonnet.
alias fable-lean='CLAUDE_CODE_EFFORT_LEVEL=xhigh CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model fable'

# Fine-grained: same, but workers follow their frontmatter
# (implementer=sonnet, grunt=haiku, reviewer=sonnet).
alias fable-fine='CLAUDE_CODE_EFFORT_LEVEL=xhigh claude --model fable'

# Big multi-agent audits: Fable + ultracode. QUOTA INCINERATOR (a 5h
# window can vanish in ~7 min). ultracode is not settable via env:
# launch, then type /effort and pick ultracode.
alias fable-ultra='CLAUDE_CODE_SUBAGENT_MODEL=sonnet claude --model fable'

# Pure-Sonnet daily workhorse, for everything that doesn't deserve Fable.
alias sonnet-fast='CLAUDE_CODE_EFFORT_LEVEL=high claude --model sonnet'
