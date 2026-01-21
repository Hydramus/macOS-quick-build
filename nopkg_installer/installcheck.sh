#!/bin/bash
# Check if enrollment has already been completed (first run only)
MARKER_FILE="/usr/local/simplemdm/enroll_marker"

if [ -f "$MARKER_FILE" ]; then
  # Already enrolled - no need to install
  exit 1
else
  # Not enrolled yet - needs install
  exit 0
fi
