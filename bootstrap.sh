#!/bin/bash
# Manual one-liner entry point.
# Downloads the repo and runs the full setup without needing git or a prior clone.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hydramus/macOS-quick-build/main/bootstrap.sh | sudo bash

set -euo pipefail

REPO_URL="https://github.com/Hydramus/macOS-quick-build/archive/refs/heads/main.zip"
if [[ $EUID -ne 0 ]]; then
    echo "[bootstrap] ERROR: run with sudo — e.g. curl ... | sudo bash"
    exit 1
fi

WORK_DIR=$(mktemp -d /tmp/macos-setup-XXXXXXXX)
# mktemp -d creates with 700 (root-only). The user phase runs as the console
# user via sudo -u, so the directory and its contents must be world-readable.
chmod 755 "$WORK_DIR"

echo "[bootstrap] Downloading macOS Quick Build..."
curl -fsSL "$REPO_URL" -o "${WORK_DIR}/repo.zip"

echo "[bootstrap] Extracting..."
unzip -q "${WORK_DIR}/repo.zip" -d "$WORK_DIR"

REPO_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name "macOS-quick-build-*" | head -n 1)
if [[ -z "$REPO_DIR" ]]; then
    echo "[bootstrap] ERROR: Could not find extracted repo"
    rm -rf "$WORK_DIR"
    exit 1
fi

# Ensure all dirs are traversable and files are readable by the console user.
chmod -R a+rX "$REPO_DIR"
chmod +x \
    "${REPO_DIR}/macOSMachineSetup.sh" \
    "${REPO_DIR}/setup-system.sh" \
    "${REPO_DIR}/setup-user.sh" \
    "${REPO_DIR}/autobrew.sh" \
    "${REPO_DIR}/rosetta-2-install.sh" \
    2>/dev/null || true

echo "[bootstrap] Starting setup..."
"${REPO_DIR}/macOSMachineSetup.sh"
RESULT=$?

rm -rf "$WORK_DIR"
exit $RESULT
