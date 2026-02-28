#!/usr/bin/env bash
# install.sh — Gulf Loop plugin installer
#
# Usage:
#   ./install.sh              Install or update
#   ./install.sh --uninstall  Remove completely

set -euo pipefail

PLUGIN_NAME="gulf-loop"
INSTALL_DIR="${HOME}/.claude/plugins/${PLUGIN_NAME}"
COMMANDS_DIR="${HOME}/.claude/commands"
SETTINGS_FILE="${HOME}/.claude/settings.json"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP_HOOK_PATH="${INSTALL_DIR}/hooks/stop-hook.sh"

# ── Colors ────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; }
step() { echo -e "\n$*"; }

# ── Dependency check ──────────────────────────────────────────────
check_deps() {
  local missing=()
  command -v jq  &>/dev/null || missing+=("jq")
  command -v claude &>/dev/null || missing+=("claude")

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    echo "  Install jq:     brew install jq"
    echo "  Install claude: https://claude.ai/download"
    exit 1
  fi
}

# ── Uninstall ─────────────────────────────────────────────────────
uninstall() {
  step "Uninstalling ${PLUGIN_NAME}..."

  # Remove plugin files
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed $INSTALL_DIR"
  else
    warn "Plugin directory not found (already removed?)"
  fi

  # Remove command files
  local removed=0
  for f in "${COMMANDS_DIR}/gulf-loop:"*.md; do
    [[ -f "$f" ]] || continue
    rm -f "$f"
    removed=$((removed + 1))
  done
  [[ $removed -gt 0 ]] && ok "Removed $removed command file(s) from $COMMANDS_DIR"

  # Remove Stop hook from settings.json
  if [[ -f "$SETTINGS_FILE" ]]; then
    local tmp
    tmp=$(mktemp)
    # Remove the gulf-loop stop-hook entry from the Stop hooks array
    jq 'if .hooks.Stop then
      .hooks.Stop[0].hooks = [
        .hooks.Stop[0].hooks[]
        | select(.command | test("gulf-loop") | not)
      ]
    else . end' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    ok "Removed Stop hook from $SETTINGS_FILE"
  fi

  echo ""
  ok "Gulf Loop uninstalled."
}

# ── Install plugin files ──────────────────────────────────────────
install_files() {
  step "Copying plugin files..."

  mkdir -p "$INSTALL_DIR"
  cp -r "${SOURCE_DIR}/hooks"          "${INSTALL_DIR}/"
  cp -r "${SOURCE_DIR}/scripts"        "${INSTALL_DIR}/"
  cp -r "${SOURCE_DIR}/prompts"        "${INSTALL_DIR}/"
  cp -r "${SOURCE_DIR}/.claude-plugin" "${INSTALL_DIR}/"

  chmod +x "${INSTALL_DIR}/hooks/stop-hook.sh"
  chmod +x "${INSTALL_DIR}/scripts/"*.sh

  ok "Plugin files → $INSTALL_DIR"
}

# ── Install command files ─────────────────────────────────────────
install_commands() {
  step "Installing slash commands..."

  mkdir -p "$COMMANDS_DIR"

  # Each command: copy source file and substitute ${CLAUDE_PLUGIN_ROOT} with install path.
  # commands/*.md is the single source of truth for descriptions and argument-hints.
  local cmd
  for cmd in start start-with-judge start-autonomous start-parallel align cancel status resume; do
    sed "s|\${CLAUDE_PLUGIN_ROOT}|${INSTALL_DIR}|g" \
      "${SOURCE_DIR}/commands/${cmd}.md" \
      > "${COMMANDS_DIR}/gulf-loop:${cmd}.md"
  done

  ok "8 slash commands → $COMMANDS_DIR"
  echo "    /gulf-loop:align  ← run before start (surfaces gaps)"
  echo "    /gulf-loop:start"
  echo "    /gulf-loop:start-with-judge"
  echo "    /gulf-loop:start-autonomous"
  echo "    /gulf-loop:start-parallel"
  echo "    /gulf-loop:cancel"
  echo "    /gulf-loop:status"
  echo "    /gulf-loop:resume"
}

# ── Register Stop hook in settings.json ───────────────────────────
install_hook() {
  step "Registering Stop hook..."

  # Create settings.json if it doesn't exist
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
    ok "Created $SETTINGS_FILE"
  fi

  # Check if gulf-loop hook is already registered
  if jq -e '.hooks.Stop[0].hooks[]? | select(.command | test("gulf-loop"))' \
       "$SETTINGS_FILE" &>/dev/null; then
    warn "Stop hook already registered — updating path"
    local tmp
    tmp=$(mktemp)
    jq --arg path "$STOP_HOOK_PATH" \
      '(.hooks.Stop[0].hooks[] | select(.command | test("gulf-loop")) | .command) = $path' \
      "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    ok "Stop hook path updated"
    return
  fi

  # Add gulf-loop Stop hook
  local tmp
  tmp=$(mktemp)
  local new_hook
  new_hook=$(jq -n --arg cmd "$STOP_HOOK_PATH" \
    '{"type":"command","command":$cmd,"timeout":30}')

  # Build the updated settings using jq
  jq --argjson hook "$new_hook" '
    if .hooks == null then .hooks = {} else . end
    | if .hooks.Stop == null then
        .hooks.Stop = [{"matcher": "", "hooks": [$hook]}]
      elif (.hooks.Stop | length) == 0 then
        .hooks.Stop = [{"matcher": "", "hooks": [$hook]}]
      elif .hooks.Stop[0].hooks == null then
        .hooks.Stop[0].hooks = [$hook]
      else
        .hooks.Stop[0].hooks += [$hook]
      end
  ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

  ok "Stop hook registered in $SETTINGS_FILE"
}

# ── Verify installation ───────────────────────────────────────────
verify() {
  step "Verifying..."

  local ok_count=0 fail_count=0

  _check() {
    if [[ -e "$1" ]]; then
      ok_count=$((ok_count + 1))
    else
      err "Missing: $1"
      fail_count=$((fail_count + 1))
    fi
  }

  _check "${INSTALL_DIR}/hooks/stop-hook.sh"
  _check "${INSTALL_DIR}/scripts/setup.sh"
  _check "${INSTALL_DIR}/scripts/run-align.sh"
  _check "${INSTALL_DIR}/prompts/framework.md"
  _check "${COMMANDS_DIR}/gulf-loop:align.md"
  _check "${COMMANDS_DIR}/gulf-loop:start.md"
  _check "${COMMANDS_DIR}/gulf-loop:start-with-judge.md"
  _check "${COMMANDS_DIR}/gulf-loop:start-autonomous.md"
  _check "${COMMANDS_DIR}/gulf-loop:start-parallel.md"

  if [[ $fail_count -gt 0 ]]; then
    err "$fail_count check(s) failed."
    exit 1
  fi

  ok "All checks passed ($ok_count files)"
}

# ── Main ──────────────────────────────────────────────────────────
main() {
  echo "Gulf Loop — installer"
  echo "━━━━━━━━━━━━━━━━━━━━━"

  if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall
    exit 0
  fi

  check_deps
  install_files
  install_commands
  install_hook
  verify

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━"
  ok "Gulf Loop installed. Restart Claude Code to activate."
  echo ""
  echo "  Quick start:"
  echo "    /gulf-loop:start \"your task\" --max-iterations 30"
  echo ""
  echo "  Judge mode (requires RUBRIC.md):"
  echo "    /gulf-loop:start-with-judge \"your task\" --max-iterations 30"
  echo ""
  echo "  Uninstall:"
  echo "    ./install.sh --uninstall"
}

main "$@"
