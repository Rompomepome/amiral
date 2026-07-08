# --- amiral : the admiral doesn't row (PowerShell) ---
# ONE command: type amiral. First time it asks your plan once and
# remembers it; after that just talk. Install: add to $PROFILE:
#   . "$HOME\.claude\amiral-profiles.ps1"
# Prefs live in ~\.claude\amiral.env. Permissions: default (safe).

function _Amiral-Dir { if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$HOME\.claude" } }

function _Amiral-LoadPrefs {
    $p = Join-Path (_Amiral-Dir) "amiral.env"
    if (Test-Path $p) {
        Get-Content $p | ForEach-Object {
            if ($_ -match '^\s*export\s+(AMIRAL_\w+)=(.+)$') {
                Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
            }
        }
    }
}

function amiral-setup {
    $dir = _Amiral-Dir; $prefs = Join-Path $dir "amiral.env"
    Write-Host "`n⚓ amiral — one-time setup (10 seconds)`n"
    Write-Host "Which Claude plan are you on? Sets the best brain included in YOUR plan.`n"
    Write-Host "  1) Pro                 -> Sonnet   (all-in-plan, lightest)"
    Write-Host "  2) Max / Team Premium  -> Opus     (included on Max)"
    Write-Host "  3) Usage credits, premium brain -> Fable (metered after Jul 7, 2026)"
    Write-Host "  4) Not sure / safe default      -> Opus`n"
    $choice = Read-Host "Enter 1-4 [4]"
    switch ($choice) {
        "1" { $brain = "sonnet" }
        "2" { $brain = "opus" }
        "3" { $brain = "fable" }
        default { $brain = "opus" }
    }
    "# amiral preferences (amiral-setup)`nexport AMIRAL_BRAIN=$brain`nexport AMIRAL_HANDS=sonnet" |
        Set-Content -Path $prefs -Encoding UTF8
    $adv = Join-Path $dir "agents\advisor.md"
    if (Test-Path $adv) {
        (Get-Content $adv) -replace '^model: .*', "model: $brain" | Set-Content $adv
        Write-Host "  advisor agent pinned to: $brain"
    }
    Write-Host "`n✓ Saved: brain=$brain, hands=sonnet. Just type 'amiral' from now on.`n"
}

function _Amiral-FirstRun {
    $prefs = Join-Path (_Amiral-Dir) "amiral.env"
    if (-not (Test-Path $prefs)) { amiral-setup }
}

function Get-AmiralBrain { if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "opus" } }
function Get-AmiralHands { if ($env:AMIRAL_HANDS) { $env:AMIRAL_HANDS } else { "sonnet" } }

function amiral {
    _Amiral-FirstRun; _Amiral-LoadPrefs
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model (Get-AmiralBrain) --effort high @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}
function amiral-solo {
    _Amiral-LoadPrefs
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model sonnet --effort high @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}
function amiral-advisor {
    _Amiral-LoadPrefs
    claude --model (Get-AmiralHands) --effort high @args
}

function amiral-fine { _Amiral-LoadPrefs; claude --model (Get-AmiralBrain) --effort high @args }
function amiral-ultra {
    _Amiral-LoadPrefs
    $b = if ($env:AMIRAL_BRAIN) { $env:AMIRAL_BRAIN } else { "fable" }
    $env:CLAUDE_CODE_SUBAGENT_MODEL = Get-AmiralHands
    try { claude --model $b @args }
    finally { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}
function matelot { _Amiral-LoadPrefs; claude --model (Get-AmiralHands) --effort high @args }
