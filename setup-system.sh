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
# ============================================
run_with_error_capture "SSH remote login" "systemsetup -setremotelogin on"
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
run_with_error_capture "Touch ID for sudo" \
    "/usr/bin/sed -i '' -e '1s/^//p; 1s/^.*/${enable_touchid}/' /etc/pam.d/sudo"
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
