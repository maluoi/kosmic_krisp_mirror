#!/bin/bash
# Download libvulkan_kosmickrisp.dylib from the macOS Vulkan SDK on Linux
# Requires: curl, 7z (p7zip-full)

set -e

SDK_ZIP_URL="https://sdk.lunarg.com/sdk/download/latest/mac/vulkan_sdk.zip"
REPO_BASE="https://vulkan.lunarg.com/sdk/installer/mac"

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
for cmd in curl 7z; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        echo "Install with: sudo apt install p7zip-full curl" >&2
        exit 1
    fi
done

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

log "==> Downloading Vulkan SDK metadata..."
curl -sL -o "$WORKDIR/vulkan_sdk.zip" "$SDK_ZIP_URL"

log "==> Extracting installer..."
unzip -q "$WORKDIR/vulkan_sdk.zip" -d "$WORKDIR/sdk"

# Find the installer.dat and extract repository URL
INSTALLER_DAT=$(find "$WORKDIR/sdk" -name "installer.dat" | head -1)
if [[ -z "$INSTALLER_DAT" ]]; then
    echo "Error: Could not find installer.dat" >&2
    exit 1
fi

# Extract repository URL from installer.dat
REPO_URL=$(strings "$INSTALLER_DAT" | grep -oE 'https://sdk\.lunarg\.com/sdk/installer/mac/[^<]+' | head -1)
if [[ -z "$REPO_URL" ]]; then
    echo "Error: Could not find repository URL in installer" >&2
    exit 1
fi
log "    Found repository: $REPO_URL"

# Fetch Updates.xml to get component details
log "==> Fetching component manifest..."
curl -sL "$REPO_URL/Updates.xml" -o "$WORKDIR/Updates.xml"

# Extract KosmicKrisp version and archive name
KOSMIC_VERSION=$(grep -A10 "com.lunarg.vulkan.kosmic" "$WORKDIR/Updates.xml" | grep -oP '(?<=<Version>)[^<]+' | head -1)
KOSMIC_ARCHIVE=$(grep -A10 "com.lunarg.vulkan.kosmic" "$WORKDIR/Updates.xml" | grep -oP '(?<=<DownloadableArchives>)[^<]+' | head -1)

if [[ -z "$KOSMIC_VERSION" || -z "$KOSMIC_ARCHIVE" ]]; then
    echo "Error: Could not find KosmicKrisp component in manifest" >&2
    exit 1
fi

# If --version-only, just output version and exit
if [[ "$VERSION_ONLY" == "true" ]]; then
    echo "$KOSMIC_VERSION"
    exit 0
fi

echo "    KosmicKrisp version: $KOSMIC_VERSION"

# Convert sdk.lunarg.com to vulkan.lunarg.com (follows redirect)
DOWNLOAD_BASE="${REPO_URL/sdk.lunarg.com/vulkan.lunarg.com}"
KOSMIC_URL="$DOWNLOAD_BASE/com.lunarg.vulkan.kosmic/${KOSMIC_VERSION}${KOSMIC_ARCHIVE}"
META_URL="$DOWNLOAD_BASE/com.lunarg.vulkan.kosmic/${KOSMIC_VERSION}meta.7z"

echo "==> Downloading KosmicKrisp..."
curl -sL -o "$WORKDIR/kosmickrisp.7z" "$KOSMIC_URL"
curl -sL -o "$WORKDIR/meta.7z" "$META_URL"

echo "==> Extracting..."
7z x -y -o"$WORKDIR/kosmic" "$WORKDIR/kosmickrisp.7z" >/dev/null
7z x -y -o"$WORKDIR/meta" "$WORKDIR/meta.7z" >/dev/null

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

# Copy LICENSE.txt from meta archive
LICENSE=$(find "$WORKDIR/meta" -name "LICENSE.txt" | head -1)
if [[ -n "$LICENSE" ]]; then
    cp "$LICENSE" "$OUTPUT_DIR/"
fi

echo "==> Done!"
ls -lh "$OUTPUT_DIR"/

# Output version for CI usage
echo "$KOSMIC_VERSION" > "$OUTPUT_DIR/VERSION"
