#!/usr/bin/env bash
# =============================================================================
# onedrive-sync-resync.sh - One-time baseline initialisation for rclone bisync
#
# Run this ONCE after:
#   - Configuring the rclone remote for the first time, OR
#   - Adding a new SYNC_* folder pair to the config.
#
# It is identical to onedrive-sync.sh but passes --resync to rclone bisync,
# which initialises the local state files that bisync needs for subsequent
# incremental syncs. Do NOT run it repeatedly; use onedrive-sync.sh for that.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_FILE="${HOME}/.config/onedrive-sync/config.env"
LOCK_FILE="/tmp/onedrive-sync.lock"
SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$ts] [$level] $msg"
    echo "$line"
    if [[ -n "${RCLONE_LOG_FILE:-}" ]]; then
        echo "$line" >> "$RCLONE_LOG_FILE"
    fi
}

log_info()  { log "INFO " "$@"; }
log_warn()  { log "WARN " "$@"; }
log_error() { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Exclusive lock - prevents running alongside normal onedrive-sync.sh
# ---------------------------------------------------------------------------
exec 9> "$LOCK_FILE"
if ! flock -n 9; then
    echo "[$SCRIPT_NAME] Another sync instance is already running (lock: $LOCK_FILE). Exiting." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[$SCRIPT_NAME] ERROR: config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Ensure log directory exists when a log file is configured
if [[ -n "${RCLONE_LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "$RCLONE_LOG_FILE")"
fi

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! command -v rclone &>/dev/null; then
    log_error "rclone not found in PATH. Install rclone and try again."
    exit 1
fi

SYNC_MODE="${SYNC_MODE:-bisync}"
DRY_RUN="${DRY_RUN:-false}"
RCLONE_LOG_LEVEL="${RCLONE_LOG_LEVEL:-INFO}"
RCLONE_EXTRA_FLAGS="${RCLONE_EXTRA_FLAGS:-}"

# ---------------------------------------------------------------------------
# Build base rclone flags
# ---------------------------------------------------------------------------
BASE_FLAGS=("--log-level" "$RCLONE_LOG_LEVEL")

if [[ -n "${RCLONE_LOG_FILE:-}" ]]; then
    BASE_FLAGS+=("--log-file" "$RCLONE_LOG_FILE")
fi

if [[ "$DRY_RUN" == "true" ]]; then
    BASE_FLAGS+=("--dry-run")
    log_warn "DRY_RUN=true - no changes will be made."
fi

# Append bisync-specific conflict resolution + --resync for baseline init
BISYNC_FLAGS=()
if [[ "$SYNC_MODE" == "bisync" ]]; then
    BISYNC_FLAGS+=("--conflict-resolve" "newer")
    BISYNC_FLAGS+=("--resync")
fi

# Split extra flags string into array safely
EXTRA_FLAGS=()
if [[ -n "$RCLONE_EXTRA_FLAGS" ]]; then
    eval "EXTRA_FLAGS=($RCLONE_EXTRA_FLAGS)"
fi

# ---------------------------------------------------------------------------
# Collect SYNC_* pairs
# ---------------------------------------------------------------------------
declare -a SYNC_PAIRS=()
while IFS= read -r varname; do
    [[ "$varname" =~ ^SYNC_[0-9]+$ ]] || continue
    value="${!varname}"
    [[ -n "$value" ]] && SYNC_PAIRS+=("$value")
done < <(compgen -v)

if [[ "${#SYNC_PAIRS[@]}" -eq 0 ]]; then
    log_warn "No SYNC_* variables found in $CONFIG_FILE. Nothing to resync."
    exit 0
fi

# ---------------------------------------------------------------------------
# Main resync loop
# ---------------------------------------------------------------------------
OVERALL_START="$(date '+%Y-%m-%d %H:%M:%S')"
log_info "========================================================"
log_info "Starting $SCRIPT_NAME  |  mode=$SYNC_MODE (--resync)  |  pairs=${#SYNC_PAIRS[@]}"
log_info "Started at: $OVERALL_START"
log_info "========================================================"

EXIT_CODE=0
PAIR_INDEX=0

for pair in "${SYNC_PAIRS[@]}"; do
    PAIR_INDEX=$(( PAIR_INDEX + 1 ))

    # Parse "local_path:remote:remote_path"
    IFS=':' read -r local_path remote_name remote_path <<< "$pair"

    if [[ -z "$local_path" || -z "$remote_name" || -z "$remote_path" ]]; then
        log_error "Pair $PAIR_INDEX malformed (expected 'local:remote:path'): '$pair' - skipping."
        EXIT_CODE=1
        continue
    fi

    remote_target="${remote_name}:${remote_path}"

    log_info "--------------------------------------------------------"
    log_info "Pair $PAIR_INDEX: $local_path  <->  $remote_target"
    log_info "--------------------------------------------------------"

    # Verify local directory exists
    if [[ ! -d "$local_path" ]]; then
        log_warn "Local path does not exist, skipping: $local_path"
        EXIT_CODE=1
        continue
    fi

    # Build rclone command (includes --resync via BISYNC_FLAGS)
    RCLONE_CMD=(rclone "$SYNC_MODE" "${BASE_FLAGS[@]}" "${EXTRA_FLAGS[@]}" "${BISYNC_FLAGS[@]}" "$local_path" "$remote_target")

    log_info "Running: ${RCLONE_CMD[*]}"

    PAIR_START="$(date +%s)"
    if "${RCLONE_CMD[@]}"; then
        PAIR_ELAPSED=$(( $(date +%s) - PAIR_START ))
        log_info "Pair $PAIR_INDEX completed successfully in ${PAIR_ELAPSED}s."
    else
        rc=$?
        PAIR_ELAPSED=$(( $(date +%s) - PAIR_START ))
        log_error "Pair $PAIR_INDEX FAILED (rclone exit code $rc) after ${PAIR_ELAPSED}s."
        EXIT_CODE=1
    fi
done

OVERALL_END="$(date '+%Y-%m-%d %H:%M:%S')"
log_info "========================================================"
log_info "Finished $SCRIPT_NAME"
log_info "Started:  $OVERALL_START"
log_info "Finished: $OVERALL_END"
if [[ "$EXIT_CODE" -eq 0 ]]; then
    log_info "Result: ALL PAIRS SUCCEEDED"
else
    log_error "Result: ONE OR MORE PAIRS FAILED (see above)"
fi
log_info "========================================================"

exit "$EXIT_CODE"
