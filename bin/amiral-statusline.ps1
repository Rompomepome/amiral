# amiral butin — statusline renderer (PowerShell shape), v0.13.
#
# BACKLOG / SCOPE (docs/butin-spec-v2.md): POSIX shell is v1. This file
# ships and is documented, but `amiral statusline install` does NOT wire it
# automatically — PowerShell parity is tracked backlog, never an implied
# promise (DESIGN-NOTES.md §1.7). No chaining in this version either
# (backlog) — a pre-existing PowerShell statusLine is left untouched
# because install never touches settings.json on Windows.
#
# settings.json shape (forward slashes — Git Bash on Windows eats
# backslashes, doc-verified against code.claude.com/docs/en/statusline.md):
#   "command": "powershell -NoProfile -File %USERPROFILE%/.claude/butin/amiral-statusline.ps1"
#
# HONESTY INVARIANT: same as the bash renderer (bin/amiral-statusline) —
# this script never computes a savings figure and never reads butin.jsonl's
# content (LastWriteTime only). Every number comes from the same cache
# lib/butin/cache.sh writes; there is no separate PowerShell producer.
#
# Dependency-free: no external modules, base class library only.

$ErrorActionPreference = 'SilentlyContinue'
$ci = [Globalization.CultureInfo]::InvariantCulture

function Format-SignedDollar([double]$n) {
  $sign = if ($n -lt 0) { '-' } else { '+' }
  $abs = [Math]::Abs($n)
  return "$sign`$" + $abs.ToString('F2', $ci)
}

function Format-Humanize([double]$n) {
  if ($n -lt 1000) { return [Math]::Floor($n).ToString('F0', $ci) }
  elseif ($n -lt 100000) { return ($n / 1000).ToString('F1', $ci) + 'k' }
  else { return [Math]::Floor($n / 1000).ToString('F0', $ci) + 'k' }
}

function Parse-Num([string]$s, $fallback) {
  if ([string]::IsNullOrEmpty($s)) { return $fallback }
  try { return [double]::Parse($s, $ci) } catch { return $fallback }
}

try {
  # Always consume stdin, even unused — parity with the bash renderer's
  # contract (a future chained previous command would need it).
  $null = [Console]::In.ReadToEnd()

  $cache = Join-Path $env:USERPROFILE '.amiral\butin-cache.tsv'
  if (-not (Test-Path $cache)) { exit 0 }

  $kv = @{}
  Get-Content $cache | ForEach-Object {
    $parts = $_ -split "`t", 2
    if ($parts.Length -eq 2) { $kv[$parts[0]] = $parts[1] }
  }

  # Corrupt-cache guard: v must be "1", net_total must parse as a number.
  # Every numeric field is parsed with InvariantCulture — the cache is
  # C-locale data; a French Windows locale must not reintroduce the
  # comma-decimal bug the data plane exists to prevent (DESIGN-NOTES §1.7).
  if ($kv['v'] -ne '1') { exit 0 }
  $netTotal = Parse-Num $kv['net_total'] $null
  if ($null -eq $netTotal) { exit 0 }

  $netToday = Parse-Num $kv['net_today'] 0
  $premToday = Parse-Num $kv['prem_avoided_today'] 0
  $premTotal = Parse-Num $kv['prem_avoided_total'] 0
  $measured = [int](Parse-Num $kv['measured'] 0)
  $unmeasured = [int](Parse-Num $kv['unmeasured'] 0)
  $pending = [int](Parse-Num $kv['pending'] 0)
  $escToday = [int](Parse-Num $kv['esc_today'] 0)
  $mode = $kv['mode']
  if ([string]::IsNullOrEmpty($mode)) { $mode = 'api' }

  # MUTE: suppresses good news only — a net-negative day always shows,
  # honesty outranks mute, same rule as the bash renderer.
  $muteFile = Join-Path $env:USERPROFILE '.amiral\statusline-mute'
  if ((Test-Path $muteFile) -and ($netToday -ge 0)) { exit 0 }

  if ([string]::IsNullOrEmpty($env:NO_COLOR)) {
    $green = "`e[32m"; $amber = "`e[33m"; $dim = "`e[2m"; $rst = "`e[0m"
  } else {
    $green = ''; $amber = ''; $dim = ''; $rst = ''
  }
  if ($netToday -gt 0) { $col = $green } elseif ($netToday -lt 0) { $col = $amber } else { $col = $dim }

  if ($mode -eq 'plan') {
    # SPEC §5bis: premium tokens avoided is the hero, never a $ figure.
    $body = "⚓ $(Format-Humanize $premToday) prem tok avoided today · $(Format-Humanize $premTotal) total ($measured meas)"
  } else {
    $todayStr = Format-SignedDollar $netToday
    $totalStr = Format-SignedDollar $netTotal
    $escPart = ''
    if (($netToday -lt 0) -and ($escToday -ne 0)) {
      $escWord = if ($escToday -eq 1) { 'escalation' } else { 'escalations' }
      $escPart = " ($escToday $escWord)"
    }
    $covPart = " ($measured meas"
    if ($unmeasured -ne 0) { $covPart += " · $unmeasured unmeas" }
    if ($pending -ne 0) { $covPart += " · $pending pending" }
    $covPart += ')'
    $body = "⚓ $todayStr today$escPart · $totalStr net$covPart"
  }

  # stale marker: generated_epoch is already an epoch integer in the cache
  # (no date PARSING anywhere), compared against the newest mtime of
  # butin.jsonl/receipts.jsonl — their CONTENT is never read.
  $staleText = ''
  if ($kv.ContainsKey('generated_epoch')) {
    $genEpoch = Parse-Num $kv['generated_epoch'] $null
    if ($null -ne $genEpoch) {
      $amiralHome = Join-Path $env:USERPROFILE '.amiral'
      $newest = [double]0
      foreach ($f in @('butin.jsonl', 'receipts.jsonl')) {
        $p = Join-Path $amiralHome $f
        if (Test-Path $p) {
          $epoch = [double]([DateTimeOffset](Get-Item $p).LastWriteTimeUtc).ToUnixTimeSeconds()
          if ($epoch -gt $newest) { $newest = $epoch }
        }
      }
      if (($newest -gt 0) -and (($newest - $genEpoch) -gt 600)) { $staleText = " $dim· stale$rst" }
    }
  }

  Write-Output "$col$body$rst$staleText"
  exit 0
} catch {
  # Never let an unexpected exception surface — same contract as the bash
  # renderer: a broken statusline script must degrade to blank, not error.
  exit 0
}
