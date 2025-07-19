#!/bin/bash
# Detect if Homebrew or SimpleMDM bootstrap hasn’t been applied
if [ ! -x /opt/homebrew/bin/brew ] || [ ! -f /usr/local/simplemdm/enroll_marker ]; then
  exit 0  # Needs install
else
  exit 1  # Up to date
fi
