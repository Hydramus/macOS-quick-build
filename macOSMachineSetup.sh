#!/bin/bash

consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

# Error tracking system
declare -a FAILED_STEPS=()
declare -a FAILED_EXIT_CODES=()
declare -a FAILED_OUTPUTS=()

# Function to track command failures
track_failure() {
    local step_name="$1"
    local exit_code="$2"
    local output="$3"
    
    FAILED_STEPS+=("$step_name")
    FAILED_EXIT_CODES+=("$exit_code")
    FAILED_OUTPUTS+=("$output")
}

# Function to run command with error capture
run_with_error_capture() {
    local step_name="$1"
    shift
    local cmd="$@"
    
    echo "Running: $step_name"
    local output
    local exit_code
    
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        track_failure "$step_name" "$exit_code" "$output"
        echo "⚠️  Failed with exit code $exit_code (continuing...)"
    else
        echo "✓ Completed successfully"
    fi
    
    echo "$output"
    return $exit_code
} 

echo "Install oh-my-zsh unattended (prevents shell restart that would kill this script)"
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo ""

#INSTALLING HOMEBREW
run_with_error_capture "Homebrew installation" "./autobrew.sh"

# Detect architecture and set HOMEBREW_PREFIX
if [[ $(uname -m) == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

echo "Detected architecture: $(uname -m)"
echo "Using Homebrew prefix: $HOMEBREW_PREFIX"

# Update current shell's PATH immediately
export PATH="${HOMEBREW_PREFIX}/bin:$PATH"
echo "Updated PATH for current shell session"

# Add defensive PATH checking for .zshrc
ZSHRC_PATH="/Users/$(id -un)/.zshrc"
PATH_ENTRY="export PATH=\"${HOMEBREW_PREFIX}/bin:\$PATH\""

if ! grep -Fxq "$PATH_ENTRY" "$ZSHRC_PATH" 2>/dev/null; then
    echo "$PATH_ENTRY" >> "$ZSHRC_PATH"
    echo "Added Homebrew to .zshrc PATH"
else
    echo "Homebrew PATH already exists in .zshrc"
fi

# Verify brew is accessible
if ! command -v brew &> /dev/null; then
    echo "ERROR: brew command not found after installation!"
    echo "PATH: $PATH"
    echo "HOMEBREW_PREFIX: $HOMEBREW_PREFIX"
    track_failure "Brew verification" "1" "brew command not accessible in PATH"
    exit 1
else
    echo "✓ Verified: brew is accessible at $(command -v brew)"
fi 

echo "Checking if device is Apple silicon and needs Rosetta 2 installed" 
run_with_error_capture "Rosetta 2 installation" "./rosetta-2-install.sh"
echo ""

echo "Enabling remote login via SSH"
run_with_error_capture "SSH remote login" "sudo systemsetup -setremotelogin on"
echo ""

#Setting hostname to Mac Serial Number
newhostname=HL-$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
run_with_error_capture "Set hostname" "sudo scutil --set HostName $newhostname && sudo scutil --set ComputerName $newhostname"
echo "New hostname set to $newhostname"
echo ""

# Install packages via Brewfile
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE_PATH="${SCRIPT_DIR}/configfiles/Brewfile"

if [ -f "$BREWFILE_PATH" ]; then
    echo "Installing packages from Brewfile..."
    run_with_error_capture "Homebrew bundle install" "brew bundle --file=\"$BREWFILE_PATH\""
else
    echo "⚠️  Warning: Brewfile not found at $BREWFILE_PATH"
    track_failure "Brewfile not found" "1" "Expected Brewfile at: $BREWFILE_PATH"
fi
echo ""

echo "Set up default dock layout"
run_with_error_capture "Dock configuration" "cp -f './configfiles/com.apple.dock.plist' '/Users/$consoleuser/Library/Preferences/' && defaults read '/Users/$consoleuser/Library/Preferences/com.apple.dock.plist' && killall Dock"
echo ""

echo "Enabled touch id for sudo"
sed="/usr/bin/sed"
enable_touchid="auth       sufficient     pam_tid.so"
run_with_error_capture "Touch ID for sudo" "${sed} -i '' -e '1s/^//p; 1s/^.*/${enable_touchid}/' /etc/pam.d/sudo"
echo ""

echo """
IMPORTANT: 
After the script is complete, please manually set up OneDrive to backup your Desktop and Documents:
1. Open OneDrive's settings via the icon in Mac's menu bar. 
2. Go to the 'Backup' tab.
3. Click on 'Manage backup'.
4. In the next window, select the 'Desktop & Documents Folders' and follow the on-screen instructions.
"""

echo ""
echo "="
echo ""

echo ""

# Print failure report
echo "="
echo "="
echo "SETUP SUMMARY"
echo "="
echo "="
echo ""

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    echo "✅ All steps completed successfully!"
else
    echo "⚠️  Setup completed with ${#FAILED_STEPS[@]} failure(s):"
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
    
    echo "⚠️  Please review the failures above and address them manually."
fi




