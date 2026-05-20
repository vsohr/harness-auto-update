# Update Windows-side AI CLIs used by PowerShell harness shells.
#
# Mirrors harness-auto-update.sh for the Windows npm-global install.
# Hermes is intentionally out of scope on Windows -- the WSL bash hook owns it.

$ErrorActionPreference = 'Stop'

# Use $args directly so bash-style flags like --status survive PowerShell parameter binding.
$Mode = if ($args.Count -gt 0) { $args[0] } else { '--run-if-due' }
$validModes = @('--background','--force','--run','--run-if-due','--status','-h','--help')
if ($validModes -notcontains $Mode) {
    Write-Error "unknown mode: $Mode (expected one of: $($validModes -join ', '))"
    exit 2
}

$IntervalSeconds = if ($env:AI_CLI_UPDATE_INTERVAL_SECONDS) { [int]$env:AI_CLI_UPDATE_INTERVAL_SECONDS } else { 86400 }
$CacheDir        = if ($env:AI_CLI_UPDATE_CACHE_DIR) { $env:AI_CLI_UPDATE_CACHE_DIR } else { Join-Path $env:LOCALAPPDATA 'harness-auto-update' }
$StampFile       = if ($env:AI_CLI_UPDATE_STAMP_FILE) { $env:AI_CLI_UPDATE_STAMP_FILE } else { Join-Path $CacheDir 'last-run' }
$LogFile         = if ($env:AI_CLI_UPDATE_LOG_FILE) { $env:AI_CLI_UPDATE_LOG_FILE } else { Join-Path $CacheDir 'update.log' }
$LockDir         = if ($env:AI_CLI_UPDATE_LOCK_DIR) { $env:AI_CLI_UPDATE_LOCK_DIR } else { Join-Path $CacheDir 'update.lock' }

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    # Append directly to the log file. Doing this via Write-Output would let
    # callers in parenthesized expressions (e.g. `-not (Update-NodeClis)`) swallow
    # the line as part of their captured output.
    try {
        if ($LogFile) {
            $dir = Split-Path -Parent -Path $LogFile
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Add-Content -LiteralPath $LogFile -Value $line -Encoding utf8
        }
    } catch {
        # Best effort -- never let logging failure abort an update.
    }
    if ($env:AI_CLI_UPDATE_VERBOSE -eq '1') {
        Write-Host $line
    }
}

function Show-Usage {
    @'
Usage: harness-auto-update.ps1 [--background|--force|--run|--status]

Updates the Windows-side AI CLIs used by PowerShell harness shells:
  - @anthropic-ai/claude-code via the Windows npm-global
  - @openai/codex via the Windows npm-global

Hermes is updated by the WSL bash hook only; this script does not touch it.

Environment:
  AI_CLI_UPDATE_DISABLE=1              disable automatic runs
  AI_CLI_UPDATE_INTERVAL_SECONDS=86400 run interval for automatic mode
'@
}

function Initialize-CacheDir {
    if (-not (Test-Path -LiteralPath $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }
}

function Get-SecondsSinceStamp {
    if (-not (Test-Path -LiteralPath $StampFile)) { return [int]::MaxValue }
    $raw = (Get-Content -LiteralPath $StampFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $raw) { return [int]::MaxValue }
    $stamp = 0
    if (-not [int64]::TryParse($raw.Trim(), [ref]$stamp)) { return [int]::MaxValue }
    $now = [int64](Get-Date -UFormat %s)
    return [int]($now - $stamp)
}

function Test-ShouldRun {
    if ($env:AI_CLI_UPDATE_DISABLE -eq '1') {
        Write-Log 'AI_CLI_UPDATE_DISABLE=1; skipping updates'
        return $false
    }
    return (Get-SecondsSinceStamp) -ge $IntervalSeconds
}

function Invoke-WithLock {
    param([scriptblock]$Action)
    try {
        New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
    } catch {
        Write-Log 'another AI CLI update is already running'
        return 0
    }
    try {
        & $Action
    } finally {
        Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Update-NpmPackage {
    param([string]$Package, [string]$Label)
    Write-Log ("updating {0} ({1})" -f $Label, $Package)
    # Windows PowerShell 5.x treats native stderr as a terminating error under Stop.
    # Relax locally so npm warnings (e.g. EBUSY when Claude Code is running) reach the log instead of throwing.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & npm.cmd install -g "$Package" 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    foreach ($line in $output) { Write-Log ([string]$line) }
    if ($exit -ne 0) {
        Write-Log ("{0} update failed with exit code {1}" -f $Label, $exit)
        return $false
    }
    return $true
}

function Update-NodeClis {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Log 'npm not found on Windows PATH; skipping Claude/Codex updates'
        return $true
    }

    Write-Log ("updating Windows npm-global CLIs with {0}" -f $npm.Source)
    # Update each package independently so a lock on one (e.g. claude while Claude Code is running) does not block the other.
    $claudeOk = Update-NpmPackage -Package '@anthropic-ai/claude-code@latest' -Label 'Claude Code'
    $codexOk  = Update-NpmPackage -Package '@openai/codex@latest'             -Label 'Codex'

    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) {
        $v = (& claude --version 2>&1 | Select-Object -First 1)
        Write-Log "claude version: $v"
    }
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        $v = (& codex --version 2>&1 | Select-Object -First 1)
        Write-Log "codex version: $v"
    }
    return ($claudeOk -and $codexOk)
}

function Invoke-Updates {
    Initialize-CacheDir
    $ok = $true

    Write-Log 'starting AI CLI update'
    if (-not (Update-NodeClis)) { $ok = $false }

    if ($ok) {
        [int64](Get-Date -UFormat %s) | Out-File -LiteralPath $StampFile -Encoding ascii -Force
        Write-Log 'AI CLI update complete'
        return $true
    }
    Write-Log 'AI CLI update completed with errors'
    return $false
}

function Start-BackgroundRun {
    Initialize-CacheDir
    if (-not (Test-ShouldRun)) { return }
    $self = $PSCommandPath
    # Avoid shadowing the automatic $args variable inside this function scope.
    $childArgs = @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$self,'--run')
    Start-Process -FilePath 'powershell.exe' -ArgumentList $childArgs -WindowStyle Hidden | Out-Null
}

function Show-Status {
    Initialize-CacheDir
    Write-Output ("log: {0}" -f $LogFile)
    Write-Output ("stamp: {0}" -f $StampFile)
    if (Test-Path -LiteralPath $StampFile) {
        Write-Output ("last run: {0} seconds ago" -f (Get-SecondsSinceStamp))
    } else {
        Write-Output 'last run: never'
    }
    if (Test-Path -LiteralPath $LogFile) {
        Get-Content -LiteralPath $LogFile -Tail 40
    }
}

switch ($Mode) {
    '--background' { Start-BackgroundRun }
    '--force' {
        Initialize-CacheDir
        Invoke-WithLock { Invoke-Updates | Out-Null }
    }
    '--run' {
        Initialize-CacheDir
        Invoke-WithLock { Invoke-Updates | Out-Null }
    }
    '--run-if-due' {
        Initialize-CacheDir
        if (Test-ShouldRun) {
            Invoke-WithLock { Invoke-Updates | Out-Null }
        }
    }
    '--status'      { Show-Status }
    '-h'            { Show-Usage }
    '--help'        { Show-Usage }
    default         { Show-Usage; exit 2 }
}
