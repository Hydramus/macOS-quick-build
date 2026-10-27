#!/bin/bash
# macOS Enrollment Script — single authoritative source for MDM deployment.
# Used by both the nopkg/Munki flow and the LaunchDaemon pkg flow.
# The nopkg pkginfo is generated from this file via build-pkginfo.sh.
#
# Nothing is downloaded at run time. The scripts are either bundled on disk
# (LaunchDaemon pkg) or embedded below as a tarball by build-pkginfo.sh (nopkg).

set -euo pipefail

# ===== Configuration =====
consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
UNAME_MACHINE="$(uname -m)"
HOMEBREW_PREFIX="/usr/local"
[[ "$UNAME_MACHINE" == "arm64" ]] && HOMEBREW_PREFIX="/opt/homebrew"

LOGFILE="/var/log/macos_enrollment.log"
MARKER_FILE="/usr/local/simplemdm/enroll_marker"
WORK_DIR="/tmp/macos-setup-$$"

# If the pkg installer bundled scripts here, use them.
BUNDLED_SETUP="/usr/local/macOS-quick-build/macOSMachineSetup.sh"
# Otherwise this base64 tar.gz of the repo, filled in by build-pkginfo.sh.
PAYLOAD="__PAYLOAD__"
REPO_DIR=""

# ===== Logging =====
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }

# ===== Steps =====

check_first_run() {
    if [ -f "$MARKER_FILE" ]; then
        log "Already enrolled (marker: $MARKER_FILE). Exiting."
        exit 0
    fi
    log "First run — starting enrollment."
    mkdir -p "$(dirname "$MARKER_FILE")"
}

# At the login window or in Setup Assistant there is no user to set up.
# Exit non-zero without the marker so Munki (or the LaunchDaemon) tries again.
check_console_user() {
    if [[ -z "$consoleuser" || "$consoleuser" == "root" || "$consoleuser" == "_mbsetupuser" ]]; then
        log "No user logged in yet — will try again on the next run."
        exit 1
    fi
}

wait_for_network() {
    local max_wait=20 count=1
    log "Waiting for network..."
    while [[ $(ifconfig -a inet 2>/dev/null | sed -n -e '/127.0.0.1/d' -e '/0.0.0.0/d' -e '/inet/p' | wc -l) -lt 1 ]]; do
        if [[ $count -gt $max_wait ]]; then
            log "ERROR: No network after $max_wait attempts."
            exit 1
        fi
        log "Network wait: attempt $count/$max_wait"
        sleep 5
        (( count++ ))
    done
    log "Network connected."
}

get_repo() {
    if [ -f "$BUNDLED_SETUP" ]; then
        log "Using bundled scripts at $(dirname "$BUNDLED_SETUP")"
        REPO_DIR="$(dirname "$BUNDLED_SETUP")"
        return 0
    fi

    # A filled-in payload is long; the placeholder is 11 characters
    if [[ ${#PAYLOAD} -lt 100 ]]; then
        log "ERROR: No bundled scripts and no embedded payload. Build the pkginfo with build-pkginfo.sh."
        exit 1
    fi
    REPO_DIR="$WORK_DIR/macOS-quick-build"
    mkdir -p "$REPO_DIR"
    if ! echo "$PAYLOAD" | base64 -D | tar -xzf - -C "$REPO_DIR"; then
        log "ERROR: Could not unpack the embedded payload"
        exit 1
    fi
    log "Embedded payload unpacked to: $REPO_DIR"
}

run_setup() {
    cd "$REPO_DIR"
    chmod +x ./macOSMachineSetup.sh ./setup-system.sh ./setup-user.sh ./autobrew.sh ./rosetta-2-install.sh 2>/dev/null || true
    log "================================================"
    log "Running macOSMachineSetup.sh ..."
    if ./macOSMachineSetup.sh 2>&1 | tee -a "$LOGFILE"; then
        log "macOSMachineSetup.sh completed successfully."
    else
        log "WARNING: macOSMachineSetup.sh finished with errors — check $LOGFILE"
    fi
    log "================================================"
}

create_marker() {
    echo "Enrollment completed at $(date)" > "$MARKER_FILE"
    log "Marker written: $MARKER_FILE"
}

cleanup() {
    rm -rf "$WORK_DIR" 2>/dev/null || true
    log "Cleanup done."
}

show_success_popup() {
    su -l "$consoleuser" -c "osascript <<EOD
tell application \"System Events\"
  display dialog \"Mac setup complete!\n\n Log: $LOGFILE\n\nQuestions? Contact IT Support.\" buttons {\"OK\"} default button 1 with title \"Setup Complete\" with icon note
end tell
EOD" 2>&1 | tee -a "$LOGFILE" || true
}

# ===== Main =====
log "========================================"
log "Enrollment started | user: $consoleuser | arch: $UNAME_MACHINE"
log "========================================"

check_first_run
check_console_user
wait_for_network
get_repo
run_setup
create_marker
cleanup
show_success_popup

log "========================================"
log "Enrollment complete."
log "========================================"
exit 0
