# --- fable-lean : quota-optimized Claude Code profiles (PowerShell) ---
# Install: add to your PowerShell profile ($PROFILE):
#   . "$HOME\.claude\fable-profiles.ps1"
# Prereq: `claude update` (Sonnet 5 needs v2.1.197+).
# Permissions: default prompts (safe). See docs/permissions.md for
# faster modes.

function fable-lean {
    $env:CLAUDE_CODE_EFFORT_LEVEL = "xhigh"
    $env:CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"
    claude --model fable @args
    Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL, Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue
}

function fable-fine {
    $env:CLAUDE_CODE_EFFORT_LEVEL = "xhigh"
    claude --model fable @args
    Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL -ErrorAction SilentlyContinue
}

# Fable + ultracode: launch, then type /effort and pick ultracode.
# QUOTA INCINERATOR — big audits only.
function fable-ultra {
    $env:CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"
    claude --model fable @args
    Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue
}

function sonnet-fast {
    $env:CLAUDE_CODE_EFFORT_LEVEL = "high"
    claude --model sonnet @args
    Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL -ErrorAction SilentlyContinue
}
