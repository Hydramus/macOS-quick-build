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
# Disable Chrome Telemetry
# Written as a system-wide managed policy (Chrome enterprise policy) rather
# than a per-user default, since Chrome ignores plain defaults for these
# keys outside of a managed-preferences plist. Phase 2 holds temporary
# passwordless sudo (granted by macOSMachineSetup.sh), so this write
# succeeds without an extra password prompt.
# ============================================
if [ -d "$CHROME_APP" ]; then
    print_status "info" "Disabling Chrome telemetry (managed policy)"
    CHROME_POLICY_PLIST="/Library/Managed Preferences/com.google.Chrome.plist"
    run_with_error_capture "Chrome telemetry policy" \
        "sudo mkdir -p '/Library/Managed Preferences' && \
         sudo defaults write '$CHROME_POLICY_PLIST' MetricsReportingEnabled -bool false && \
         sudo defaults write '$CHROME_POLICY_PLIST' URLKeyedAnonymizedDataCollectionEnabled -bool false && \
         sudo defaults write '$CHROME_POLICY_PLIST' ChromeVariations -int 0 && \
         sudo defaults write '$CHROME_POLICY_PLIST' FeedbackSurveysEnabled -bool false && \
         sudo chown root:wheel '$CHROME_POLICY_PLIST' && \
         sudo chmod 644 '$CHROME_POLICY_PLIST'"
fi
echo ""

# ============================================
# Little Snitch — cask depends on the macOS release
#
# Homebrew ships two casks and each declares a minimum macOS:
#   little-snitch     (6.x) -> requires macOS 14 (Sonoma) or newer
#   little-snitch@5   (5.x) -> requires macOS 11 (Big Sur) or newer
# Installing the wrong one just aborts with a depends_on error, so the
# choice is made here at runtime instead of being hardcoded in the Brewfile.
# ============================================
MACOS_MAJOR=$(macos_major_version)
print_status "info" "Detected macOS major version: ${MACOS_MAJOR}"

if [[ "$MACOS_MAJOR" -ge 14 ]]; then
    LITTLE_SNITCH_CASK="little-snitch"
elif [[ "$MACOS_MAJOR" -ge 11 ]]; then
    LITTLE_SNITCH_CASK="little-snitch@5"
else
    LITTLE_SNITCH_CASK=""
fi

if [[ -z "$LITTLE_SNITCH_CASK" ]]; then
    print_status "warning" "macOS ${MACOS_MAJOR} is older than 11 — no supported Little Snitch cask, skipping"
elif "${HOMEBREW_PREFIX}/bin/brew" list --cask "$LITTLE_SNITCH_CASK" &>/dev/null; then
    print_status "info" "$LITTLE_SNITCH_CASK already installed — skipping"
else
    print_status "info" "Installing $LITTLE_SNITCH_CASK for macOS ${MACOS_MAJOR}"
    run_with_error_capture "Little Snitch ($LITTLE_SNITCH_CASK) installation" \
        "${HOMEBREW_PREFIX}/bin/brew install --cask $LITTLE_SNITCH_CASK"
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
