#!/bin/bash

# macOS Machine Setup Script
# Requires sudo to run

# ============================================
# ANSI Color Codes 
# ============================================
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ============================================
# Privilege and User Context Setup
# ============================================

# Ensure script is run with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} This script must be run with sudo"
    echo "Usage: sudo ./macOSMachineSetup.sh"
    exit 1
fi

# Get the actual user who invoked sudo (not root)
if [ -n "$SUDO_USER" ]; then
    consoleuser="$SUDO_USER"
else
    consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
fi

# Validate we have a real user
if [[ -z "$consoleuser" || "$consoleuser" == "root" ]]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Could not determine console user"
    exit 1
fi

echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} Running as root, operating on user: $consoleuser"
echo ""

# ============================================
# Error Tracking System 
# ============================================
FAILED_STEPS=()
FAILED_EXIT_CODES=()
FAILED_OUTPUTS=()

# ============================================
# Reusable Helper Functions
# ============================================

# Function to track command failures
track_failure() {
    local step_name="$1"
    local exit_code="$2"
    local output="$3"
    
    FAILED_STEPS[${#FAILED_STEPS[@]}]="$step_name"
    FAILED_EXIT_CODES[${#FAILED_EXIT_CODES[@]}]="$exit_code"
    FAILED_OUTPUTS[${#FAILED_OUTPUTS[@]}]="$output"
}

# Function to print colored status messages
print_status() {
    local status_type="$1"
    local message="$2"
    
    case "$status_type" in
        "info")
            echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $message"
            ;;
        "success")
            echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $message"
            ;;
        "warning")
            echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $message"
            ;;
        "error")
            echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $message"
            ;;
    esac
}

# Function to run command with live output and error capture
run_with_error_capture() {
    local step_name="$1"
    shift
    local cmd="$@"
    
    print_status "info" "Starting: $step_name"
    
    # Use temporary file to capture output while displaying live
    local capture_file=$(mktemp)
    local exit_code
    
    # Execute with tee to show output AND save it
    if eval "$cmd" 2>&1 | tee "$capture_file"; then
        exit_code=0
        print_status "success" "Completed: $step_name"
        rm -f "$capture_file"  # Delete on success
    else
        exit_code=${PIPESTATUS[0]}
        local captured_output=$(cat "$capture_file")
        track_failure "$step_name" "$exit_code" "$captured_output"
        print_status "warning" "Failed: $step_name (exit code: $exit_code, continuing...)"
        print_status "info" "Log file saved at: $capture_file"
        # Keep file for debugging - don't delete
    fi
    
    return $exit_code
}

# Function to detect system architecture
detect_architecture() {
    local arch=$(uname -m)
    if [[ "$arch" == "arm64" ]]; then
        echo "/opt/homebrew"
    else
        echo "/usr/local"
    fi
}

# Function to add PATH entry if not present
ensure_path_entry() {
    local path_to_add="$1"
    local config_file="$2"
    local path_line="export PATH=\"${path_to_add}:\$PATH\""
    
    if ! grep -Fxq "$path_line" "$config_file" 2>/dev/null; then
        echo "$path_line" >> "$config_file"
        print_status "success" "Added to PATH in $config_file"
        return 0
    else
        print_status "info" "PATH entry already exists in $config_file"
        return 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to run command as console user
run_as_user() {
    sudo -u "$consoleuser" -H "$@"
} 

# ============================================
# Xcode Command Line Tools Installation
# ============================================
echo "============================================"
echo "Checking for Xcode Command Line Tools"
echo "============================================"

if xcode-select -p &>/dev/null; then
    print_status "success" "Xcode Command Line Tools already installed at: $(xcode-select -p)"
else
    print_status "info" "Xcode Command Line Tools not found. Installing..."
    
    # Method 1: Try non-interactive installation via softwareupdate (no GUI)
    print_status "info" "Attempting automated installation via softwareupdate..."
    
    # Create temporary file to trigger softwareupdate to show CLT
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    
    # Find the Command Line Tools package
    clt=$(softwareupdate -l 2>/dev/null | grep -B 1 -E "Command Line (Developer|Tools)" | awk -F"*" '/^ +\*/ {print $2}' | sed 's/^ *//' | tail -n1)
    
    # Fallback for newer macOS versions where format changed
    if [[ -z "$clt" ]]; then
        clt=$(softwareupdate -l 2>/dev/null | grep "Label: Command" | tail -1 | sed 's#\* Label: \(.*\)#\1#')
    fi
    
    if [[ -n "$clt" ]]; then
        print_status "info" "Found package: $clt"
        print_status "info" "Installing (this may take 5-15 minutes)..."
        
        if softwareupdate -i "$clt" --verbose; then
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
            /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null
            print_status "success" "Command Line Tools installed successfully"
        else
            rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
            print_status "warning" "Automated installation failed"
            clt=""  # Clear to trigger fallback
        fi
    fi
    
    # Method 2: Fall back to GUI prompt if automated installation failed
    if [[ -z "$clt" ]] || ! xcode-select -p &>/dev/null; then
        echo ""
        echo "============================================"
        echo "MANUAL INSTALLATION REQUIRED"
        echo "============================================"
        print_status "warning" "Automated installation could not complete."
        echo ""
        print_status "info" "Attempting to open GUI installer prompt..."
        xcode-select --install 2>/dev/null
        echo ""
        echo "Please follow these steps:"
        echo "1. A popup should appear asking to install Command Line Developer Tools"
        echo "2. Click 'Install' and wait for installation to complete (5-15 minutes)"
        echo ""
        echo "If no popup appears, you can download manually:"
        echo "  1. Visit: https://developer.apple.com/download/all/"
        echo "  2. Sign in with your Apple ID"
        echo "  3. Search for 'Command Line Tools for Xcode'"
        echo "  4. Download the version matching your macOS"
        echo "  5. Install the downloaded .dmg file"
        echo ""
        echo "After installation completes, re-run this script."
        echo "============================================"
        
        # Give user time to see the message
        sleep 3
        
        # Check one more time if tools became available
        if ! xcode-select -p &>/dev/null; then
            echo ""
            print_status "error" "Xcode Command Line Tools are required but not installed."
            print_status "error" "This script cannot continue without them."
            echo ""
            exit 1
        fi
    fi
fi

echo ""
echo "============================================"
echo ""

# ============================================
# Accept Xcode License
# ============================================
print_status "info" "Accepting Xcode license agreement"
if xcodebuild -license accept 2>/dev/null; then
    print_status "success" "Xcode license accepted"
else
    print_status "warning" "Could not accept Xcode license (may already be accepted or not applicable)"
fi
echo ""

# ============================================
# Oh-My-Zsh Installation
# ============================================
print_status "info" "Installing oh-my-zsh unattended (prevents shell restart that would kill this script)"
run_as_user sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
echo ""

# ============================================
# Homebrew Installation
# ============================================
run_with_error_capture "Homebrew installation" "./autobrew.sh"

# Detect architecture and set HOMEBREW_PREFIX
HOMEBREW_PREFIX=$(detect_architecture)
print_status "info" "Detected architecture: $(uname -m)"
print_status "info" "Using Homebrew prefix: $HOMEBREW_PREFIX"

# Update current shell's PATH immediately
export PATH="${HOMEBREW_PREFIX}/bin:$PATH"
print_status "success" "Updated PATH for current shell session"

# Add PATH to .zshrc and ensure proper ownership
ZSHRC_PATH="/Users/$consoleuser/.zshrc"
ensure_path_entry "${HOMEBREW_PREFIX}/bin" "$ZSHRC_PATH"
chown "$consoleuser:staff" "$ZSHRC_PATH" 2>/dev/null

# Verify brew is accessible
if ! command_exists brew; then
    print_status "error" "brew command not found after installation!"
    print_status "info" "PATH: $PATH"
    print_status "info" "HOMEBREW_PREFIX: $HOMEBREW_PREFIX"
    track_failure "Brew verification" "1" "brew command not accessible in PATH"
    exit 1
else
    print_status "success" "Verified: brew is accessible at $(command -v brew)"
fi 

# ============================================
# Rosetta 2 Installation (Apple Silicon)
# ============================================
print_status "info" "Checking if device is Apple silicon and needs Rosetta 2 installed"
run_with_error_capture "Rosetta 2 installation" "./rosetta-2-install.sh"
echo ""

# ============================================
# SSH Remote Login
# ============================================
print_status "info" "Enabling remote login via SSH"
run_with_error_capture "SSH remote login" "systemsetup -setremotelogin on"
echo ""

# ============================================
# Hostname Configuration
# ============================================
newhostname=HL-$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
run_with_error_capture "Set hostname" "scutil --set HostName $newhostname && scutil --set ComputerName $newhostname"
print_status "info" "New hostname set to $newhostname"
echo ""

# ============================================
# Brewfile Package Installation
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE_PATH="${SCRIPT_DIR}/configfiles/Brewfile"

if [ -f "$BREWFILE_PATH" ]; then
    print_status "info" "Installing packages from Brewfile..."
    
    # Temporarily allow console user to run brew without password (for cask installs)
    SUDOERS_TEMP="/etc/sudoers.d/brew_temp_$$"
    echo "$consoleuser ALL=(root) NOPASSWD: ${HOMEBREW_PREFIX}/bin/brew" > "$SUDOERS_TEMP"
    chmod 0440 "$SUDOERS_TEMP"
    print_status "info" "Configured temporary sudo access for brew commands"
    
    # Run brew bundle as console user (cask installs will work without prompts)
    run_with_error_capture "Homebrew bundle install" "sudo -u '$consoleuser' -H ${HOMEBREW_PREFIX}/bin/brew bundle --verbose --file=\"$BREWFILE_PATH\""
    
    # Remove temporary sudoers entry
    rm -f "$SUDOERS_TEMP"
    print_status "success" "Removed temporary sudo permissions"
else
    print_status "warning" "Brewfile not found at $BREWFILE_PATH"
    track_failure "Brewfile not found" "1" "Expected Brewfile at: $BREWFILE_PATH"
fi
echo ""

# ============================================
# Dock Configuration
# ============================================
print_status "info" "Setting up default dock layout"
run_with_error_capture "Dock configuration" "cp -f './configfiles/com.apple.dock.plist' '/Users/$consoleuser/Library/Preferences/' && chown '$consoleuser:staff' '/Users/$consoleuser/Library/Preferences/com.apple.dock.plist' && sudo -u '$consoleuser' defaults read '/Users/$consoleuser/Library/Preferences/com.apple.dock.plist' && sudo -u '$consoleuser' killall Dock"
echo ""

# ============================================
# Touch ID for sudo
# ============================================
print_status "info" "Enabling touch ID for sudo"
sed="/usr/bin/sed"
enable_touchid="auth       sufficient     pam_tid.so"
run_with_error_capture "Touch ID for sudo" "${sed} -i '' -e '1s/^//p; 1s/^.*/${enable_touchid}/' /etc/pam.d/sudo"
echo ""

# ============================================
# Manual Steps Reminder
# ============================================
echo ""
echo "============================================"
echo "MANUAL STEPS REQUIRED"
echo "============================================"
echo ""
print_status "info" "After the script is complete, please manually set up OneDrive to backup your Desktop and Documents:"
echo "  1. Open OneDrive's settings via the icon in Mac's menu bar"
echo "  2. Go to the 'Backup' tab"
echo "  3. Click on 'Manage backup'"
echo "  4. In the next window, select the 'Desktop & Documents Folders' and follow the on-screen instructions"
echo ""

# ============================================
# Setup Summary Report
# ============================================
echo ""
echo "============================================"
echo "SETUP SUMMARY"
echo "============================================"
echo ""

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    print_status "success" "All steps completed successfully!"
else
    print_status "warning" "Setup completed with ${#FAILED_STEPS[@]} failure(s):"
    echo ""
    
    for i in "${!FAILED_STEPS[@]}"; do
        echo "-------------------------------------------"
        echo "Failed Step $((i+1)): ${FAILED_STEPS[$i]}"
        echo "Exit Code: ${FAILED_EXIT_CODES[$i]}"
        echo "Output:"
        echo "${FAILED_OUTPUTS[$i]}"
        echo "-------------------------------------------"
        echo ""
    done
    
    print_status "warning" "Please review the failures above and address them manually."
fi




