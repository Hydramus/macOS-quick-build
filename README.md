# macOS-quick-build

Automated macOS setup and configuration toolkit for both manual installation and MDM-based deployment (SimpleMDM).

---

## Manual Installation

### Option A — One-liner (no git required)

The fastest way to set up a fresh Mac. Run this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Hydramus/macOS-quick-build/main/bootstrap.sh | sudo bash
```

This downloads the repo, makes everything executable, and runs the full setup automatically. No cloning, no extra steps.

### Option B — From a local clone

If you have the repo already:

```bash
git clone https://github.com/Hydramus/macOS-quick-build.git
cd macOS-quick-build
sudo ./macOSMachineSetup.sh
```

### Prerequisites

- macOS 12 (Monterey) or later
- Admin/sudo access
- Internet connection

### What happens

Setup runs in two phases:

**Phase 1 — System (root):**
- Installs Xcode Command Line Tools (automated, no GUI prompt)
- Accepts Xcode license
- Installs Rosetta 2 on Apple Silicon
- Enables SSH remote login
- Sets hostname to `HL-<serial-number>`
- Enables Touch ID for sudo
- Turns off Chrome telemetry (managed policy)
- Installs Homebrew with correct prefix for the architecture

**Phase 2 — User (runs as your account, no sudo):**
- Installs oh-my-zsh (unattended)
- Adds Homebrew to `~/.zshrc`
- Installs the command line tools from `configfiles/Brewfile`
- Sets Chrome as the default browser, if Chrome is already installed
- Applies the dock layout from `configfiles/com.apple.dock.plist`

GUI apps are not in the Brewfile: install them with your MDM (for example Munki NoPkgs that call Installomator), which runs as root and needs no user password.

A summary of any failures is printed at the end.

---

## MDM Deployment (SimpleMDM)

Two options are available. Both use `nopkg_installer/enrollment.sh` as the single source of truth.

### Option A — nopkg / Munki

Suitable if you're already using SimpleMDM with Munki.

1. **Commit** your changes, then **generate the pkginfo**:
   ```bash
   ./nopkg_installer/build-pkginfo.sh
   ```
   This produces `nopkg_installer/nopkg-enroll.pkginfo`, with the setup scripts from `HEAD` embedded as a base64 tarball. It refuses to build from uncommitted changes. Re-run it after every change.

2. **Upload** `nopkg-enroll.pkginfo` to SimpleMDM and assign it to a group that holds only new Macs (it resets the Dock, so keep it away from Macs already in use).

Munki runs the `postinstall_script` (`enrollment.sh` with the payload), unpacks the embedded scripts and runs the full setup unattended. Nothing is downloaded from GitHub, so a change to this repo reaches a Mac only when you rebuild and re-upload. If no one is logged in yet, it exits without the marker and Munki tries again on its next run.

### Option B — Self-contained pkg (LaunchDaemon)

Bundles all scripts into a signed `.pkg`. No GitHub download at enrollment time — useful when you want offline-capable deployment or don't want to rely on Munki.

1. **Build the pkg** (requires Xcode CLT):
   ```bash
   ./pkg_installer/build-pkg.sh
   ```
   Output: `pkg_installer/dist/macOS-QuickBuild-<date>.pkg`

2. **Sign the pkg** — SimpleMDM requires a valid Developer ID signature before it will deploy a pkg:
   ```bash
   productsign --sign "Developer ID Installer: Your Name (TEAMID)" \
     pkg_installer/dist/macOS-QuickBuild-<date>.pkg \
     pkg_installer/dist/macOS-QuickBuild-<date>-signed.pkg
   ```
   You'll need a **Developer ID Installer** certificate in your keychain (available via Apple Developer Portal). To list available signing identities: `security find-identity -v -p basic`

3. **Upload** the signed pkg to SimpleMDM under **Apps → Custom Apps**.

4. **Assign** it to your device group.

On first boot after MDM enrollment, the pkg's `postinstall` loads a LaunchDaemon that runs `enrollment.sh`. The script uses the bundled scripts directly — no network download needed before setup begins.

### Enrollment log

All MDM enrollment activity is written to:
```
/var/log/macos_enrollment.log
```

### Re-running enrollment (for testing)

```bash
sudo rm /usr/local/simplemdm/enroll_marker
```

Then re-run the package from SimpleMDM or trigger `enrollment.sh` directly.

---

## Customization

### Packages

Edit `configfiles/Brewfile`:

```ruby
brew "your-cli-tool"
```

Keep it to formulae. Casks often run their own `sudo` installer, which an unattended run can't answer.

### Dock layout

The plist is XML, with `__HOME__` where the user's home folder goes (`setup-user.sh` fills it in). To change it, export a Dock and convert it:

```bash
defaults export com.apple.dock ~/Desktop/com.apple.dock.plist
plutil -convert xml1 ~/Desktop/com.apple.dock.plist
```

Then remove the `book`, `file-mod-date` and `parent-mod-date` keys and `recent-apps` (they hold the original user's paths), replace `/Users/<you>` with `__HOME__`, and copy it to `configfiles/com.apple.dock.plist`.

---

## Directory Structure

```
macOS-quick-build/
├── bootstrap.sh                    # One-liner manual entry point
├── macOSMachineSetup.sh            # Orchestrator (calls both phases)
├── setup-system.sh                 # Phase 1: root-level operations
├── setup-user.sh                   # Phase 2: user-level operations
├── autobrew.sh                     # Homebrew installation
├── rosetta-2-install.sh            # Rosetta 2 installation
├── lib/
│   └── common.sh                   # Shared utilities (logging, error tracking)
├── configfiles/
│   ├── Brewfile                    # Command line tools
│   └── com.apple.dock.plist        # Dock layout (XML template)
├── nopkg_installer/                # SimpleMDM nopkg/Munki flow
│   ├── enrollment.sh               # Single source for MDM enrollment logic
│   ├── build-pkginfo.sh            # Generates pkginfo from enrollment.sh
│   ├── nopkg-enroll.pkginfo.template
│   ├── nopkg-enroll.pkginfo        # Generated — upload this to SimpleMDM
│   └── installcheck.sh             # First-run detection
└── pkg_installer/                  # LaunchDaemon pkg flow
    ├── build-pkg.sh                # Builds the self-contained .pkg
    └── payload/
        └── Library/LaunchDaemons/
            └── com.macosquickbuild.enrollment.plist
```

---

## Troubleshooting

**Script fails: "Could not determine console user"**
Run with `sudo ./macOSMachineSetup.sh`, not as `sudo -i` or in a root shell where `$SUDO_USER` is not set.

**Xcode CLT install hangs or fails**
On a fresh Mac, `softwareupdate` sometimes needs a moment after first boot. Re-run the script. In an MDM context, the script will exit cleanly with an error rather than hanging on a GUI dialog.

**A cask you added prompts for a password**
The user phase has no sudo. Install that app with your MDM instead, or run the cask by hand.

**A step failed — how do I see the full output?**
Every `print_status`/`track_failure` call (in every script that sources `lib/common.sh`) is appended to `/var/log/macos_quick_build.log`, timestamped, so failures survive after the terminal output scrolls away. For MDM runs, also check `/var/log/macos_enrollment.log`.

**MDM enrollment ran but setup didn't complete**
Check `/var/log/macos_enrollment.log`. To re-run: `sudo rm /usr/local/simplemdm/enroll_marker` and redeploy.

---

## Security Notice

This script modifies system-level settings including SSH remote login, sudo authentication (Touch ID), and system hostname. Review all scripts before running on production systems.

The MDM flow runs as root but downloads no code: the scripts are embedded in the pkginfo (nopkg) or the pkg. The one-liner in Manual Installation does download `main`, so only use it where you trust the current state of the repo. Earlier versions granted the console user temporary `NOPASSWD: ALL` sudo for cask installs; that is gone. If an old run was interrupted, check `/etc/sudoers.d/` for a leftover `brew_temp_*` file and remove it.

---

## License

See LICENSE file for details.
