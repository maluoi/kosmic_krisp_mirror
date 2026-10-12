#!/bin/bash
# Download libvulkan_kosmickrisp.dylib from the macOS Vulkan SDK on Linux
# Requires: curl, unzip, 7z (p7zip-full)

set -e

SDK_ZIP_URL="https://sdk.lunarg.com/sdk/download/latest/mac/vulkan_sdk.zip"

# Parse arguments
VERSION_ONLY=false
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
    case $1 in
        --version-only)
            VERSION_ONLY=true
            shift
            ;;
        *)
            OUTPUT_DIR="$1"
            shift
            ;;
    esac
done

# Helper to print messages (to stderr in version-only mode)
log() {
    if [[ "$VERSION_ONLY" == "true" ]]; then
        echo "$@" >&2
    else
        echo "$@"
    fi
}

# Check dependencies
for cmd in curl unzip 7z; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        echo "Install with: sudo apt install p7zip-full curl unzip" >&2
        exit 1
    fi
done

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

log "==> Downloading Vulkan SDK metadata..."
curl -sL -o "$WORKDIR/vulkan_sdk.zip" "$SDK_ZIP_URL"

log "==> Extracting installer..."
unzip -q "$WORKDIR/vulkan_sdk.zip" -d "$WORKDIR/sdk"
rm "$WORKDIR/vulkan_sdk.zip"

# Find the installer.dat
INSTALLER_DAT=$(find "$WORKDIR/sdk" -name "installer.dat" | head -1)
if [[ -z "$INSTALLER_DAT" ]]; then
    echo "Error: Could not find installer.dat" >&2
    exit 1
fi

# As of SDK 1.4.363.0, KosmicKrisp is no longer a separate downloadable
# component; it ships inside the core vulkan.7z, which is embedded directly in
# installer.dat (a Qt resource blob followed by the component archives).

# Read the core component version from the embedded package manifest
KOSMIC_VERSION=$(head -c 65536 "$INSTALLER_DAT" | grep -a -A10 "<Name>com.lunarg.vulkan.core</Name>" | grep -oP '(?<=<Version>)[^<]+' | head -1)
if [[ -z "$KOSMIC_VERSION" ]]; then
    echo "Error: Could not find core component version in installer" >&2
    exit 1
fi

# If --version-only, just output version and exit
if [[ "$VERSION_ONLY" == "true" ]]; then
    echo "$KOSMIC_VERSION"
    exit 0
fi

echo "    KosmicKrisp version: $KOSMIC_VERSION"

# Carve each embedded 7z archive out of installer.dat and keep the one that
# contains KosmicKrisp. Archive size comes from the 7z start header:
# 32 + NextHeaderOffset + NextHeaderSize.
echo "==> Locating KosmicKrisp archive..."
ARCHIVE=""
for OFFSET in $(LC_ALL=C grep -obUaP '7z\xBC\xAF\x27\x1C' "$INSTALLER_DAT" | cut -d: -f1); do
    read -r NEXT_OFFSET NEXT_SIZE < <(od -An -t u8 --endian=little -j $((OFFSET + 12)) -N 16 "$INSTALLER_DAT")
    tail -c +$((OFFSET + 1)) "$INSTALLER_DAT" | head -c $((32 + NEXT_OFFSET + NEXT_SIZE)) > "$WORKDIR/component.7z"
    if 7z l "$WORKDIR/component.7z" 2>/dev/null | grep -q "libvulkan_kosmickrisp.dylib"; then
        ARCHIVE="$WORKDIR/component.7z"
        break
    fi
done
if [[ -z "$ARCHIVE" ]]; then
    echo "Error: Could not find KosmicKrisp archive in installer" >&2
    exit 1
fi

echo "==> Extracting..."
7z x -y -o"$WORKDIR/kosmic" "$ARCHIVE" "*libvulkan_kosmickrisp.dylib" "*kosmickrisp*icd*.json" -r >/dev/null

# Find and copy the dylib
DYLIB=$(find "$WORKDIR/kosmic" -name "libvulkan_kosmickrisp.dylib" | head -1)
if [[ -z "$DYLIB" ]]; then
    echo "Error: Could not find libvulkan_kosmickrisp.dylib in archive"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp "$DYLIB" "$OUTPUT_DIR/"

# Also copy the ICD JSON if present
ICD_JSON=$(find "$WORKDIR/kosmic" -name "*kosmickrisp*icd*.json" 2>/dev/null | head -1)
if [[ -n "$ICD_JSON" ]]; then
    cp "$ICD_JSON" "$OUTPUT_DIR/"
fi

# Copy LICENSE.txt from the installer's Qt resource, where it is stored
# uncompressed with a 4-byte big-endian length prefix
LICENSE_OFFSET=$(LC_ALL=C grep -obUa 'Copyright 20[0-9-]* LunarG' "$INSTALLER_DAT" | head -1 | cut -d: -f1)
if [[ -n "$LICENSE_OFFSET" ]]; then
    LICENSE_SIZE=$(od -An -t u4 --endian=big -j $((LICENSE_OFFSET - 4)) -N 4 "$INSTALLER_DAT" | tr -d ' ')
    tail -c +$((LICENSE_OFFSET + 1)) "$INSTALLER_DAT" | head -c "$LICENSE_SIZE" > "$OUTPUT_DIR/LICENSE.txt"
fi

echo "==> Done!"
ls -lh "$OUTPUT_DIR"/

# Output version for CI usage
echo "$KOSMIC_VERSION" > "$OUTPUT_DIR/VERSION"
