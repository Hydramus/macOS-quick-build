#!/bin/bash
# macOS Machine Setup Script — Orchestrator
# Delegates system-level work to setup-system.sh (root) and
# user-level work to setup-user.sh (console user).
# Usage: sudo ./macOSMachineSetup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ============================================
# Privilege and User Context
# ============================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} This script must be run with sudo"
    echo "Usage: sudo ./macOSMachineSetup.sh"
    exit 1
fi

if [ -n "$SUDO_USER" ]; then
    consoleuser="$SUDO_USER"
else
    consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
fi

if [[ -z "$consoleuser" || "$consoleuser" == "root" ]]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Could not determine console user"
    exit 1
fi

print_status "info" "Running as root, configuring user: $consoleuser"
echo ""

# Ensure all scripts are executable (survives zip/tarball extraction that drops execute bits)
chmod +x \
    "${SCRIPT_DIR}/setup-system.sh" \
    "${SCRIPT_DIR}/setup-user.sh" \
    "${SCRIPT_DIR}/autobrew.sh" \
    "${SCRIPT_DIR}/rosetta-2-install.sh" 2>/dev/null

HOMEBREW_PREFIX=$(detect_architecture)
SYSTEM_FAILED=0
USER_FAILED=0

# ============================================
# Phase 1: System-level setup (root)
# ============================================
echo "============================================"
echo "Phase 1: System Setup"
echo "============================================"
echo ""

if ! "${SCRIPT_DIR}/setup-system.sh" "$consoleuser"; then
    print_status "warning" "System phase completed with failures"
    SYSTEM_FAILED=1
fi
echo ""

# Ensure brew is in PATH for subsequent steps
export PATH="${HOMEBREW_PREFIX}/bin:$PATH"

if [[ $SYSTEM_FAILED -ne 0 ]] && ! command_exists brew; then
    print_status "error" "Homebrew unavailable after system phase — skipping user phase"
    echo ""
    echo "============================================"
    echo "OVERALL SETUP SUMMARY"
    echo "============================================"
    print_status "warning" "System phase had failures — review output above"
    print_status "warning" "User phase was skipped because Homebrew is not installed"
    exit 1
fi

# ============================================
# Phase 2: User-level setup (console user)
# Temporarily grant passwordless brew for cask installs, then revoke.
# ============================================
echo "============================================"
echo "Phase 2: User Setup"
echo "============================================"
echo ""

BREWFILE_PATH="${SCRIPT_DIR}/configfiles/Brewfile"
SUDOERS_TEMP="/etc/sudoers.d/brew_temp_$$"

if [ -f "$BREWFILE_PATH" ]; then
    echo "$consoleuser ALL=(root) NOPASSWD: ${HOMEBREW_PREFIX}/bin/brew" > "$SUDOERS_TEMP"
    chmod 0440 "$SUDOERS_TEMP"
    print_status "info" "Temporary sudo access granted for brew cask installs"
fi

if ! sudo -u "$consoleuser" -H "${SCRIPT_DIR}/setup-user.sh" "$BREWFILE_PATH"; then
    print_status "warning" "User phase completed with failures"
    USER_FAILED=1
fi

if [ -f "$SUDOERS_TEMP" ]; then
    rm -f "$SUDOERS_TEMP"
    print_status "success" "Temporary sudo access revoked"
fi
echo ""

# ============================================
# Overall Summary
# ============================================
echo "============================================"
echo "OVERALL SETUP SUMMARY"
echo "============================================"
echo ""

if [[ $SYSTEM_FAILED -eq 0 && $USER_FAILED -eq 0 ]]; then
    print_status "success" "All phases completed successfully!"
    exit 0
else
    [[ $SYSTEM_FAILED -ne 0 ]] && print_status "warning" "System phase had failures — review output above"
    [[ $USER_FAILED -ne 0 ]]   && print_status "warning" "User phase had failures — review output above"
    exit 1
fi
