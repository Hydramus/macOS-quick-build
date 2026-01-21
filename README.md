# macOS-quick-build

Automated macOS setup and configuration toolkit for both manual installation and MDM-based deployment (SimpleMDM).

---

# Manual Installation (Interactive)

For manual setup on a new Mac, run the main setup script directly:

### Prerequisites
- macOS 10.15 or later
- Admin/sudo access
- Internet connection

### Quick Start

1. Clone or download this repository:
   ```bash
   git clone https://github.com/Hydramus/macOS-quick-build.git
   cd macOS-quick-build
   ```

2. Make scripts executable:
   ```bash
   chmod +x macOSMachineSetup.sh autobrew.sh rosetta-2-install.sh
   ```

3. Run the main setup script:
   ```bash
   ./macOSMachineSetup.sh
   ```

### What It Does

The main script (`macOSMachineSetup.sh`) automatically:
- Installs oh-my-zsh (unattended mode)
- Installs Homebrew with architecture detection (Apple Silicon/Intel)
- Installs Rosetta 2 (Apple Silicon only)
- Installs all packages from `configfiles/Brewfile`
- Configures hostname to serial number
- Enables SSH remote login
- Applies dock layout
- Enables Touch ID for sudo
- Updates PATH for current shell session
- Tracks and reports any failures with full error details

### Features

- **Architecture-aware**: Automatically detects and configures for Apple Silicon or Intel Macs
- **Error resilient**: Continues on failures and reports them at the end
- **Idempotent**: Can be run multiple times safely
- **No shell restart required**: PATH is updated in the current session
- **Comprehensive error tracking**: Full stdout/stderr output for debugging

---

# MDM-Ready Enrollment (SimpleMDM nopkg)

For automated deployment via SimpleMDM after first user login.

### Overview

The `nopkg-enroll.sh` script is designed for SimpleMDM's nopkg feature to automate macOS setup immediately after the first user account is created. It downloads the latest version of this repository and executes the full setup process unattended.

### Key Features

- **First-run only**: Uses marker file to prevent re-execution
- **Timestamped logging**: All actions logged to `/var/log/macos_enrollment.log` with timestamps
- **GitHub-based**: Downloads latest repository version automatically
- **Unattended execution**: Runs completely in the background
- **User notification**: Shows success dialog with log file path
- **Network resilient**: Waits up to 100 seconds for network connectivity
- **Comprehensive error handling**: Tracks failures but continues execution

### Setup Instructions

1. **Update Repository URL**
   
   Edit line 17 in `nopkg_installer/nopkg-enroll.sh` and `nopkg_installer/postinstall.sh`:
   ```bash
   REPO_URL="https://github.com/Hydramus/macOS-quick-build/archive/refs/heads/main.zip"
   ```

2. **Generate pkginfo File**
   
   Navigate to the `nopkg_installer/` directory and run:
   ```bash
   makepkginfo --nopkg \
     --name="nopkg-enroll" \
     --displayname="Auto-Enroll via SimpleMDM" \
     --pkgvers="2.0" \
     --installcheck_script=installcheck.sh \
     --postinstall_script=postinstall.sh \
     --unattended_install \
     > nopkg-enroll.pkginfo
   ```

3. **Upload to SimpleMDM**
   
   - Upload the generated `nopkg-enroll.pkginfo` to SimpleMDM
   - Configure it to run after the first user account is created
   - Set it to auto-install on enrollment

### How It Works

1. **First Login Detection**: `installcheck.sh` checks for marker file at `/usr/local/simplemdm/enroll_marker`
2. **Network Wait**: Script waits for network connectivity (max 100 seconds)
3. **oh-my-zsh Installation**: Installs oh-my-zsh in unattended mode (no shell restart)
4. **Repository Download**: Downloads latest code from GitHub
5. **Main Setup**: Executes `macOSMachineSetup.sh` with all improvements
6. **Completion Marker**: Creates marker file to prevent re-runs
7. **User Notification**: Displays success dialog with log file location

### Log File

All enrollment activity is logged to:
```
/var/log/macos_enrollment.log
```

Each log entry includes a timestamp in format: `[YYYY-MM-DD HH:MM:SS]`

---

## Directory Structure

```
macOS-quick-build/
├── README.md
├── LICENSE
├── macOSMachineSetup.sh          # Main setup script (manual or MDM)
├── autobrew.sh                    # Homebrew installation
├── rosetta-2-install.sh           # Rosetta 2 installation
├── configfiles/
│   ├── Brewfile                   # Package definitions
│   ├── com.apple.dock.plist       # Dock layout
│   └── README.md
└── nopkg_installer/               # SimpleMDM integration
    ├── nopkg-enroll.sh            # Main enrollment orchestrator
    ├── installcheck.sh            # First-run detection
    ├── postinstall.sh             # SimpleMDM postinstall script
    └── nopkg-enroll.pkginfo       # SimpleMDM package definition
```

---

## Customization

### Adding/Removing Packages

Edit `configfiles/Brewfile` to customize installed packages:

```ruby
# Add CLI tools
brew "your-tool-name"

# Add applications
cask "your-app-name"
```

### Modifying Dock Layout

Export your current dock configuration:
```bash
defaults export com.apple.dock ~/Desktop/com.apple.dock.plist
```

Copy the exported file to `configfiles/com.apple.dock.plist`.

## Security Notice

This script modifies system settings including:
- Enabling SSH remote login
- Installing third-party packages via Homebrew
- Modifying sudo authentication (Touch ID)

Review all scripts before running on production systems.

---

## Troubleshooting

### Manual Installation Issues

**Problem**: Homebrew commands not found after installation
- **Solution**: The script now updates PATH automatically. If still having issues, open a new terminal or run: `export PATH="/opt/homebrew/bin:$PATH"` (Apple Silicon) or `export PATH="/usr/local/bin:$PATH"` (Intel)

**Problem**: Script fails with permission errors
- **Solution**: Ensure you're running with sudo privileges. The script will prompt when needed.

### MDM Enrollment Issues

**Problem**: Enrollment not running on first login
- **Solution**: Check SimpleMDM console to verify the package is assigned and installation conditions are met.

**Problem**: Want to re-run enrollment for testing
- **Solution**: Delete the marker file: `sudo rm /usr/local/simplemdm/enroll_marker` and re-run the package.

**Problem**: Need to see what failed
- **Solution**: Check the log file: `cat /var/log/macos_enrollment.log` for timestamped details and error outputs.

---

## Version History

### Version 2.0 (Current)
- Refactored for SimpleMDM nopkg deployment
- Added GitHub-based repository downloading
- Implemented first-run detection with marker files
- Added timestamped logging throughout
- Converted to Brewfile-based package management
- Added comprehensive error tracking and reporting
- Fixed PATH issues for immediate brew command availability
- Unattended oh-my-zsh installation (no shell restart)
- Architecture-aware Homebrew installation
- Custom success notifications

### Version 1.x
- Basic manual installation scripts
- Individual package installation loops
- SimpleMDM integration prototypes

---

## Requirements

- macOS 10.15 (Catalina) or later
- Admin/sudo access
- Active internet connection
- For MDM: SimpleMDM account with nopkg support

---

## Support

For questions or issues:
- Check the log file: `/var/log/macos_enrollment.log` (MDM) or terminal output (manual)
- Review error messages in the setup summary
- Contact your IT support team for assistance

---

## License

See LICENSE file for details.


