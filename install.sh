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
  # Copy everything except install.sh itself, .git, README
  rsync -a --exclude='install.sh' \
            --exclude='.git' \
            --exclude='.gitignore' \
            --exclude='README.md' \
            --exclude='RUBRIC.example.md' \
            "${SOURCE_DIR}/" "${INSTALL_DIR}/"

  # Ensure scripts are executable
  chmod +x "${INSTALL_DIR}/hooks/stop-hook.sh"
  chmod +x "${INSTALL_DIR}/scripts/"*.sh

  ok "Plugin files → $INSTALL_DIR"
}

# ── Install command files ─────────────────────────────────────────
install_commands() {
  step "Installing slash commands..."

  mkdir -p "$COMMANDS_DIR"

  # Generate command files with the actual install path baked in
  _write_command "gulf-loop:start" \
    "Start a Gulf Loop — autonomous iterative development until the completion promise is output" \
    "PROMPT [--max-iterations N] [--completion-promise TEXT]" \
    "setup-loop.sh"

  _write_command "gulf-loop:start-with-judge" \
    "Start a Gulf Loop with LLM Judge — completes only when auto-checks pass AND Claude Opus approves" \
    "PROMPT [--max-iterations N] [--hitl-threshold N]" \
    "setup-judge.sh"

  _write_command "gulf-loop:start-autonomous" \
    "Start a fully autonomous Gulf Loop — no HITL, branch-based, auto-merges on completion" \
    "PROMPT [--max-iterations N] [--base-branch BRANCH] [--with-judge] [--hitl-threshold N]" \
    "setup-autonomous.sh"

  _write_command "gulf-loop:start-parallel" \
    "Set up N parallel autonomous Gulf Loops in separate git worktrees" \
    "PROMPT --workers N [--max-iterations N] [--base-branch BRANCH] [--with-judge]" \
    "setup-parallel.sh"

  _write_simple_command "gulf-loop:cancel"  "Cancel the active Gulf Loop"                              "cancel-loop.sh"
  _write_simple_command "gulf-loop:status"  "Show current Gulf Loop iteration status"                  "status-loop.sh"
  _write_simple_command "gulf-loop:resume"  "Resume a Gulf Loop paused by the HITL gate"              "resume-loop.sh"

  ok "7 slash commands → $COMMANDS_DIR"
  echo "    /gulf-loop:start"
  echo "    /gulf-loop:start-with-judge"
  echo "    /gulf-loop:start-autonomous"
  echo "    /gulf-loop:start-parallel"
  echo "    /gulf-loop:cancel"
  echo "    /gulf-loop:status"
  echo "    /gulf-loop:resume"
}

_write_command() {
  local name="$1" desc="$2" hint="$3" script="$4"
  local src_name="${name#gulf-loop:}"

  # Write frontmatter
  cat > "${COMMANDS_DIR}/${name}.md" <<EOF
---
description: "${desc}"
argument-hint: "${hint}"
allowed-tools: ["Bash(${INSTALL_DIR}/scripts/${script}:*)"]
hide-from-slash-command-tool: "true"
---

EOF

  # Append body from source command file (strip YAML frontmatter block)
  awk '/^---$/{c++;next} c>=2{print}' \
    "${SOURCE_DIR}/commands/${src_name}.md" \
    >> "${COMMANDS_DIR}/${name}.md" 2>/dev/null || true

  # Replace ${CLAUDE_PLUGIN_ROOT} references with actual install path
  local tmp
  tmp=$(mktemp)
  sed "s|\${CLAUDE_PLUGIN_ROOT}|${INSTALL_DIR}|g" "${COMMANDS_DIR}/${name}.md" > "$tmp" \
    && mv "$tmp" "${COMMANDS_DIR}/${name}.md"
}

_write_simple_command() {
  local name="$1" desc="$2" script="$3"

  cat > "${COMMANDS_DIR}/${name}.md" <<EOF
---
description: "${desc}"
allowed-tools: ["Bash(${INSTALL_DIR}/scripts/${script}:*)"]
hide-from-slash-command-tool: "true"
---

\`\`\`!
${INSTALL_DIR}/scripts/${script}
\`\`\`
EOF
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
  _check "${INSTALL_DIR}/scripts/setup-loop.sh"
  _check "${INSTALL_DIR}/scripts/setup-judge.sh"
  _check "${INSTALL_DIR}/scripts/setup-autonomous.sh"
  _check "${INSTALL_DIR}/scripts/setup-parallel.sh"
  _check "${INSTALL_DIR}/prompts/framework.md"
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
