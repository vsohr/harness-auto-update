#!/usr/bin/env bash
# Update AI CLIs used by local harness shells.

set -u

INTERVAL_SECONDS="${AI_CLI_UPDATE_INTERVAL_SECONDS:-86400}"
CACHE_DIR="${AI_CLI_UPDATE_CACHE_DIR:-$HOME/.cache/harness-auto-update}"
STAMP_FILE="${AI_CLI_UPDATE_STAMP_FILE:-$CACHE_DIR/last-run}"
LOG_FILE="${AI_CLI_UPDATE_LOG_FILE:-$CACHE_DIR/update.log}"
LOCK_DIR="${AI_CLI_UPDATE_LOCK_DIR:-$CACHE_DIR/update.lock}"
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HOME/.hermes/hermes-agent}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
  cat <<'EOF'
Usage: harness-auto-update.sh [--background|--force|--run|--status]

Updates the WSL-side AI CLIs used by local harness shells:
  - @anthropic-ai/claude-code via the nvm-managed npm
  - @openai/codex via the nvm-managed npm
  - Hermes via a clean git fast-forward of ~/.hermes/hermes-agent

Environment:
  AI_CLI_UPDATE_DISABLE=1              disable automatic runs
  AI_CLI_UPDATE_INTERVAL_SECONDS=86400 run interval for automatic mode
  HERMES_AGENT_DIR=...                 override Hermes checkout path
EOF
}

mkdir_cache_dir() {
  mkdir -p "$CACHE_DIR"
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
  fi
}

seconds_since_stamp() {
  if [ ! -f "$STAMP_FILE" ]; then
    echo 999999999
    return
  fi

  local now
  local stamp
  now="$(date +%s)"
  stamp="$(cat "$STAMP_FILE" 2>/dev/null || echo 0)"
  case "$stamp" in
    ''|*[!0-9]*) echo 999999999 ;;
    *) echo $((now - stamp)) ;;
  esac
}

should_run() {
  if [ "${AI_CLI_UPDATE_DISABLE:-0}" = "1" ]; then
    log "AI_CLI_UPDATE_DISABLE=1; skipping updates"
    return 1
  fi

  [ "$(seconds_since_stamp)" -ge "$INTERVAL_SECONDS" ]
}

with_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "another AI CLI update is already running"
    return 0
  fi

  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  "$@"
}

update_node_clis() {
  load_nvm

  local npm_path
  npm_path="$(command -v npm 2>/dev/null || true)"
  if [ -z "$npm_path" ]; then
    log "npm not found in WSL; skipping Claude/Codex updates"
    return 0
  fi

  case "$npm_path" in
    /mnt/*)
      log "npm resolves to Windows path ($npm_path); skipping WSL CLI updates"
      return 0
      ;;
  esac

  log "updating Claude Code and Codex with $npm_path"
  if ! npm install -g @anthropic-ai/claude-code@latest @openai/codex@latest; then
    log "Claude/Codex npm update failed"
    return 1
  fi

  if command -v claude >/dev/null 2>&1; then
    log "claude version: $(claude --version 2>/dev/null || true)"
  fi
  if command -v codex >/dev/null 2>&1; then
    log "codex version: $(codex --version 2>/dev/null || true)"
  fi
}

hermes_worktree_dirty() {
  [ -n "$(git -C "$HERMES_AGENT_DIR" status --porcelain 2>/dev/null)" ]
}

sync_hermes_dependencies() {
  local python_path="$HERMES_AGENT_DIR/venv/bin/python"

  if [ ! -x "$python_path" ]; then
    log "Hermes venv not found; run $HERMES_AGENT_DIR/setup-hermes.sh manually"
    return 0
  fi

  if command -v uv >/dev/null 2>&1 && [ -f "$HERMES_AGENT_DIR/uv.lock" ]; then
    log "syncing Hermes dependencies with uv.lock"
    (
      cd "$HERMES_AGENT_DIR" &&
        UV_PROJECT_ENVIRONMENT="$HERMES_AGENT_DIR/venv" uv sync --all-extras --locked
    ) || (
      cd "$HERMES_AGENT_DIR" &&
        uv pip install --python "$python_path" -e ".[all]"
    ) || (
      cd "$HERMES_AGENT_DIR" &&
        uv pip install --python "$python_path" -e "."
    )
  else
    log "syncing Hermes dependencies with pip"
    (
      cd "$HERMES_AGENT_DIR" &&
        "$python_path" -m pip install -e ".[all]"
    ) || (
      cd "$HERMES_AGENT_DIR" &&
        "$python_path" -m pip install -e "."
    )
  fi

  if [ -x "$HERMES_AGENT_DIR/venv/bin/hermes" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$HERMES_AGENT_DIR/venv/bin/hermes" "$HOME/.local/bin/hermes"
  fi
}

update_hermes() {
  if [ ! -d "$HERMES_AGENT_DIR/.git" ]; then
    log "Hermes checkout not found at $HERMES_AGENT_DIR; skipping"
    return 0
  fi

  if hermes_worktree_dirty; then
    log "Hermes checkout has local changes; skipping git update"
    git -C "$HERMES_AGENT_DIR" status --short || true
    return 0
  fi

  local before
  local after
  before="$(git -C "$HERMES_AGENT_DIR" rev-parse HEAD)"

  log "updating Hermes in $HERMES_AGENT_DIR"
  if ! git -C "$HERMES_AGENT_DIR" pull --ff-only --recurse-submodules; then
    log "Hermes git pull failed"
    return 1
  fi
  if ! git -C "$HERMES_AGENT_DIR" submodule update --init --recursive; then
    log "Hermes submodule update failed"
    return 1
  fi

  after="$(git -C "$HERMES_AGENT_DIR" rev-parse HEAD)"
  if [ "$before" != "$after" ]; then
    log "Hermes changed from $before to $after"
    sync_hermes_dependencies
  else
    log "Hermes already up to date"
  fi

  if command -v hermes >/dev/null 2>&1; then
    log "hermes path: $(command -v hermes)"
  fi
}

run_updates() {
  mkdir_cache_dir
  local failed=0

  log "starting AI CLI update"
  update_node_clis || failed=1
  update_hermes || failed=1

  if [ "$failed" -eq 0 ]; then
    date +%s > "$STAMP_FILE"
    log "AI CLI update complete"
    return 0
  fi

  log "AI CLI update completed with errors"
  return 1
}

run_background() {
  mkdir_cache_dir
  if ! should_run; then
    exit 0
  fi

  nohup bash "$0" --run >>"$LOG_FILE" 2>&1 &
}

status() {
  mkdir_cache_dir
  printf 'log: %s\n' "$LOG_FILE"
  printf 'stamp: %s\n' "$STAMP_FILE"
  if [ -f "$STAMP_FILE" ]; then
    printf 'last run: %s seconds ago\n' "$(seconds_since_stamp)"
  else
    printf 'last run: never\n'
  fi
  if [ -f "$LOG_FILE" ]; then
    tail -n 40 "$LOG_FILE"
  fi
}

case "${1:---run-if-due}" in
  --background)
    run_background
    ;;
  --force)
    mkdir_cache_dir
    with_lock run_updates >>"$LOG_FILE" 2>&1
    ;;
  --run)
    mkdir_cache_dir
    with_lock run_updates
    ;;
  --run-if-due)
    mkdir_cache_dir
    if should_run; then
      with_lock run_updates >>"$LOG_FILE" 2>&1
    fi
    ;;
  --status)
    status
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
