# --- amiral : the admiral doesn't row (PowerShell) ---
# ONE command: type amiral, then just talk. The admiral routes every
# task itself; you never pick a model, effort, or agent.
# Install: add to $PROFILE:  . "$HOME\.claude\amiral-profiles.ps1"
#
# Defaults: brain=opus (included in Max; Pro serves Sonnet within plan),
#           hands=sonnet. Override with $env:AMIRAL_BRAIN / $env:AMIRAL_HANDS.
# Permissions: default prompts (safe). See docs/permissions.md.

function Get-AmiralBrain { if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "opus" } }
function Get-AmiralHands { if ($env:AMIRAL_HANDS) { $env:AMIRAL_HANDS } else { "sonnet" } }

function amiral {
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model (Get-AmiralBrain) --effort high @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}

function amiral-solo {
    $b = if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "sonnet" }
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model $b --effort high @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}

function amiral-fine { claude --model (Get-AmiralBrain) --effort high @args }

# Premium frontier audit; launch then /effort -> ultracode. Incinerator.
function amiral-ultra {
    $b = if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "fable" }
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model $b @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}

function matelot { claude --model (Get-AmiralHands) --effort high @args }
