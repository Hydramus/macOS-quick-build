# macOS-quick-build

## MDM-Ready Enrollment (SimpleMDM nopkg)

For MDM deployments, use the new entry-point script: `nonpkg-enroll.sh`.  
This script is designed to be triggered via SimpleMDM's nopkg feature after the first user account is created.  
It automates initial setup tasks such as Homebrew installation, Rosetta 2 setup, and other configuration steps.

**Recommended Usage:**  
- Trigger `nonpkg-enroll.sh` via SimpleMDM nopkg or manually via Software Update after user creation.

---

## Using makepkginfo for SimpleMDM nopkg Integration

To automate enrollment with SimpleMDM, you can use the `makepkginfo` tool to create a nopkg installer package info file.  
This should be done in the new `nopkg_installer` directory.

**Example:**

```sh
makepkginfo --nopkg \
  --name="nopkg-enroll" \
  --displayname="Auto-Enroll via SimpleMDM" \
  --pkgvers="1.0" \
  --installcheck_script=installcheck.sh \
  --postinstall_script=postinstall.sh \
  --unattended_install \
  > nopkg-enroll.pkginfo
```

- Place your `installcheck.sh` and `postinstall.sh` scripts in the `nopkg_installer/` directory.
- The `postinstall.sh` script should trigger `nonpkg-enroll.sh` to run the full enrollment workflow.
- Upload `nopkg-enroll.pkginfo` to SimpleMDM and configure it to run after the first user account is created.

**Directory Structure Example:**

```
macOS-quick-build/
  nonpkg-enroll.sh
  autobrew.sh
  rosetta-2-install.sh
  macOSMachineSetup.sh
  configfiles/
  nopkg_installer/
    installcheck.sh
    postinstall.sh
    nopkg-enroll.pkginfo
```

---

## Script Running Order

1. **nonpkg-enroll.sh**  
   Entry-point for MDM automation. Runs all required setup scripts in order.

2. **autobrew.sh**  
   Installs Homebrew and essential packages.

3. **rosetta-2-install.sh**  
   Installs Rosetta 2 for Apple Silicon compatibility.

4. **macOSMachineSetup.sh**  
   Performs additional macOS configuration and setup tasks.

## Manual Usage

If not using MDM, you can run each script manually in the order listed above.

## Contents

- `nonpkg-enroll.sh` — MDM-ready entry-point script manually or...

### Run these manually individually below for your own preferences.

- `autobrew.sh` — Homebrew installation
- `rosetta-2-install.sh` — Rosetta 2 installation
- `macOSMachineSetup.sh` — Additional macOS setup
- `configfiles/` — Configuration files used by setup scripts
- `nopkg_installer/` — Scripts and pkginfo for SimpleMDM nopkg integration

---
For more details, see comments in each script.

