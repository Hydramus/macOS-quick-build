#!/bin/bash
# System-level setup phase — must run as root.
# Called by macOSMachineSetup.sh with the console user as $1.
# Covers: Xcode CLT, Xcode license, Rosetta 2, SSH, hostname, Touch ID, Homebrew installation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] setup-system.sh must run as root"
    exit 1
fi

consoleuser="$1"
if [[ -z "$consoleuser" || "$consoleuser" == "root" ]]; then
    echo "[ERROR] Console user not provided or is root"
    exit 1
fi

# ============================================
# Xcode Command Line Tools
# ============================================
echo "============================================"
echo "Checking for Xcode Command Line Tools"
echo "============================================"

if xcode-select -p &>/dev/null; then
    print_status "success" "Xcode CLT already installed at: $(xcode-select -p)"
else
    print_status "info" "Xcode CLT not found. Attempting automated install via softwareupdate..."

    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    clt=$(softwareupdate -l 2>/dev/null | grep -B 1 -E "Command Line (Developer|Tools)" | awk -F"*" '/^ +\*/ {print $2}' | sed 's/^ *//' | tail -n1)
    if [[ -z "$clt" ]]; then
        clt=$(softwareupdate -l 2>/dev/null | grep "Label: Command" | tail -1 | sed 's#\* Label: \(.*\)#\1#')
    fi

    if [[ -n "$clt" ]]; then
        print_status "info" "Found: $clt — installing (may take 5-15 min)..."
        if softwareupdate -i "$clt" --verbose; then
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
            /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null
            print_status "success" "Xcode CLT installed"
        else
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
            clt=""
        fi
    fi

    if [[ -z "$clt" ]] || ! xcode-select -p &>/dev/null; then
        # Only launch the GUI dialog when stdin is a real terminal (interactive run).
        # In MDM/LaunchDaemon context this branch is a hard failure — no GUI available.
        if [[ -t 0 ]]; then
            echo ""
            echo "============================================"
            echo "MANUAL INSTALLATION REQUIRED"
            echo "============================================"
            print_status "info" "Opening GUI installer. Click Install in the dialog, then press Enter here."
            xcode-select --install 2>/dev/null
            read -r -p "Press Enter once CLT installation is complete..."
            if ! xcode-select -p &>/dev/null; then
                print_status "error" "Xcode CLT still not found after manual install attempt."
                exit 1
            fi
        else
            track_failure "Xcode CLT" "1" "Non-interactive context: softwareupdate failed and GUI installer is unavailable"
            print_status "error" "Xcode CLT could not be installed non-interactively. Aborting."
            exit 1
        fi
    fi
fi
echo ""

# ============================================
# Accept Xcode License
# ============================================
print_status "info" "Accepting Xcode license"
if xcodebuild -license accept 2>/dev/null; then
    print_status "success" "Xcode license accepted"
else
    print_status "warning" "Could not accept Xcode license (may already be accepted)"
fi
echo ""

# ============================================
# Rosetta 2 (Apple Silicon only)
# ============================================
run_with_error_capture "Rosetta 2" "${SCRIPT_DIR}/rosetta-2-install.sh"
echo ""

# ============================================
# SSH Remote Login
# systemsetup -setremotelogin requires Full Disk Access on Monterey+;
# loading the LaunchDaemon directly works without that entitlement.
# ============================================
SSH_PLIST="/System/Library/LaunchDaemons/ssh.plist"
if launchctl list com.openssh.sshd &>/dev/null; then
    print_status "info" "SSH remote login is already enabled — skipping"
else
    run_with_error_capture "SSH remote login" \
        "launchctl load -w '$SSH_PLIST'"
fi
echo ""

# ============================================
# Hostname
# ============================================
newhostname=HL-$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
run_with_error_capture "Set hostname" "scutil --set HostName $newhostname && scutil --set ComputerName $newhostname"
print_status "info" "Hostname set to $newhostname"
echo ""

# ============================================
# Touch ID for sudo
# ============================================
print_status "info" "Enabling Touch ID for sudo"
enable_touchid="auth       sufficient     pam_tid.so"
if grep -qF "pam_tid.so" /etc/pam.d/sudo 2>/dev/null; then
    print_status "info" "Touch ID for sudo already enabled — skipping"
else
    run_with_error_capture "Touch ID for sudo" \
        "{ printf '%s\n' '$enable_touchid'; cat /etc/pam.d/sudo; } > /tmp/_pam_sudo && mv /tmp/_pam_sudo /etc/pam.d/sudo"
fi
echo ""

# ============================================
# Little Snitch mass deployment configuration
#
# Little Snitch 6 reads /var/root/LittleSnitchMassDeploymentConfiguration.json
# on its VERY FIRST launch and applies it as if restoring a backup — licence
# key included. It then deletes the file, because it holds the licence key.
#
# The window only exists on a machine where Little Snitch has never run:
#   - the network extension must not be activated yet, and
#   - /Library/Application Support/Objective Development/Little Snitch
#     must not exist yet.
# Otherwise the file is ignored (an anti-tampering measure), and the config
# has to be applied afterwards with `littlesnitch restore-model` instead —
# which is what setup-user.sh falls back to.
#
# So this has to be staged now, in the root phase, before the cask is
# installed and the app is first launched in Phase 2.
# ============================================
LS_MASS_CONFIG_SRC="${SCRIPT_DIR}/configfiles/littlesnitch/LittleSnitchMassDeploymentConfiguration.json"
LS_MASS_CONFIG_DST="/var/root/LittleSnitchMassDeploymentConfiguration.json"
LS_SUPPORT_DIR="/Library/Application Support/Objective Development/Little Snitch"

if [[ ! -f "$LS_MASS_CONFIG_SRC" ]]; then
    print_status "info" "No Little Snitch mass deployment config at $LS_MASS_CONFIG_SRC — skipping (see configfiles/littlesnitch/README.md)"
elif ! /usr/bin/plutil -lint "$LS_MASS_CONFIG_SRC" &>/dev/null && ! /usr/bin/python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$LS_MASS_CONFIG_SRC" &>/dev/null; then
    track_failure "Little Snitch mass deployment config" "1" "$LS_MASS_CONFIG_SRC is not valid JSON — not staging it"
else
    if [[ -d "$LS_SUPPORT_DIR" ]]; then
        print_status "warning" "Little Snitch has run on this Mac before ($LS_SUPPORT_DIR exists) — mass deployment config will be IGNORED; setup-user.sh will try restore-model instead"
    fi
    if /usr/bin/systemextensionsctl list 2>/dev/null | grep -q "at.obdev.littlesnitch"; then
        print_status "warning" "Little Snitch network extension is already activated — mass deployment config will be IGNORED; setup-user.sh will try restore-model instead"
    fi
    run_with_error_capture "Stage Little Snitch mass deployment config" \
        "install -m 600 -o root -g wheel '$LS_MASS_CONFIG_SRC' '$LS_MASS_CONFIG_DST'"
fi
echo ""

# ============================================
# Homebrew (directory creation and initial install requires root)
# ============================================
run_with_error_capture "Homebrew installation" "${SCRIPT_DIR}/autobrew.sh"

HOMEBREW_PREFIX=$(detect_architecture)
export PATH="${HOMEBREW_PREFIX}/bin:$PATH"

if ! command_exists brew; then
    track_failure "brew verification" "1" "brew not found in PATH after install"
    print_status "error" "brew not accessible — PATH: $PATH"
    print_summary "System Setup Summary"
    exit 1
fi

print_status "success" "brew accessible at $(command -v brew)"
echo ""

print_summary "System Setup Summary"
exit ${#FAILED_STEPS[@]}
