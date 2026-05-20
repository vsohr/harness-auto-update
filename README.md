# harness-auto-update

Background updater for local AI CLI harness shells. Two surfaces are covered:

- **WSL** (`harness-auto-update.sh` + `shell-hook.sh`): nvm-managed Claude Code, Codex, and a clean fast-forward of `~/.hermes/hermes-agent`.
- **Windows / PowerShell** (`harness-auto-update.ps1` + `shell-hook.ps1`): the Windows npm-global Claude Code and Codex. Hermes is out of scope on this side -- the WSL hook owns it.

Hermes is intentionally skipped when the checkout has local changes. The updater should never overwrite local Hermes edits.

## Usage (WSL)

```bash
bash /mnt/c/git/harness-auto-update/harness-auto-update.sh --background
```

Automatic background mode runs at most once per day. Force a run with:

```bash
bash /mnt/c/git/harness-auto-update/harness-auto-update.sh --force
```

Check the last run and log with:

```bash
bash /mnt/c/git/harness-auto-update/harness-auto-update.sh --status
```

## Configuration

```bash
AI_CLI_UPDATE_DISABLE=1              # disable automatic runs
AI_CLI_UPDATE_INTERVAL_SECONDS=86400 # default interval
HERMES_AGENT_DIR=~/.hermes/hermes-agent
```

The script sources `~/.nvm/nvm.sh` before updating Claude and Codex. If `npm` resolves to a Windows `/mnt/c/...` path inside WSL, it skips the Node CLI updates instead of modifying the wrong installation.

To use the shared hook from an interactive shell:

```bash
if [ -f /mnt/c/git/harness-auto-update/shell-hook.sh ]; then
  . /mnt/c/git/harness-auto-update/shell-hook.sh
fi
```

The hook also keeps the active nvm `bin` directory ahead of `~/.local/bin`, so stale local shims do not shadow the nvm-managed Claude and Codex installs.

## Usage (Windows / PowerShell)

```powershell
& 'C:\git\harness-auto-update\harness-auto-update.ps1' --background
& 'C:\git\harness-auto-update\harness-auto-update.ps1' --force
& 'C:\git\harness-auto-update\harness-auto-update.ps1' --status
```

`--background` forks a hidden PowerShell child so the launching shell never blocks on `npm install`. State lives under `%LOCALAPPDATA%\harness-auto-update\` (`last-run` stamp, `update.log`, `update.lock`).

To wire the hook into every interactive PowerShell session, add this to your `$PROFILE` (`$PROFILE` resolves to `Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` for Windows PowerShell, or `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` for PowerShell 7):

```powershell
if (Test-Path 'C:\git\harness-auto-update\shell-hook.ps1') {
    . 'C:\git\harness-auto-update\shell-hook.ps1'
}
```

The Windows side targets the system Node install on `PATH` (typically `C:\Program Files\nodejs\npm`). nvm-windows is not assumed; if you use it, make sure the desired Node version is the active default before the hook fires.
