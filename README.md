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
- Installs Homebrew with correct prefix for the architecture

**Phase 2 — User (runs as your account):**
- Installs oh-my-zsh (unattended)
- Adds Homebrew to `~/.zshrc`
- Installs all packages from `configfiles/Brewfile`
- Applies the dock layout from `configfiles/com.apple.dock.plist`

A summary of any failures is printed at the end.

---

## MDM Deployment (SimpleMDM)

Two options are available. Both use `nopkg_installer/enrollment.sh` as the single source of truth.

### Option A — nopkg / Munki

Suitable if you're already using SimpleMDM with Munki.

1. **Update the repo URL** in `nopkg_installer/enrollment.sh` if you've forked the repo:
   ```bash
   REPO_URL="https://github.com/Hydramus/macOS-quick-build/archive/refs/heads/main.zip"
   ```

2. **Generate the pkginfo** from `enrollment.sh`:
   ```bash
   ./nopkg_installer/build-pkginfo.sh
   ```
   This produces `nopkg_installer/nopkg-enroll.pkginfo`. Re-run this whenever `enrollment.sh` changes.

3. **Upload** `nopkg-enroll.pkginfo` to SimpleMDM and assign it to your device group.

On first login, Munki runs the `postinstall_script` (which is `enrollment.sh` verbatim), downloads the repo, and runs the full setup unattended.

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
cask "your-app-name"
```

### Dock layout

Export your current dock and replace the config file:

```bash
defaults export com.apple.dock ~/Desktop/com.apple.dock.plist
cp ~/Desktop/com.apple.dock.plist configfiles/com.apple.dock.plist
```

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
│   ├── Brewfile                    # Package definitions
│   └── com.apple.dock.plist        # Dock layout
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

**Homebrew cask installs prompt for a password**
Ensure you're running `sudo ./macOSMachineSetup.sh` — the orchestrator creates a temporary passwordless sudoers entry for brew during the user phase.

**A step failed — how do I see the full output?**
Each failed step saves its output to a temp file and prints the path. Use `cat /tmp/tmp.XXXXXXXX` to inspect it. For MDM runs, check `/var/log/macos_enrollment.log`.

**MDM enrollment ran but setup didn't complete**
Check `/var/log/macos_enrollment.log`. To re-run: `sudo rm /usr/local/simplemdm/enroll_marker` and redeploy.

---

## Security Notice

This script modifies system-level settings including SSH remote login, sudo authentication (Touch ID), and system hostname. Review all scripts before running on production systems.

---

## License

See LICENSE file for details.
