#!/bin/bash
# lib/common.sh — Shared utilities for macOS-quick-build scripts.
# Source this file at the top of every script:
#   source "${SCRIPT_DIR}/lib/common.sh"

# ============================================
# Color constants
# ============================================
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ============================================
# Failure tracking
# Accumulates names of failed steps so print_summary can report them.
# ============================================
FAILED_STEPS=()

# ============================================
# Progress log
# Every print_status/track_failure call is also appended here so a run
# started any way (direct sudo, MDM enrollment.sh, etc.) leaves a durable
# record. LOG_FILE can be pre-set/exported by the caller; otherwise this
# default is used and shared across all scripts in this repo.
# ============================================
LOG_FILE="${LOG_FILE:-/var/log/macos_quick_build.log}"

_ensure_log_file() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    chmod 666 "$LOG_FILE" 2>/dev/null
}
_ensure_log_file

log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE" 2>/dev/null
}

# ============================================
# print_status <level> <message>
# Levels: info | success | warning | error
# ============================================
print_status() {
    local level="$1"
    local message="$2"
    case "$level" in
        info)    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}    $message" ;;
        success) echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $message" ;;
        warning) echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $message" ;;
        error)   echo -e "${COLOR_RED}[ERROR]${COLOR_RESET}   $message" ;;
        *)       echo -e "$message" ;;
    esac
    # macOS ships Bash 3.2 (no ${var^^} uppercase expansion), so use tr instead.
    local level_upper
    level_upper=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    log_to_file "[${level_upper}] $message"
}

# ============================================
# track_failure <step_name> <exit_code> <detail>
# Records a failed step; prints the detail message.
# ============================================
track_failure() {
    local step="$1"
    local code="$2"
    local detail="$3"
    FAILED_STEPS+=("$step")
    print_status "error" "Step '$step' failed (exit $code): $detail"
}

# ============================================
# run_with_error_capture <step_name> <command_string>
# Runs command_string via eval; on failure calls track_failure.
# ============================================
run_with_error_capture() {
    local step="$1"
    local cmd="$2"
    print_status "info" "Running: $step"
    if eval "$cmd"; then
        print_status "success" "$step completed"
    else
        local code=$?
        track_failure "$step" "$code" "Command: $cmd"
    fi
}

# ============================================
# detect_architecture
# Prints the Homebrew prefix for the current CPU.
# ============================================
detect_architecture() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "/opt/homebrew"
    else
        echo "/usr/local"
    fi
}

# ============================================
# macos_major_version
# Prints the major macOS version number (e.g. 15 for 15.4, 10 for 10.15).
# Prints 0 if sw_vers is unavailable (i.e. not running on macOS).
# ============================================
macos_major_version() {
    if [[ -x /usr/bin/sw_vers ]]; then
        /usr/bin/sw_vers -productVersion | cut -d. -f1
    else
        echo "0"
    fi
}

# ============================================
# command_exists <command>
# Returns 0 if command is available in PATH, 1 otherwise.
# ============================================
command_exists() {
    command -v "$1" &>/dev/null
}

# ============================================
# ensure_path_entry <path_dir> <rc_file>
# Appends an export PATH line to rc_file if it is not already present.
# ============================================
ensure_path_entry() {
    local path_dir="$1"
    local rc_file="$2"
    local entry="export PATH=\"${path_dir}:\$PATH\""

    if grep -qF "$path_dir" "$rc_file" 2>/dev/null; then
        print_status "info" "$path_dir already in $rc_file — skipping"
    else
        echo "" >> "$rc_file"
        echo "# Added by macOS-quick-build" >> "$rc_file"
        echo "$entry" >> "$rc_file"
        print_status "success" "Added $path_dir to $rc_file"
    fi
}

# ============================================
# print_summary <title>
# Prints a pass/fail summary using FAILED_STEPS[].
# ============================================
print_summary() {
    local title="${1:-Setup Summary}"
    echo ""
    echo "============================================"
    echo "$title"
    echo "============================================"
    log_to_file "===== $title ====="
    if [[ ${#FAILED_STEPS[@]} -eq 0 ]]; then
        print_status "success" "All steps completed successfully"
    else
        print_status "warning" "${#FAILED_STEPS[@]} step(s) failed:"
        for step in "${FAILED_STEPS[@]}"; do
            echo -e "  ${COLOR_RED}•${COLOR_RESET} $step"
            log_to_file "  - $step"
        done
    fi
    echo ""
}
