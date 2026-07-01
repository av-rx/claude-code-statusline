<#
    Claude Code status line installer (native Windows / PowerShell).

    WHAT THIS DOES:
      1. Writes the status line script to  $HOME\.claude\statusline-command.ps1
      2. Adds the "statusLine" setting to   $HOME\.claude\settings.json,
         MERGING into any existing settings (a timestamped .bak backup is made first).

    HOW TO RUN IT:
      Hand this file to Claude Code and say: "run install-statusline.ps1 to set up my status line".
      (Or in PowerShell:  powershell -ExecutionPolicy Bypass -File install-statusline.ps1 )

    Safe to run more than once - it just refreshes the files.
#>

$ErrorActionPreference = 'Stop'

$ClaudeDir    = Join-Path $HOME '.claude'
$ScriptPath   = Join-Path $ClaudeDir 'statusline-command.ps1'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# -- 1. Write the status line script -------------------------------------------
# Single-quoted here-string: everything is written verbatim, nothing expands.
$statusline = @'
#!/usr/bin/env pwsh
# Claude Code Status Line (PowerShell / native Windows)
#
# Reads the session JSON piped to it by Claude Code on stdin and prints a
# single colour-coded status line. Works on Windows PowerShell 5.1 and
# PowerShell 7+. No external tools required.

# Read the piped JSON from stdin.
$raw = $input | Out-String
if (-not $raw.Trim()) { return }
try { $data = $raw | ConvertFrom-Json } catch { return }

# Emit UTF-8 so the bar/box glyphs render correctly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ESC   = [char]27
$RESET = "$ESC[0m"

# -- Colour palette (256-colour ANSI) ------------------------------------------
$C_MODEL     = "$ESC[38;5;183m"   # soft lavender   - model name
$C_EFFORT    = "$ESC[38;5;139m"   # dusty mauve     - effort suffix
$C_BAR_NEUT  = "$ESC[38;5;248m"   # light gray      - bar fill, low usage
$C_BAR_WARN  = "$ESC[38;5;221m"   # golden yellow   - bar fill, mid usage
$C_BAR_CRIT  = "$ESC[38;5;210m"   # soft coral      - bar fill, high usage
$C_BAR_EMPTY = "$ESC[38;5;240m"   # dark gray       - empty bar cells
$C_MUTED     = "$ESC[38;5;242m"   # dim gray        - secondary / token counts
$C_LOCATION  = "$ESC[38;5;110m"   # muted sky blue  - repo / dir name
$C_SESSION   = "$ESC[38;5;252m"   # near-white      - session name
$C_OK        = "$ESC[38;5;150m"   # sage green      - PR approved
$C_WARN      = "$ESC[38;5;221m"   # golden yellow   - open PR, mid rate limit
$C_CRIT      = "$ESC[38;5;210m"   # soft coral      - changes requested, high rate limit
$C_DRAFT     = "$ESC[38;5;242m"   # dim gray        - PR draft
$C_PCT_LOW   = "$ESC[38;5;73m"    # teal            - low percentage value

# -- Glyphs (by code point so this file stays pure ASCII) ----------------------
$G_FULL   = [char]0x2588          # full block
$G_SHADE  = [char]0x2591          # light shade (empty bar cell)
$G_BAR    = [char]0x2502          # vertical bar (separator)
$G_CHECK  = [char]0x2713          # check mark
$G_CROSS  = [char]0x2717          # ballot x
$G_MIDDOT = [char]0x00B7          # middle dot

$SEP = " $ESC[38;5;244m$G_BAR$RESET "

# -- Helpers -------------------------------------------------------------------
function Get-Field {
    param($obj, [string]$path)
    $cur = $obj
    foreach ($k in $path.Split('.')) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.$k
    }
    return $cur
}

function Test-Val {
    param($v)
    return ($null -ne $v) -and ("$v" -ne "")
}

function Get-PctColor {
    param([int]$pct)
    if     ($pct -ge 85) { return $C_CRIT }
    elseif ($pct -ge 60) { return $C_WARN }
    else                 { return $C_PCT_LOW }
}

function New-Bar {
    param([int]$pct, [int]$width)
    $filled = [int][math]::Floor($pct * $width / 100)
    if ($filled -lt 0)      { $filled = 0 }
    if ($filled -gt $width) { $filled = $width }
    $empty = $width - $filled
    if     ($pct -ge 85) { $color = $C_BAR_CRIT }
    elseif ($pct -ge 60) { $color = $C_BAR_WARN }
    else                 { $color = $C_BAR_NEUT }
    return $color + ($G_FULL.ToString() * $filled) + $C_BAR_EMPTY + ($G_SHADE.ToString() * $empty) + $RESET
}

function Format-Tokens {
    param($n)
    $n = [double]$n
    if ($n -ge 1000000) {
        $v = $n / 1000000
        if ($v -eq [math]::Floor($v)) { return ('{0:0}M' -f $v) }
        return ('{0:0.0}M' -f $v)
    }
    return ('{0:0}k' -f [math]::Floor($n / 1000))
}

# Returns a formatted reset time only when the timestamp is in the future.
function Format-Reset {
    param($ts, [string]$mode)
    try {
        $unix = [long]$ts
        if ($unix -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { return $null }
        $dt = [DateTimeOffset]::FromUnixTimeSeconds($unix).LocalDateTime
        if ($mode -eq 'short') { return $dt.ToString('HH:mm') }
        $hour = $dt.Hour
        $ampm = if ($hour -ge 12) { 'pm' } else { 'am' }
        $h12  = $hour % 12
        if ($h12 -eq 0) { $h12 = 12 }
        return ($dt.ToString('MMM ') + $dt.Day + ' ' + $h12 + $ampm)
    } catch { return $null }
}

$parts = @()

# -- 1. MODEL + EFFORT ---------------------------------------------------------
$model  = Get-Field $data 'model.display_name'
$effort = Get-Field $data 'effort.level'
if (Test-Val $model) {
    $mp = "$C_MODEL$model$RESET"
    if (Test-Val $effort) { $mp += " $C_EFFORT$effort$RESET" }
    $parts += $mp
}

# -- 2. CONTEXT BAR ------------------------------------------------------------
$usedPct = Get-Field $data 'context_window.used_percentage'
if (Test-Val $usedPct) {
    $usedInt = [int][math]::Round([double]$usedPct)
    $bar     = New-Bar $usedInt 10
    $pctC    = Get-PctColor $usedInt
    $totalInput = Get-Field $data 'context_window.total_input_tokens'
    $ctxSize    = Get-Field $data 'context_window.context_window_size'
    $tokenStr = ''
    if ((Test-Val $totalInput) -and (Test-Val $ctxSize)) {
        $tokenStr = " $C_MUTED" + (Format-Tokens $totalInput) + '/' + (Format-Tokens $ctxSize) + $RESET
    }
    $parts += "$bar $pctC$usedInt%$RESET$tokenStr"
}

# -- 3. LOCATION ---------------------------------------------------------------
$repoOwner  = Get-Field $data 'workspace.repo.owner'
$repoName   = Get-Field $data 'workspace.repo.name'
$projectDir = Get-Field $data 'workspace.project_dir'
$cwd        = Get-Field $data 'cwd'
if ((Test-Val $repoOwner) -and (Test-Val $repoName)) {
    $lp = "$C_MUTED$repoOwner/$RESET$C_LOCATION$repoName$RESET"
    $wt = Get-Field $data 'workspace.git_worktree'
    if (Test-Val $wt) { $lp += "$C_MUTED@$wt$RESET" }
    $parts += $lp
} elseif (Test-Val $projectDir) {
    $parts += "$C_LOCATION" + (Split-Path -Leaf $projectDir) + $RESET
} elseif (Test-Val $cwd) {
    $parts += "$C_LOCATION" + (Split-Path -Leaf $cwd) + $RESET
}

# -- 4. SESSION ----------------------------------------------------------------
$session = Get-Field $data 'session_name'
if (Test-Val $session) { $parts += "$C_SESSION$session$RESET" }

# -- 5. PR ---------------------------------------------------------------------
$prNum = Get-Field $data 'pr.number'
if (Test-Val $prNum) {
    $prState = Get-Field $data 'pr.review_state'
    if (-not (Test-Val $prState)) { $prState = 'open' }
    switch ($prState) {
        'approved'          { $prColor = $C_OK;    $prLabel = $G_CHECK }
        'changes_requested' { $prColor = $C_CRIT;  $prLabel = $G_CROSS }
        'draft'             { $prColor = $C_DRAFT; $prLabel = '~' }
        default             { $prColor = $C_WARN;  $prLabel = $G_MIDDOT }
    }
    $parts += "$C_MUTED#$RESET$prColor$prNum $prLabel $prState$RESET"
}

# -- 6. RATE LIMITS ------------------------------------------------------------
$fivePct    = Get-Field $data 'rate_limits.five_hour.used_percentage'
$fiveResets = Get-Field $data 'rate_limits.five_hour.resets_at'
$weekPct    = Get-Field $data 'rate_limits.seven_day.used_percentage'
$weekResets = Get-Field $data 'rate_limits.seven_day.resets_at'
if ((Test-Val $fivePct) -or (Test-Val $weekPct)) {
    $rp = ''
    if (Test-Val $fivePct) {
        $fi = [int][math]::Round([double]$fivePct)
        $rc = Get-PctColor $fi
        $rp = "$C_MUTED" + "5h $RESET$rc$fi%$RESET"
        if (Test-Val $fiveResets) {
            $t = Format-Reset $fiveResets 'short'
            if ($t) { $rp += " $C_MUTED$t$RESET" }
        }
    }
    if (Test-Val $weekPct) {
        $wi = [int][math]::Round([double]$weekPct)
        $rc = Get-PctColor $wi
        if ($rp -ne '') { $rp += '  ' }
        $rp += "$C_MUTED" + "7d $RESET$rc$wi%$RESET"
        if (Test-Val $weekResets) {
            $t = Format-Reset $weekResets 'long'
            if ($t) { $rp += " $C_MUTED$t$RESET" }
        }
    }
    $parts += $rp
}

# -- ASSEMBLE ------------------------------------------------------------------
[Console]::Out.Write(($parts -join $SEP) + "`n")
'@

# Write the script as UTF-8 without BOM.
[System.IO.File]::WriteAllText($ScriptPath, $statusline, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  Wrote status line script -> $ScriptPath"

# -- 2. Merge the statusLine setting into settings.json (non-destructive) ------
if (Test-Path $SettingsPath) {
    $stamp  = Get-Date -Format 'yyyyMMddHHmmss'
    $backup = "$SettingsPath.bak.$stamp"
    Copy-Item -Path $SettingsPath -Destination $backup
    Write-Host "OK  Backed up existing settings -> $backup"
}

$settings = $null
if (Test-Path $SettingsPath) {
    $rawSettings = Get-Content -Path $SettingsPath -Raw
    if ($rawSettings.Trim()) {
        try { $settings = $rawSettings | ConvertFrom-Json }
        catch {
            Write-Error "Existing settings.json is not valid JSON - aborting so nothing is lost. Fix or remove $SettingsPath and re-run."
            exit 3
        }
    }
}
if ($null -eq $settings) { $settings = [PSCustomObject]@{} }

# Use a forward-slash path so the command works whether Claude Code routes it
# through Git Bash or PowerShell.
$fwdPath = $ScriptPath -replace '\\', '/'
$command = "powershell -NoProfile -File $fwdPath"
$statusLineValue = [PSCustomObject]@{ type = 'command'; command = $command }

$settings | Add-Member -MemberType NoteProperty -Name statusLine -Value $statusLineValue -Force

$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($SettingsPath, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  Added statusLine to -> $SettingsPath"
Write-Host ""
Write-Host "Done. Restart Claude Code (or open a new session) to see the status line."
