#!/bin/bash
set -euo pipefail

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Get the UID to authorize (default: SUDO_UID, fallback to argument)
AUTHORIZED_UID="${1:-${SUDO_UID:-}}"
if [[ -z "${AUTHORIZED_UID}" ]]; then
    echo "Error: Could not determine UID to authorize. Pass as argument or set SUDO_UID." >&2
    exit 1
fi

# Constants from Protocol.swift HelperPaths
LABEL="com.stevenahhh.freefan.helper"
SOCKET_PATH="/var/run/com.stevenahhh.freefan.sock"
TOOL_PATH="/Library/PrivilegedHelperTools/com.stevenahhh.freefan.helper"
PLIST_PATH="/Library/LaunchDaemons/com.stevenahhh.freefan.helper.plist"
LOG_PATH="/var/log/com.stevenahhh.freefan.helper.log"

# Helper binary source (default: script's sibling in app bundle Resources)
HELPER_SOURCE="${HELPER_SOURCE:-$(dirname "${BASH_SOURCE[0]}")/FreeFanHelper}"

if [[ ! -f "${HELPER_SOURCE}" ]]; then
    echo "Error: FreeFanHelper not found at ${HELPER_SOURCE}" >&2
    exit 1
fi

# Copy helper binary to privileged location
echo "Installing helper binary to ${TOOL_PATH}..."
cp "${HELPER_SOURCE}" "${TOOL_PATH}"
chown root:wheel "${TOOL_PATH}"
chmod 0755 "${TOOL_PATH}"
echo "PASS: Helper binary installed and set to root:wheel 0755"

# Write the launchd plist
echo "Writing launchd plist to ${PLIST_PATH}..."
cat > "${PLIST_PATH}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TOOL_PATH}</string>
        <string>--allow-uid</string>
        <string>${AUTHORIZED_UID}</string>
        <string>--socket</string>
        <string>${SOCKET_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
</dict>
</plist>
EOF
chown root:wheel "${PLIST_PATH}"
chmod 0644 "${PLIST_PATH}"
echo "PASS: Launchd plist written and set to root:wheel 0644"

# Unload any previous version (tolerate failure)
echo "Unloading any previous daemon..."
launchctl bootout "system/${LABEL}" 2>/dev/null || true
echo "PASS: Bootout completed (failure tolerated)"

# Load the daemon
echo "Loading daemon with launchctl bootstrap..."
launchctl bootstrap system "${PLIST_PATH}"
echo "PASS: Daemon bootstrapped"

# Ensure log file exists with correct permissions
touch "${LOG_PATH}"
chmod 0644 "${LOG_PATH}"
echo "PASS: Log file created at ${LOG_PATH}"

echo ""
echo "Helper installation complete."
