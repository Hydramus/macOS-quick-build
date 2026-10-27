#!/bin/bash
# User-level setup phase — runs as the console user, no root needed inside.
# Called by macOSMachineSetup.sh via: sudo -u <user> -H ./setup-user.sh <brewfile_path>
# Covers: oh-my-zsh, PATH in .zshrc, brew bundle (CLI tools), default browser, dock configuration.

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
# Homebrew Update
# ============================================
print_status "info" "Updating Homebrew before bundle install"
run_with_error_capture "Homebrew update" \
    "${HOMEBREW_PREFIX}/bin/brew update"
echo ""

# ============================================
# Brewfile Package Installation
# ============================================
if [ -f "$BREWFILE_PATH" ]; then
    print_status "info" "Installing packages from Brewfile: $BREWFILE_PATH"
    run_with_error_capture "Homebrew bundle" \
        "${HOMEBREW_PREFIX}/bin/brew bundle install --verbose --file=\"$BREWFILE_PATH\""
else
    print_status "warning" "Brewfile not found at $BREWFILE_PATH"
    track_failure "Brewfile not found" "1" "Expected: $BREWFILE_PATH"
fi
echo ""

# ============================================
# Chrome as Default Browser
# duti binds URL schemes/UTIs to a bundle identifier; Chrome's is
# com.google.chrome regardless of channel (stable build).
# ============================================
CHROME_APP="/Applications/Google Chrome.app"
if [ -d "$CHROME_APP" ]; then
    if command_exists duti; then
        print_status "info" "Setting Google Chrome as the default browser"
        run_with_error_capture "Chrome as default browser" \
            "duti -s com.google.chrome http && \
             duti -s com.google.chrome https && \
             duti -s com.google.chrome public.html"
    else
        print_status "warning" "duti not found — cannot set default browser (check Brewfile)"
    fi
else
    print_status "warning" "Google Chrome not found at $CHROME_APP — skipping default browser setup"
fi
echo ""

# ============================================
# Dock Configuration
# ============================================
# The plist is XML with __HOME__ where the user's home folder goes
DOCK_PLIST="${SCRIPT_DIR}/configfiles/com.apple.dock.plist"
if [ -f "$DOCK_PLIST" ]; then
    print_status "info" "Applying Dock configuration"
    run_with_error_capture "Dock configuration" \
        "sed 's#__HOME__#${HOME}#g' '$DOCK_PLIST' > '${HOME}/Library/Preferences/com.apple.dock.plist' && \
         defaults read '${HOME}/Library/Preferences/com.apple.dock.plist' >/dev/null && \
         killall Dock"
else
    print_status "warning" "Dock plist not found at $DOCK_PLIST"
fi
echo ""

print_summary "User Setup Summary"
exit ${#FAILED_STEPS[@]}
