#!/bin/bash
# Builds a self-contained .pkg for SimpleMDM deployment.
# The package bundles all setup scripts and a LaunchDaemon that runs enrollment.sh
# on first boot — no GitHub download required at enrollment time.
#
# Prerequisites: pkgbuild (ships with Xcode CLT)
# Usage: ./build-pkg.sh
# Output: pkg_installer/dist/macOS-QuickBuild-<date>.pkg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${SCRIPT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/payload"
PKG_SCRIPTS_DIR="${BUILD_DIR}/scripts"
DIST_DIR="${SCRIPT_DIR}/dist"

INSTALL_PATH="/usr/local/macOS-quick-build"
LAUNCHDAEMON_LABEL="com.macosquickbuild.enrollment"
LAUNCHDAEMON_PLIST="${SCRIPT_DIR}/payload/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"

PKG_IDENTIFIER="com.macosquickbuild.pkg"
PKG_VERSION="$(date '+%Y.%m.%d')"
PKG_NAME="macOS-QuickBuild-${PKG_VERSION}.pkg"

echo "============================================"
echo "Building macOS Quick Build enrollment pkg"
echo "Version: $PKG_VERSION"
echo "============================================"
echo ""

# ============================================
# Prepare build tree
# ============================================
rm -rf "$BUILD_DIR"
mkdir -p "${PAYLOAD_DIR}${INSTALL_PATH}"
mkdir -p "${PAYLOAD_DIR}/Library/LaunchDaemons"
mkdir -p "$PKG_SCRIPTS_DIR"
mkdir -p "$DIST_DIR"

# ============================================
# Copy scripts into payload
# ============================================
for script in macOSMachineSetup.sh setup-system.sh setup-user.sh autobrew.sh rosetta-2-install.sh; do
    cp "${REPO_DIR}/${script}" "${PAYLOAD_DIR}${INSTALL_PATH}/"
    chmod +x "${PAYLOAD_DIR}${INSTALL_PATH}/${script}"
done

cp "${REPO_DIR}/nopkg_installer/enrollment.sh" "${PAYLOAD_DIR}${INSTALL_PATH}/"
chmod +x "${PAYLOAD_DIR}${INSTALL_PATH}/enrollment.sh"

cp -r "${REPO_DIR}/lib"         "${PAYLOAD_DIR}${INSTALL_PATH}/"
cp -r "${REPO_DIR}/configfiles" "${PAYLOAD_DIR}${INSTALL_PATH}/"

# ============================================
# Copy LaunchDaemon plist into payload
# ============================================
cp "$LAUNCHDAEMON_PLIST" "${PAYLOAD_DIR}/Library/LaunchDaemons/"

# ============================================
# pkg postinstall: loads the LaunchDaemon so enrollment runs immediately
# ============================================
cat > "${PKG_SCRIPTS_DIR}/postinstall" << 'POSTINSTALL'
#!/bin/bash
# Load the LaunchDaemon so enrollment starts right after pkg installation.
/bin/launchctl load /Library/LaunchDaemons/com.macosquickbuild.enrollment.plist 2>/dev/null || true
exit 0
POSTINSTALL
chmod +x "${PKG_SCRIPTS_DIR}/postinstall"

# ============================================
# Build
# ============================================
echo "Running pkgbuild..."
pkgbuild \
    --root        "$PAYLOAD_DIR" \
    --scripts     "$PKG_SCRIPTS_DIR" \
    --identifier  "$PKG_IDENTIFIER" \
    --version     "$PKG_VERSION" \
    "${DIST_DIR}/${PKG_NAME}"

echo ""
echo "============================================"
echo "Package ready: ${DIST_DIR}/${PKG_NAME}"
echo "============================================"
echo ""
echo "Deploy via SimpleMDM:"
echo "  1. Apps → Custom Apps → Upload ${PKG_NAME}"
echo "  2. Assign to your device group"
echo "  3. On first boot after MDM enrollment the LaunchDaemon fires"
echo "     and runs enrollment.sh — no user interaction required."
echo ""
echo "The nopkg/Munki flow (nopkg-enroll.pkginfo) is still supported"
echo "as an alternative; both use the same enrollment.sh source."
