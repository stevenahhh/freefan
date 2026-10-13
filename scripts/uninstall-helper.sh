#!/bin/bash
set -euo pipefail

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Constants from Protocol.swift HelperPaths
LABEL="com.stevenahhh.openfan.helper"
SOCKET_PATH="/var/run/com.stevenahhh.openfan.sock"
TOOL_PATH="/Library/PrivilegedHelperTools/com.stevenahhh.openfan.helper"
PLIST_PATH="/Library/LaunchDaemons/com.stevenahhh.openfan.helper.plist"

echo "Unloading daemon..."
launchctl bootout "system/${LABEL}" 2>/dev/null || true
echo "PASS: Daemon unloaded (failure tolerated)"

if [[ -f "${PLIST_PATH}" ]]; then
    echo "Removing plist..."
    rm "${PLIST_PATH}"
    echo "PASS: Plist removed"
fi

if [[ -f "${TOOL_PATH}" ]]; then
    echo "Removing helper binary..."
    rm "${TOOL_PATH}"
    echo "PASS: Helper binary removed"
fi

rm -f "${TOOL_PATH}.revision"

if [[ -S "${SOCKET_PATH}" ]]; then
    echo "Removing socket..."
    rm "${SOCKET_PATH}"
    echo "PASS: Socket removed"
fi

echo ""
echo "Helper uninstallation complete."
