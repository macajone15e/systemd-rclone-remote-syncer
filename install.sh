#!/usr/bin/env bash
# =============================================================================
# install.sh - Deploy OneDrive Linux Synchronizer to the current user account
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
CONFIG_DIR="${HOME}/.config/onedrive-sync"

header "==> Creating directories"
mkdir -p "$BIN_DIR" "$SYSTEMD_DIR" "$CONFIG_DIR"
success "Directories ready: $BIN_DIR, $SYSTEMD_DIR, $CONFIG_DIR"

# ---------------------------------------------------------------------------
# Install scripts
# ---------------------------------------------------------------------------
header "==> Installing scripts to $BIN_DIR"
install -m 755 "$SCRIPT_DIR/onedrive-sync.sh" "$BIN_DIR/onedrive-sync.sh"
success "Scripts installed."

# ---------------------------------------------------------------------------
# Install systemd units
# ---------------------------------------------------------------------------
header "==> Installing systemd units to $SYSTEMD_DIR"
install -m 644 "$SCRIPT_DIR/systemd/onedrive-sync.service" "$SYSTEMD_DIR/onedrive-sync.service"
install -m 644 "$SCRIPT_DIR/systemd/onedrive-sync.timer"   "$SYSTEMD_DIR/onedrive-sync.timer"
systemctl --user daemon-reload
success "Systemd units installed and daemon reloaded."

# ---------------------------------------------------------------------------
# Config file (never overwrite if it already exists)
# ---------------------------------------------------------------------------
CONFIG_FILE="$CONFIG_DIR/config.env"
header "==> Config file"
if [[ -f "$CONFIG_FILE" ]]; then
    warn "config.env already exists at $CONFIG_FILE — skipping (your settings are preserved)."
else
    install -m 600 "$SCRIPT_DIR/config.env.template" "$CONFIG_FILE"
    success "config.env installed to $CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Shell aliases
# ---------------------------------------------------------------------------
header "==> Adding shell aliases"

ALIAS_SYNC='alias sync-onedrive="onedrive-sync.sh"'

add_alias_to_rc() {
    local rc_file="$1"
    local alias_line="$2"
    local alias_name="${alias_line%%=*}"          # e.g. "alias sync-onedrive"
    alias_name="${alias_name#alias }"             # e.g. "sync-onedrive"

    if [[ ! -f "$rc_file" ]]; then
        return
    fi

    if grep -q "alias ${alias_name}=" "$rc_file" 2>/dev/null; then
        warn "Alias '${alias_name}' already exists in $rc_file — skipping."
    else
        echo "" >> "$rc_file"
        echo "# OneDrive sync alias (added by install.sh)" >> "$rc_file"
        echo "$alias_line" >> "$rc_file"
        success "Added '$alias_name' alias to $rc_file"
    fi
}

for RC in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    add_alias_to_rc "$RC" "$ALIAS_SYNC"
done

# Also ensure BIN_DIR is in PATH for shells that don't include it automatically
for RC in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [[ -f "$RC" ]] && ! grep -q "${BIN_DIR}" "$RC" 2>/dev/null; then
        echo "" >> "$RC"
        echo "# Added by onedrive-sync install.sh" >> "$RC"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
        success "Added $BIN_DIR to PATH in $RC"
    fi
done

# ---------------------------------------------------------------------------
# Success message
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}============================================================${RESET}"
echo -e "${BOLD}${GREEN}  OneDrive Linux Synchronizer installed successfully!${RESET}"
echo -e "${BOLD}${GREEN}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo ""
echo -e "  ${CYAN}1.${RESET} Configure your rclone OneDrive remote (if not done yet):"
echo -e "       ${YELLOW}rclone config${RESET}"
echo ""
echo -e "  ${CYAN}2.${RESET} Edit the sync configuration file:"
echo -e "       ${YELLOW}${CONFIG_FILE}${RESET}"
echo -e "     Set your SYNC_1, SYNC_2 … pairs (local_path:remote:remote_path)."
echo ""
echo -e "  ${CYAN}3.${RESET} Run the initial baseline sync (required before scheduling):"
echo -e "       ${YELLOW}${BIN_DIR}/onedrive-sync.sh --resync${RESET}"
echo -e "     Or, after reloading your shell:"
echo -e "       ${YELLOW}sync-onedrive --resync${RESET}"
echo ""
echo -e "  ${CYAN}4.${RESET} Enable and start the automatic timer:"
echo -e "       ${YELLOW}systemctl --user enable --now onedrive-sync.timer${RESET}"
echo ""
echo -e "  ${CYAN}5.${RESET} Check timer status:"
echo -e "       ${YELLOW}systemctl --user status onedrive-sync.timer${RESET}"
echo ""
echo -e "  ${CYAN}6.${RESET} Reload your shell to activate the alias:"
echo -e "       ${YELLOW}source ~/.bashrc${RESET}  (or ~/.zshrc)"
echo ""
