#!/bin/bash

# macOS Automated Enrollment Script for SimpleMDM (NoPkg)
# Author: hydramus
# Purpose: Automate setup of macOS device post-enrollment
# Version: 1.2

set -euo pipefail

# ===== VARIABLES =====
consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
UNAME_MACHINE="$(uname -m)"
HOMEBREW_PREFIX="/usr/local"
LOGFILE="/var/log/macos_enrollment.log"

if [[ "$UNAME_MACHINE" == "arm64" ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
fi

# ===== FUNCTIONS =====
wait_for_network() {
  local max_wait=10 count=1
  while [[ $(ifconfig -a inet 2>/dev/null | sed -n -e '/127.0.0.1/d' -e '/0.0.0.0/d' -e '/inet/p' | wc -l) -lt 1 ]]; do
    if [[ $count -gt $max_wait ]]; then
      echo "[ERROR] No network detected." | tee -a "$LOGFILE"
      exit 1
    fi
    echo "Waiting for network... ($count)" | tee -a "$LOGFILE"
    sleep 5
    (( count++ ))
  done
}

install_rosetta() {
  if [[ "$UNAME_MACHINE" == "arm64" ]]; then
    if ! pgrep oahd >/dev/null 2>&1; then
      echo "Installing Rosetta 2..." | tee -a "$LOGFILE"
      wait_for_network
      /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    else
      echo "Rosetta 2 already installed." | tee -a "$LOGFILE"
    fi
  fi
}

install_homebrew() {
  echo "Installing Homebrew..." | tee -a "$LOGFILE"
  if [[ ! -e "$HOMEBREW_PREFIX/bin/brew" ]]; then
    mkdir -p "$HOMEBREW_PREFIX/Homebrew"
    curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$HOMEBREW_PREFIX/Homebrew"
    ln -s "$HOMEBREW_PREFIX/Homebrew/bin/brew" "$HOMEBREW_PREFIX/bin/brew"

    # Create and set permissions for multi-user Homebrew directories
    for dir in Cellar Caskroom Frameworks bin include lib opt etc sbin share var man; do
      mkdir -p "$HOMEBREW_PREFIX/$dir"
      chown -R "$consoleuser":_developer "$HOMEBREW_PREFIX/$dir"
      chmod -R g+rwx "$HOMEBREW_PREFIX/$dir"
    done
    mkdir -p /Library/Caches/Homebrew
    chmod g+rwx /Library/Caches/Homebrew
    chown "$consoleuser":_developer /Library/Caches/Homebrew
  fi
  echo "Updating Homebrew..." | tee -a "$LOGFILE"
  su -l "$consoleuser" -c "$HOMEBREW_PREFIX/bin/brew update"
}

install_cli_tools() {
  echo "Installing Xcode CLI tools..." | tee -a "$LOGFILE"
  if ! xcode-select -p >/dev/null 2>&1; then
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    softwareupdate -i "$(softwareupdate -l | grep -B 1 -E 'Command Line (Developer|Tools)' | awk -F"*" '/^ +\\*/ {print $2}' | sed 's/^ *//' | tail -n1)"
    rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    xcode-select --switch /Library/Developer/CommandLineTools
  fi
}

install_brew_packages() {
  local tools=(
    bash-completion
    htop
    wget
    watch
    tree
    nmap
    curl
    tmux
    unzip
    vim
  )

  local apps=(
    dropbox
    google-chrome
    little-snitch@5
    iterm2
    caffeine
    rectangle
    vlc
    the-unarchiver
    adobe-creative-cloud
    stats
    teamviewer
  )

  for tool in "${tools[@]}"; do
    echo "Installing $tool..." | tee -a "$LOGFILE"
    brew install "$tool"
  done

  for app in "${apps[@]}"; do
    echo "Installing $app..." | tee -a "$LOGFILE"
    brew install --cask "$app"
  done
}

apply_configs() {
  #echo "Applying dock layout..." | tee -a "$LOGFILE"
  #cp -f "./com.apple.dock.plist" "/Users/$consoleuser/Library/Preferences/"
  #killall Dock || true

  echo "Enabling Touch ID for sudo..." | tee -a "$LOGFILE"
  if ! grep -q "pam_tid.so" /etc/pam.d/sudo; then
    sed -i '' '1s;^;auth       sufficient     pam_tid.so\\n;' /etc/pam.d/sudo
  fi

  echo "Setting hostname to serial number..." | tee -a "$LOGFILE"
  newhostname=HL-$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
  sudo scutil --set HostName "$newhostname"
  sudo scutil --set ComputerName "$newhostname"

  echo "Enabling SSH remote login..." | tee -a "$LOGFILE"
  sudo systemsetup -setremotelogin on
}

show_success_popup() {
  osascript <<EOD
  tell application "System Events"
    display dialog "✅ macOS enrollment script completed successfully!\\n\\n📄 Log file: $LOGFILE" buttons {"Close"} default button 1 with title "Enrollment Complete"
  end tell
EOD
}

# ===== EXECUTION =====
install_cli_tools
install_rosetta
install_homebrew
install_brew_packages
apply_configs

show_success_popup

echo "\nIMPORTANT: Please manually set up Dropbox to back up Desktop and Documents." | tee -a "$LOGFILE"
echo "macOS enrollment script completed successfully." | tee -a "$LOGFILE"

exit 0
