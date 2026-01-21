#!/bin/bash

# macOS Automated Enrollment Script for SimpleMDM (NoPkg)
# Author: hydramus
# Purpose: Automate setup of macOS device post-enrollment (first login only)
# Version: 2.0

set -euo pipefail

# ===== VARIABLES =====
consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
UNAME_MACHINE="$(uname -m)"
HOMEBREW_PREFIX="/usr/local"
LOGFILE="/var/log/macos_enrollment.log"
MARKER_FILE="/usr/local/simplemdm/enroll_marker"
STATUS_FILE="/tmp/enrollment_status.txt"
REPO_URL="https://github.com/Hydramus/macOS-quick-build/archive/refs/heads/main.zip"
WORK_DIR="/tmp/macos-setup-$$"

if [[ "$UNAME_MACHINE" == "arm64" ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
fi

# ===== LOGGING FUNCTION =====
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log_status() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
  echo "$*" > "$STATUS_FILE"
}

# ===== FUNCTIONS =====
check_first_run() {
  if [ -f "$MARKER_FILE" ]; then
    log "Enrollment already completed. Marker file exists at $MARKER_FILE"
    exit 0
  fi
  
  log "First run detected. Starting enrollment process..."
  mkdir -p "$(dirname "$MARKER_FILE")"
}

wait_for_network() {
  local max_wait=20 count=1
  log_status "Waiting for network connection..."
  
  while [[ $(ifconfig -a inet 2>/dev/null | sed -n -e '/127.0.0.1/d' -e '/0.0.0.0/d' -e '/inet/p' | wc -l) -lt 1 ]]; do
    if [[ $count -gt $max_wait ]]; then
      log "ERROR: No network detected after ${max_wait} attempts."
      exit 1
    fi
    log "Waiting for network... attempt $count/$max_wait"
    sleep 5
    (( count++ ))
  done
  
  log "Network connection established."
}

install_oh_my_zsh() {
  log_status "Installing oh-my-zsh..."
  
  if [ -d "/Users/$consoleuser/.oh-my-zsh" ]; then
    log "oh-my-zsh already installed. Skipping."
    return 0
  fi
  
  log "Downloading and installing oh-my-zsh unattended..."
  su -l "$consoleuser" -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' 2>&1 | tee -a "$LOGFILE"
  
  if [ -d "/Users/$consoleuser/.oh-my-zsh" ]; then
    log "oh-my-zsh installation completed successfully."
  else
    log "WARNING: oh-my-zsh installation may have failed."
  fi
}

download_repo() {
  log_status "Downloading macOS setup repository..."
  
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
  
  log "Downloading from: $REPO_URL"
  
  if curl -L "$REPO_URL" -o repo.zip 2>&1 | tee -a "$LOGFILE"; then
    log "Repository downloaded successfully."
  else
    log "ERROR: Failed to download repository from $REPO_URL"
    exit 1
  fi
  
  log "Extracting repository..."
  unzip -q repo.zip 2>&1 | tee -a "$LOGFILE"
  
  # Find the extracted directory (GitHub creates a folder like macOS-quick-build-main)
  REPO_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name "macOS-quick-build-*" | head -n 1)
  
  if [ -z "$REPO_DIR" ]; then
    log "ERROR: Could not find extracted repository directory."
    exit 1
  fi
  
  log "Repository extracted to: $REPO_DIR"
  cd "$REPO_DIR"
}

run_main_setup() {
  log_status "Running main setup script..."
  
  if [ ! -f "./macOSMachineSetup.sh" ]; then
    log "ERROR: macOSMachineSetup.sh not found in repository."
    exit 1
  fi
  
  # Make scripts executable
  chmod +x ./macOSMachineSetup.sh
  chmod +x ./autobrew.sh 2>/dev/null || true
  chmod +x ./rosetta-2-install.sh 2>/dev/null || true
  
  log "Executing macOSMachineSetup.sh..."
  log "================================================"
  
  # Run the main setup script with logging
  if ./macOSMachineSetup.sh 2>&1 | tee -a "$LOGFILE"; then
    log "================================================"
    log "macOSMachineSetup.sh completed successfully."
  else
    log "================================================"
    log "WARNING: macOSMachineSetup.sh completed with errors. Check log for details."
  fi
}

create_marker() {
  log "Creating enrollment completion marker..."
  echo "Enrollment completed at $(date)" > "$MARKER_FILE"
  log "Marker file created at: $MARKER_FILE"
}

cleanup() {
  log "Cleaning up temporary files..."
  rm -rf "$WORK_DIR" 2>/dev/null || true
  rm -f "$STATUS_FILE" 2>/dev/null || true
  log "Cleanup completed."
}

show_success_popup() {
  log "Displaying success notification to user..."
  
  su -l "$consoleuser" -c "osascript <<EOD
  tell application \"System Events\"
    display dialog \"🎉 Great success with installation!\\n\\nYour Mac has been configured successfully.\\n\\n📄 Log file location:\\n$LOGFILE\\n\\nIf you have any questions, please check in with:\\nIT Support\" buttons {\"OK\"} default button 1 with title \"Setup Complete\" with icon note
  end tell
EOD" 2>&1 | tee -a "$LOGFILE"
}

# ===== MAIN EXECUTION =====
log "========================================"
log "macOS Enrollment Script Started"
log "User: $consoleuser"
log "Architecture: $UNAME_MACHINE"
log "Homebrew Prefix: $HOMEBREW_PREFIX"
log "========================================"

# Check if this is the first run
check_first_run

# Wait for network
wait_for_network

# Install oh-my-zsh first
install_oh_my_zsh

# Download repository
download_repo

# Run main setup script
run_main_setup

# Create completion marker
create_marker

# Cleanup temporary files
cleanup

# Show success notification
show_success_popup

log "========================================"
log "Enrollment completed successfully!"
log "========================================"

exit 0
