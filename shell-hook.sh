# Shared interactive-shell hook for harness-auto-update.

if [ "${HARNESS_AUTO_UPDATE_HOOK_LOADED:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
export HARNESS_AUTO_UPDATE_HOOK_LOADED=1

if [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.nvm/nvm.sh"
fi

if [ -n "${NVM_BIN:-}" ] && [ -d "$NVM_BIN" ]; then
  PATH="$(printf '%s' "$PATH" | awk -v RS=: -v ORS=: -v bin="$NVM_BIN" '$0 != bin { print }' | sed 's/:$//')"
  export PATH="$NVM_BIN:$PATH"
fi

if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$PATH:$HOME/.local/bin" ;;
  esac
fi

AI_CLI_UPDATE_SCRIPT="${AI_CLI_UPDATE_SCRIPT:-/mnt/c/git/harness-auto-update/harness-auto-update.sh}"
if [ "${AI_CLI_UPDATE_DISABLE:-0}" != "1" ] && [ -f "$AI_CLI_UPDATE_SCRIPT" ]; then
  bash "$AI_CLI_UPDATE_SCRIPT" --background >/dev/null 2>&1 || true
fi
