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
# Little Snitch — unattended install + template configuration
#
# Cask choice depends on the macOS release. Homebrew ships two casks and each
# declares a minimum macOS:
#   little-snitch     (6.x) -> requires macOS 14 (Sonoma) or newer
#   little-snitch@5   (5.x) -> requires macOS 11 (Big Sur) or newer
# Installing the wrong one just aborts with a depends_on error, so the choice
# is made here at runtime instead of being hardcoded in the Brewfile.
#
# Unattended-ness has three separate parts, and only the first is fully under
# this script's control:
#   1. Licence agreement / installer prompts -> user defaults, set below.
#   2. Network extension + content filter approval -> can ONLY be pre-approved
#      by a signed .mobileconfig pushed from MDM to a supervised device. See
#      configfiles/littlesnitch/LittleSnitch.mobileconfig. Without it, someone
#      has to click through the System Settings prompts on first launch.
#   3. Rules/settings/licence -> the mass deployment JSON staged in Phase 1,
#      or `littlesnitch restore-model` with a .lsbackup template (below).
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

LS_APP="/Applications/Little Snitch.app"
LS_TEMPLATE="${SCRIPT_DIR}/configfiles/littlesnitch/template.lsbackup"

if [[ -z "$LITTLE_SNITCH_CASK" ]]; then
    print_status "warning" "macOS ${MACOS_MAJOR} is older than 11 — no supported Little Snitch cask, skipping"
else
    # --- Suppress the licence/installer/welcome prompts -------------------
    # These are user defaults for the account that runs the app (not root),
    # and must be set BEFORE the first launch to have any effect.
    print_status "info" "Pre-accepting Little Snitch licence and install prompts for $(id -un)"
    defaults write at.obdev.littlesnitch AcceptLicenseAgreementAutomatically YES 2>/dev/null
    defaults write at.obdev.littlesnitch PerformInstallationAutomatically   YES 2>/dev/null
    defaults write at.obdev.littlesnitch LastShownWelcomeWindowVersion      2   2>/dev/null

    # --- Install the cask -------------------------------------------------
    if "${HOMEBREW_PREFIX}/bin/brew" list --cask "$LITTLE_SNITCH_CASK" &>/dev/null; then
        print_status "info" "$LITTLE_SNITCH_CASK already installed — skipping cask install"
    else
        print_status "info" "Installing $LITTLE_SNITCH_CASK for macOS ${MACOS_MAJOR}"
        run_with_error_capture "Little Snitch ($LITTLE_SNITCH_CASK) installation" \
            "${HOMEBREW_PREFIX}/bin/brew install --cask $LITTLE_SNITCH_CASK"
    fi

    # --- First launch -----------------------------------------------------
    # Launching installs the network extension and, on Little Snitch 6,
    # consumes /var/root/LittleSnitchMassDeploymentConfiguration.json.
    # Best-effort: this needs a real GUI login session, so it is a warning
    # rather than a tracked failure when it does not take.
    if [[ ! -d "$LS_APP" ]]; then
        print_status "warning" "$LS_APP not found — skipping first-launch and configuration steps"
    elif [[ "$(stat -f%Su /dev/console 2>/dev/null)" != "$(id -un)" ]]; then
        print_status "warning" "No GUI session for $(id -un) — skipping first launch. Little Snitch will install its network extension the first time someone logs in and opens it."
    else
        if pgrep -x "Little Snitch" &>/dev/null; then
            print_status "info" "Little Snitch is already running — not relaunching"
        else
            print_status "info" "Launching Little Snitch once to install the network extension"
            nohup "${LS_APP}/Contents/MacOS/Little Snitch" \
                -AcceptLicenseAgreementAutomatically YES \
                -PerformInstallationAutomatically YES \
                >/dev/null 2>&1 &
            disown 2>/dev/null
        fi

        # Wait for the extension to show up (approval may need a human click
        # unless the MDM profile pre-approved it).
        print_status "info" "Waiting up to 120s for the Little Snitch network extension to activate"
        LS_EXT_OK=0
        for _ in $(seq 1 24); do
            if /usr/bin/systemextensionsctl list 2>/dev/null | grep -q "at.obdev.littlesnitch"; then
                LS_EXT_OK=1
                break
            fi
            sleep 5
        done
        if [[ "$LS_EXT_OK" -eq 1 ]]; then
            print_status "success" "Little Snitch network extension is active"
        else
            print_status "warning" "Little Snitch network extension not active after 120s — approval is likely still pending in System Settings > General > Login Items & Extensions > Network Extensions"
        fi
    fi

    # --- Apply the template configuration ---------------------------------
    # On a clean macOS 14+ machine the Phase 1 mass deployment JSON has
    # already done this. This path covers Little Snitch 5, re-runs, and any
    # machine where the mass deployment window had already closed.
    # It needs "Allow access via Terminal", which the mass deployment config
    # turns on via "allowCommandLineAccess": 1.
    if [[ -f "$LS_TEMPLATE" && -d "$LS_APP" ]]; then
        LS_CLI=$(littlesnitch_cli)
        if [[ -z "$LS_CLI" ]]; then
            print_status "warning" "littlesnitch command line tool not found — cannot apply $LS_TEMPLATE"
        elif ! sudo -n "$LS_CLI" list-preferences --global-only &>/dev/null; then
            print_status "warning" "littlesnitch CLI is not usable (Terminal access is off, or sudo needs a password) — apply $LS_TEMPLATE manually, or enable Little Snitch > Settings > Security > Allow access via Terminal"
        else
            print_status "info" "Applying Little Snitch template configuration from $LS_TEMPLATE"
            # --preserve-terminal-access is documented for enterprise
            # deployment but is absent from some `restore-model --help`
            # builds, so fall back to a plain restore.
            if sudo -n "$LS_CLI" restore-model --preserve-terminal-access "$LS_TEMPLATE" &>/dev/null; then
                print_status "success" "Little Snitch template configuration applied"
            else
                run_with_error_capture "Little Snitch template configuration" \
                    "sudo -n '$LS_CLI' restore-model '$LS_TEMPLATE'"
            fi
        fi
    elif [[ ! -f "$LS_TEMPLATE" ]]; then
        print_status "info" "No Little Snitch template at $LS_TEMPLATE — leaving the shipped defaults (see configfiles/littlesnitch/README.md)"
    fi
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
