#!/bin/bash
# Manual one-liner entry point.
# Downloads the repo and runs the full setup without needing git or a prior clone.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hydramus/macOS-quick-build/main/bootstrap.sh | sudo bash

set -euo pipefail

REPO_URL="https://github.com/Hydramus/macOS-quick-build/archive/refs/heads/main.zip"
WORK_DIR=$(mktemp -d /tmp/macos-setup-XXXXXXXX)

if [[ $EUID -ne 0 ]]; then
    echo "[bootstrap] ERROR: run with sudo — e.g. curl ... | sudo bash"
    rm -rf "$WORK_DIR"
    exit 1
fi

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

chmod +x \
    "${REPO_DIR}/macOSMachineSetup.sh" \
    "${REPO_DIR}/setup-system.sh" \
    "${REPO_DIR}/setup-user.sh" \
    "${REPO_DIR}/autobrew.sh" \
    "${REPO_DIR}/rosetta-2-install.sh" \
    "${REPO_DIR}/lib/common.sh" \
    2>/dev/null || true

echo "[bootstrap] Starting setup..."
"${REPO_DIR}/macOSMachineSetup.sh"
RESULT=$?

rm -rf "$WORK_DIR"
exit $RESULT
