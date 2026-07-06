# --- amiral : the admiral doesn't row (PowerShell) ---
# ONE command: type amiral, then just talk. The admiral routes every
# task itself; you never pick a model, effort, or agent.
# Install: add to your PowerShell profile ($PROFILE):
#   . "$HOME\.claude\amiral-profiles.ps1"
# Fleet: $env:AMIRAL_BRAIN (default fable), $env:AMIRAL_HANDS (default sonnet).
# Uses --effort (session level, overridable by agent frontmatter) rather
# than CLAUDE_CODE_EFFORT_LEVEL, which would force workers to xhigh.
# Permissions: default prompts (safe). See docs/permissions.md.

function Get-AmiralBrain { if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "fable" } }
function Get-AmiralHands { if ($env:AMIRAL_HANDS) { $env:AMIRAL_HANDS } else { "sonnet" } }

function amiral {
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model (Get-AmiralBrain) --effort xhigh @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}

function amiral-fine {
    claude --model (Get-AmiralBrain) --effort xhigh @args
}

# Launch, then /effort -> ultracode. QUOTA INCINERATOR - big audits only.
# Verify in /agents that workflow workers honor the hands model.
function amiral-ultra {
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model (Get-AmiralBrain) @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}

function matelot {
    claude --model (Get-AmiralHands) --effort high @args
}
