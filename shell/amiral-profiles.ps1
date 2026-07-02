# --- amiral : the admiral doesn't row (PowerShell) ---
# Install: add to your PowerShell profile ($PROFILE):
#   . "$HOME\.claude\amiral-profiles.ps1"
# Configurable fleet: $env:AMIRAL_BRAIN (default fable),
#                     $env:AMIRAL_HANDS (default sonnet).
# Permissions: default prompts (safe). See docs/permissions.md.

function Invoke-AmiralSession {
    param([string]$Effort, [string]$ForceHands, [string[]]$Rest)
    $brain = if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "fable" }
    $hands = if ($env:AMIRAL_HANDS) { $env:AMIRAL_HANDS } else { "sonnet" }
    if ($Effort)     { $env:CLAUDE_CODE_EFFORT_LEVEL = $Effort }
    if ($ForceHands) { $env:CLAUDE_CODE_SUBAGENT_MODEL = $hands }
    try { claude --model $brain @Rest }
    finally {
        Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL, Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue
    }
}

function amiral       { Invoke-AmiralSession -Effort "xhigh" -ForceHands "yes" -Rest $args }
function amiral-fine  { Invoke-AmiralSession -Effort "xhigh" -Rest $args }
# Launch, then /effort -> ultracode. QUOTA INCINERATOR - big audits only.
function amiral-ultra { Invoke-AmiralSession -ForceHands "yes" -Rest $args }
function matelot {
    $hands = if ($env:AMIRAL_HANDS) { $env:AMIRAL_HANDS } else { "sonnet" }
    $env:CLAUDE_CODE_EFFORT_LEVEL = "high"
    try { claude --model $hands @args }
    finally { Remove-Item Env:CLAUDE_CODE_EFFORT_LEVEL -ErrorAction SilentlyContinue }
}
