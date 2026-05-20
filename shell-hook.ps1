# Shared interactive-shell hook for harness-auto-update (PowerShell).
#
# Source from your $PROFILE:
#   if (Test-Path 'C:\git\harness-auto-update\shell-hook.ps1') {
#       . 'C:\git\harness-auto-update\shell-hook.ps1'
#   }

if ($env:HARNESS_AUTO_UPDATE_HOOK_LOADED -eq '1') { return }
$env:HARNESS_AUTO_UPDATE_HOOK_LOADED = '1'

$script = if ($env:AI_CLI_UPDATE_SCRIPT) {
    $env:AI_CLI_UPDATE_SCRIPT
} else {
    'C:\git\harness-auto-update\harness-auto-update.ps1'
}

if ($env:AI_CLI_UPDATE_DISABLE -ne '1' -and (Test-Path -LiteralPath $script)) {
    try {
        & $script --background | Out-Null
    } catch {
        # Hook must never break an interactive shell.
    }
}
