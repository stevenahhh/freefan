#!/bin/bash
set -euo pipefail

# Absolute paths
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_DIR}/build"
SCRATCH_DIR="${BUILD_DIR}/scratch"
BIN_DIR="${SCRATCH_DIR}/release"
BUNDLE_DIR="${BUILD_DIR}/OpenFan.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# The app target carries #Preview harnesses, whose macro plugins only ship with Xcode, so prefer that toolchain
# whenever it is installed and the active developer directory is not already pointing at it.
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app" && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "Using the Xcode toolchain for #Preview support"
fi

# Clean up any previous build
rm -rf "${BUNDLE_DIR}"

# Build both products in release mode
echo "Building OpenFan (app)..."
swift build -c release --scratch-path "${SCRATCH_DIR}" --product OpenFan
echo "PASS: OpenFan built"

echo "Building OpenFanHelper (privileged helper)..."
swift build -c release --scratch-path "${SCRATCH_DIR}" --product OpenFanHelper
echo "PASS: OpenFanHelper built"

# SwiftPM writes release products under the scratch path: <scratch>/release/<product>
for product in OpenFan OpenFanHelper; do
    if [ ! -x "${BIN_DIR}/${product}" ]; then
        echo "FAIL: ${BIN_DIR}/${product} is missing after the release build" >&2
        exit 1
    fi
done

# Create bundle structure
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executables
cp "${BIN_DIR}/OpenFan" "${MACOS_DIR}/"
echo "PASS: OpenFan copied to Contents/MacOS"

cp "${BIN_DIR}/OpenFanHelper" "${RESOURCES_DIR}/"
echo "PASS: OpenFanHelper copied to Contents/Resources"

# Copy install/uninstall scripts
cp "${REPO_DIR}/scripts/install-helper.sh" "${RESOURCES_DIR}/"
cp "${REPO_DIR}/scripts/uninstall-helper.sh" "${RESOURCES_DIR}/"
echo "PASS: Install/uninstall scripts copied to Contents/Resources"

# Copy Info.plist
cp "${REPO_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/"
echo "PASS: Info.plist copied to Contents"

# Sign the helper binary first (nested binary must be signed before the bundle)
codesign --force --sign - --identifier com.stevenahhh.openfan.helper "${RESOURCES_DIR}/OpenFanHelper"
echo "PASS: OpenFanHelper signed with ad-hoc signature"

# Sign the app bundle (after its nested binaries are signed)
codesign --force --sign - --identifier com.stevenahhh.openfan "${BUNDLE_DIR}"
echo "PASS: OpenFan.app bundle signed with ad-hoc signature"

# Verify the signature is valid and strict
codesign --verify --strict "${BUNDLE_DIR}"
echo "PASS: OpenFan.app signature verified (strict)"

# Report final status
BUNDLE_PATH="$(cd "${BUNDLE_DIR}" && pwd)"
APP_SIZE=$(stat -f%z "${MACOS_DIR}/OpenFan")
echo ""
echo "Bundle path: ${BUNDLE_PATH}"
echo "App binary size: ${APP_SIZE} bytes"
