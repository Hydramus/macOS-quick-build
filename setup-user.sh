#!/bin/bash
# User-level setup phase — runs as the console user, no root needed inside.
# Called by macOSMachineSetup.sh via: sudo -u <user> -H ./setup-user.sh <brewfile_path>
# Covers: oh-my-zsh, PATH in .zshrc, brew bundle, dock configuration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BREWFILE_PATH="${1:-${SCRIPT_DIR}/configfiles/Brewfile}"
HOMEBREW_PREFIX=$(detect_architecture)

export PATH="${HOMEBREW_PREFIX}/bin:$PATH"

# ============================================
# oh-my-zsh
# ============================================
print_status "info" "Checking oh-my-zsh"
if [ -d "${HOME}/.oh-my-zsh" ]; then
    print_status "info" "oh-my-zsh already installed — skipping"
else
    run_with_error_capture "oh-my-zsh installation" \
        'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
fi
echo ""

# ============================================
# PATH in .zshrc
# ============================================
ZSHRC_PATH="${HOME}/.zshrc"
ensure_path_entry "${HOMEBREW_PREFIX}/bin" "$ZSHRC_PATH"
echo ""

# ============================================
# Brewfile Package Installation
# ============================================
if [ -f "$BREWFILE_PATH" ]; then
    print_status "info" "Installing packages from Brewfile: $BREWFILE_PATH"
    run_with_error_capture "Homebrew bundle" \
        "${HOMEBREW_PREFIX}/bin/brew bundle --verbose --file=\"$BREWFILE_PATH\""
else
    print_status "warning" "Brewfile not found at $BREWFILE_PATH"
    track_failure "Brewfile not found" "1" "Expected: $BREWFILE_PATH"
fi
echo ""

# ============================================
# Dock Configuration
# ============================================
DOCK_PLIST="${SCRIPT_DIR}/configfiles/com.apple.dock.plist"
if [ -f "$DOCK_PLIST" ]; then
    print_status "info" "Applying Dock configuration"
    run_with_error_capture "Dock configuration" \
        "cp -f '$DOCK_PLIST' '${HOME}/Library/Preferences/com.apple.dock.plist' && \
         defaults read '${HOME}/Library/Preferences/com.apple.dock.plist' && \
         killall Dock"
else
    print_status "warning" "Dock plist not found at $DOCK_PLIST"
fi
echo ""

print_summary "User Setup Summary"
exit ${#FAILED_STEPS[@]}
