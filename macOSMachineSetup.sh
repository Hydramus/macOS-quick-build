#!/bin/bash

consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' ) 

echo "Installing oh-my-zsh in current user's shell"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo ""

#INSTALLING HOMEBREW
sudo ./autobrew.sh

echo "To accommodate for Apple Silicon change to the pathing"
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> /Users/"$(id -un)"/.zshrc 

echo "Checking if device is Apple silicon and needs Rosetta 2 installed" 
./rosetta-2-install.sh 
echo ""

echo "Enabling remote login via SSH"
sudo systemsetup -setremotelogin on
echo ""

#Setting hostname to Mac Serial Number
newhostname=HL-$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
sudo scutil --set HostName $newhostname
sudo scutil --set ComputerName $newhostname
echo "New hostname set to $newhostname"

tools=(
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

# Install tools
for tool in ${tools[@]}; do
    echo "Attempting to install: $tool"
    brew install $tool
done

# List of applications to install
apps=(
    dropbox
    google-chrome
    little-snitch@5
    iterm2
    caffeine
    rectangle
    #blender
    vlc
    the-unarchiver
    #adobe-creative-cloud
    #adobe-acrobat-pro
    stats
    teamviewer
    #microsoft-office              # This is the unofficial cask for Microsoft Office
    stats
)

# Installing applications
for app in ${apps[@]}; do
    echo "Attempting to install: $app"
    brew install --cask $app
done

echo "Set up default dock layout"
cp -f "./configfiles/com.apple.dock.plist" "/Users/$consoleuser/Library/Preferences/"
defaults read "/Users/$consoleuser/Library/Preferences/com.apple.dock.plist"
killall Dock
echo ""

echo "Enabled touch id for sudo"
echo ""
sed="/usr/bin/sed"
enable_touchid="auth       sufficient     pam_tid.so"
${sed} -i '' -e "1s/^//p; 1s/^.*/${enable_touchid}/" /etc/pam.d/sudo

echo """
IMPORTANT: 
After the script is complete, please manually set up OneDrive to backup your Desktop and Documents:
1. Open OneDrive's settings via the icon in Mac's menu bar. 
2. Go to the 'Backup' tab.
3. Click on 'Manage backup'.
4. In the next window, select the 'Desktop & Documents Folders' and follow the on-screen instructions.
"""
