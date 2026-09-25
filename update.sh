#!/usr/bin/env bash
# =============================================================================
# update.sh - Update Cloud Remote Linux Synchronizer
# =============================================================================
set -euo pipefail

REPO="macajone15e/systemd-rclone-remote-syncer"
BIN_DIR="${HOME}/.local/bin"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
CONFIG_DIR="${HOME}/.config/rclone-remote-syncer"
CONFIG_FILE="$CONFIG_DIR/config.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; }

TARGET_TAG="${1:-latest}"

if [[ "$TARGET_TAG" == "latest" ]]; then
    info "Fetching latest release tag..."
    LATEST_JSON=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest")
    TARGET_TAG=$(echo "$LATEST_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    if [[ -z "$TARGET_TAG" ]]; then
        error "Could not determine latest release tag. Response: $LATEST_JSON"
        exit 1
    fi
    success "Latest tag is $TARGET_TAG"
else
    info "Verifying tag $TARGET_TAG..."
    if ! curl -sLf -o /dev/null "https://raw.githubusercontent.com/$REPO/$TARGET_TAG/rclone-remote-syncer.sh"; then
        error "Release/Tag $TARGET_TAG not found or not accessible."
        exit 1
    fi
    success "Tag $TARGET_TAG verified."
fi

REPO_URL="https://raw.githubusercontent.com/$REPO/$TARGET_TAG"

echo -e "\n${BOLD}${CYAN}==> Backing up config${RESET}"
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}_backup_${TARGET_TAG}"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    success "Backed up config to $BACKUP_FILE"
else
    info "No config file found at $CONFIG_FILE to backup."
fi

echo -e "\n${BOLD}${CYAN}==> Updating scripts and systemd units${RESET}"
fetch_file() {
    local src="$1"
    local dest="$2"
    local mode="$3"
    info "Updating $src..."
    curl -sfL "$REPO_URL/$src" -o "$dest" || {
        error "Failed to download $src"
        exit 1
    }
    chmod "$mode" "$dest"
}

fetch_file "rclone-remote-syncer.sh" "$BIN_DIR/rclone-remote-syncer.sh" 755
fetch_file "systemd/rclone-remote-syncer.service" "$SYSTEMD_DIR/rclone-remote-syncer.service" 644
fetch_file "systemd/rclone-remote-syncer.timer" "$SYSTEMD_DIR/rclone-remote-syncer.timer" 644

systemctl --user daemon-reload
systemctl --user enable --now rclone-remote-syncer.timer
success "Systemd units reloaded and timer started."

echo ""
echo -e "${BOLD}${GREEN}============================================================${RESET}"
echo -e "${BOLD}${GREEN}  Updated successfully to $TARGET_TAG!${RESET}"
echo -e "${BOLD}${GREEN}============================================================${RESET}"
