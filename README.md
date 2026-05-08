# harness-auto-update

Background updater for local AI CLI harness shells.

It updates the WSL-side tools used from interactive shells and ttyd:

- Claude Code: `@anthropic-ai/claude-code@latest`
- Codex: `@openai/codex@latest`
- Hermes: clean fast-forward of `~/.hermes/hermes-agent`

Hermes is intentionally skipped when the checkout has local changes. The updater should never overwrite local Hermes edits.

## Usage

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
