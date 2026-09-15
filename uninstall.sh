#!/usr/bin/env bash
# =============================================================================
# uninstall.sh - Remove Cloud Remote Linux Synchronizer from the current user account
# Reverses the effects of install.sh
# =============================================================================
set -euo pipefail

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
# Paths (must match install.sh exactly)
# ---------------------------------------------------------------------------
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
CONFIG_DIR="${HOME}/.config/rclone-remote-syncer"
OLD_CONFIG_DIR="${HOME}/.config/onedrive-sync"

# ---------------------------------------------------------------------------
# Stop and disable systemd timer and service
# ---------------------------------------------------------------------------
header "==> Stopping and disabling systemd units"

for unit in rclone-remote-syncer.timer rclone-remote-syncer.service onedrive-sync.timer onedrive-sync.service; do
    if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
        systemctl --user stop "$unit"
        success "Stopped $unit"
    else
        info "$unit is not running — skipping stop."
    fi

    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
        systemctl --user disable "$unit"
        success "Disabled $unit"
    else
        info "$unit is not enabled — skipping disable."
    fi
done

# ---------------------------------------------------------------------------
# Remove systemd unit files
# ---------------------------------------------------------------------------
header "==> Removing systemd unit files"

for unit_file in "$SYSTEMD_DIR/rclone-remote-syncer.service" "$SYSTEMD_DIR/rclone-remote-syncer.timer" "$SYSTEMD_DIR/onedrive-sync.service" "$SYSTEMD_DIR/onedrive-sync.timer"; do
    if [[ -f "$unit_file" ]]; then
        rm -f "$unit_file"
        success "Removed $unit_file"
    else
        info "$unit_file not found — skipping."
    fi
done

systemctl --user daemon-reload
success "Daemon reloaded."

# ---------------------------------------------------------------------------
# Remove scripts from BIN_DIR
# ---------------------------------------------------------------------------
header "==> Removing scripts from $BIN_DIR"

for script in rclone-remote-syncer.sh rclone-remote-syncer-resync.sh onedrive-sync.sh onedrive-sync-resync.sh; do
    target="$BIN_DIR/$script"
    if [[ -f "$target" ]]; then
        rm -f "$target"
        success "Removed $target"
    else
        info "$target not found — skipping."
    fi
done

# ---------------------------------------------------------------------------
# Remove shell aliases from .bashrc and .zshrc
# ---------------------------------------------------------------------------
header "==> Removing shell aliases"

remove_aliases_from_rc() {
    local rc_file="$1"
    if [[ ! -f "$rc_file" ]]; then
        info "$rc_file not found — skipping."
        return
    fi

    sed -i '/alias sync-onedrive=/d' "$rc_file"
    sed -i '/alias sync-remote=/d' "$rc_file"
    sed -i '/alias sync-onedrive-resync=/d' "$rc_file"
    sed -i '/alias sync-remote-resync=/d' "$rc_file"
    sed -i '/# OneDrive sync aliases (added by install.sh)/d' "$rc_file"
    sed -i '/# Cloud Remote sync aliases (added by install.sh)/d' "$rc_file"
    sed -i '/# Added by onedrive-sync install.sh/d' "$rc_file"
    sed -i '/# Added by rclone-remote-syncer install.sh/d' "$rc_file"
    sed -i '/export PATH="\$HOME\/.local\/bin:\$PATH"/d' "$rc_file"
    success "Cleaned aliases and PATH entry from $rc_file"
}

for RC in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    remove_aliases_from_rc "$RC"
done

# ---------------------------------------------------------------------------
# Optionally remove config directory
# ---------------------------------------------------------------------------
header "==> Config directory"

if [[ -d "$OLD_CONFIG_DIR" ]]; then
    echo -e "${YELLOW}The old config directory exists: ${BOLD}$OLD_CONFIG_DIR${RESET}"
    read -r -p "Remove $OLD_CONFIG_DIR and all its contents? [y/N] " answer_old
    case "$answer_old" in
        [yY]|[yY][eE][sS])
            rm -rf "$OLD_CONFIG_DIR"
            success "Removed $OLD_CONFIG_DIR"
            ;;
        *)
            info "Keeping $OLD_CONFIG_DIR — remove it manually if desired."
            ;;
    esac
fi

if [[ -d "$CONFIG_DIR" ]]; then
    echo -e "${YELLOW}The config directory exists: ${BOLD}$CONFIG_DIR${RESET}"
    echo -e "${YELLOW}It may contain your personal config.env and sync logs.${RESET}"
    echo ""
    read -r -p "Remove $CONFIG_DIR and all its contents? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            rm -rf "$CONFIG_DIR"
            success "Removed $CONFIG_DIR"
            ;;
        *)
            info "Keeping $CONFIG_DIR — remove it manually if desired."
            ;;
    esac
else
    info "$CONFIG_DIR not found — nothing to remove."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}============================================================${RESET}"
echo -e "${BOLD}${GREEN}  Cloud Remote Linux Synchronizer uninstalled successfully!${RESET}"
echo -e "${BOLD}${GREEN}============================================================${RESET}"
echo ""
echo -e "${BOLD}Reload your shell to deactivate aliases:${RESET}"
echo -e "  ${CYAN}source ~/.bashrc${RESET}  (or ~/.zshrc)"
echo ""
