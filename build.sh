#!/bin/bash
# Flatpak build for Claude Desktop using flatpak-builder
# Requires: flatpak, flatpak-builder, 7z (p7zip), node + npx
# Usage: ./build.sh [--no-bundle] [--keep-staging]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}!${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*" >&2; }
section() { echo ""; echo "$*"; }

# ── Constants ─────────────────────────────────────────────────────────────────
APP_ID="com.anthropic.Claude"
RUNTIME_VERSION="24.08"

# Update these when Anthropic releases a new version.
# Find the current installer URL at: https://downloads.claude.ai/releases/win32/x64/latest/
CLAUDE_VERSION="1.3109.0"
EXE_HASH="35cbf6530e05912137624cde0f075dc7f121fa60"
EXE_FILE="Claude-${EXE_HASH}.exe"
EXE_URL="https://downloads.claude.ai/releases/win32/x64/${CLAUDE_VERSION}/${EXE_FILE}"
EXE_SHA256="616a7a1c6235709650b0dabe3a06d32f9ade08340891713bd647dff47065f230"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="${SCRIPT_DIR}/../claude-desktop/build"
ELECTRON_APP_DIR="${STAGING_DIR}/electron-app"
WORK_DIR="${SCRIPT_DIR}/_deb_extract"
BUILD_DIR="${SCRIPT_DIR}/build-dir"
REPO_DIR="${SCRIPT_DIR}/repo"

# ── Flags ─────────────────────────────────────────────────────────────────────
NO_BUNDLE=false
KEEP_STAGING=false
for arg in "$@"; do
    case "$arg" in
        --no-bundle)    NO_BUNDLE=true ;;
        --keep-staging) KEEP_STAGING=true ;;
        --help|-h)
            echo "Usage: $0 [--no-bundle] [--keep-staging]"
            echo "  --no-bundle     Skip flatpak build-bundle (app installed directly via --install)"
            echo "  --keep-staging  Keep ../claude-desktop/build/ after build (useful for debugging)"
            exit 0
            ;;
    esac
done

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    rm -rf "$WORK_DIR"
    if [ "$KEEP_STAGING" = false ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
    exit $exit_code
}
trap cleanup EXIT

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "🔨 Claude Desktop Flatpak Builder (flatpak-builder)"
echo "   App: ${APP_ID}  |  Claude: v${CLAUDE_VERSION}  |  Runtime: ${RUNTIME_VERSION}"
echo ""

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
section "🔍 Checking prerequisites..."

if ! command -v flatpak &>/dev/null; then
    error "flatpak is not installed."
    echo "  Fedora/Bazzite:   sudo dnf install flatpak"
    echo "  Ubuntu/Debian:    sudo apt install flatpak"
    echo "  Arch:             sudo pacman -S flatpak"
    exit 1
fi
info "flatpak: $(flatpak --version)"

if ! command -v flatpak-builder &>/dev/null; then
    error "flatpak-builder is not installed."
    echo "  Bazzite/Fedora (immutable): rpm-ostree install flatpak-builder  (then reboot)"
    echo "  Fedora (mutable):           sudo dnf install flatpak-builder"
    echo "  Ubuntu/Debian:              sudo apt install flatpak-builder"
    echo "  Arch:                       sudo pacman -S flatpak-builder"
    echo ""
    echo "  Alternatively, use ./simple-build.sh which does not require flatpak-builder."
    exit 1
fi
info "flatpak-builder: $(flatpak-builder --version)"

if ! command -v 7z &>/dev/null; then
    error "7z is not installed (needed to extract the Windows installer)."
    echo "  Bazzite/Fedora (immutable): rpm-ostree install p7zip p7zip-plugins  (then reboot)"
    echo "  Fedora (mutable):           sudo dnf install p7zip p7zip-plugins"
    echo "  Ubuntu/Debian:              sudo apt install p7zip-full"
    echo "  Arch:                       sudo pacman -S p7zip"
    exit 1
fi
info "7z: found"

if ! command -v node &>/dev/null || ! command -v npx &>/dev/null; then
    error "node / npx is not installed (needed for asar patching)."
    echo "  Bazzite/Fedora (immutable): toolbox enter && sudo dnf install nodejs npm"
    echo "  Fedora (mutable):           sudo dnf install nodejs npm"
    echo "  Ubuntu/Debian:              sudo apt install nodejs npm"
    echo "  Arch:                       sudo pacman -S nodejs npm"
    exit 1
fi
info "node: $(node --version)"

if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
    error "Neither wget nor curl is installed. Please install one."
    exit 1
fi

# ── 2. Runtimes ───────────────────────────────────────────────────────────────
section "📦 Checking Flatpak runtimes..."

install_runtime_if_missing() {
    local ref="$1"
    local name="${ref%%//*}"
    if ! flatpak list --runtime | grep -qF "$name"; then
        warn "${ref} not found — installing from flathub..."
        flatpak install -y --noninteractive flathub "${ref}" || {
            error "Failed to install ${ref}. Make sure flathub is enabled:"
            echo "  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
            exit 1
        }
    else
        info "${ref} already installed."
    fi
}

install_runtime_if_missing "org.freedesktop.Platform//${RUNTIME_VERSION}"
install_runtime_if_missing "org.freedesktop.Sdk//${RUNTIME_VERSION}"
install_runtime_if_missing "org.electronjs.Electron2.BaseApp//${RUNTIME_VERSION}"

# ── 3. Download Windows installer ────────────────────────────────────────────
section "⬇️  Fetching Claude Desktop v${CLAUDE_VERSION}..."

cd "$SCRIPT_DIR"

if [ -f "$EXE_FILE" ]; then
    info "${EXE_FILE} already downloaded — skipping."
else
    info "Downloading ${EXE_URL} ..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$EXE_FILE" "$EXE_URL" || {
            error "Download failed. Check that the version/URL constants at the top of this script are current."
            rm -f "$EXE_FILE"
            exit 1
        }
    else
        curl -L --progress-bar -o "$EXE_FILE" "$EXE_URL" || {
            error "Download failed. Check that the version/URL constants at the top of this script are current."
            rm -f "$EXE_FILE"
            exit 1
        }
    fi
fi

# Verify checksum
info "Verifying checksum..."
echo "${EXE_SHA256}  ${EXE_FILE}" | sha256sum -c --quiet || {
    error "SHA-256 mismatch — the download may be corrupt or the constants need updating."
    rm -f "$EXE_FILE"
    exit 1
}
info "Checksum OK."

# ── 4. Extract installer → nupkg → app.asar ───────────────────────────────────
section "📂 Extracting installer..."

rm -rf "$WORK_DIR"
mkdir -p "${WORK_DIR}/exe"
cp "$EXE_FILE" "${WORK_DIR}/"
cd "${WORK_DIR}/exe"

info "Extracting NSIS installer with 7z..."
7z x -y "${WORK_DIR}/${EXE_FILE}" > /dev/null

# Find the Squirrel nupkg bundled inside the NSIS installer
NUPKG=$(find . -maxdepth 2 -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG" ]; then
    error "Could not find AnthropicClaude-*.nupkg inside the installer."
    exit 1
fi
info "Found nupkg: $(basename "$NUPKG")"

mkdir -p "${WORK_DIR}/nupkg"
info "Extracting nupkg..."
7z x -y "$NUPKG" -o"${WORK_DIR}/nupkg" > /dev/null

# Locate app.asar (typically at lib/net45/resources/app.asar)
APP_ASAR=$(find "${WORK_DIR}/nupkg" -name "app.asar" | grep -v "unpacked" | head -1)
if [ -z "$APP_ASAR" ]; then
    error "Could not find app.asar inside the nupkg."
    exit 1
fi
APP_ASAR_DIR="$(dirname "$APP_ASAR")"
info "Found app.asar at: ${APP_ASAR}"

# Find icon (search broadly in case filename changes across versions)
ICON_SRC=$(find "${WORK_DIR}/nupkg" -name "*.png" | grep -i "256\|icon\|claude" | head -1)
if [ -z "$ICON_SRC" ]; then
    ICON_SRC=$(find "${WORK_DIR}/nupkg" -name "*.png" | head -1)
fi
if [ -z "$ICON_SRC" ]; then
    error "Could not find an icon in the extracted installer."
    exit 1
fi
info "Found icon: $(basename "$ICON_SRC")"

cd "$SCRIPT_DIR"

# ── 5. Patch app.asar (native module stub) ───────────────────────────────────
section "🔧 Patching app.asar for Linux..."

ASAR_CONTENTS="${WORK_DIR}/app.asar.contents"
PATCHED_ASAR="${WORK_DIR}/app_patched.asar"

info "Extracting app.asar (using npx @electron/asar)..."
npx --yes @electron/asar extract "$APP_ASAR" "$ASAR_CONTENTS"

# Replace the Windows-only native module with a Linux JS stub
STUB_DIR="${ASAR_CONTENTS}/node_modules/@ant/claude-native"
mkdir -p "$STUB_DIR"
cp "${SCRIPT_DIR}/scripts/claude-native-stub.js" "${STUB_DIR}/index.js"
cat > "${STUB_DIR}/package.json" << 'PKGEOF'
{"name":"@ant/claude-native","version":"1.0.0","main":"index.js"}
PKGEOF
info "Native module stub installed."

info "Repacking app.asar..."
# --unpack '**/*.node' keeps native binaries outside the archive so Electron can load them
npx --yes @electron/asar pack "$ASAR_CONTENTS" "$PATCHED_ASAR" --unpack '**/*.node'
info "app.asar repacked."

# ── 6. Stage files for flatpak-builder ───────────────────────────────────────
section "📁 Staging files for flatpak-builder..."

rm -rf "$STAGING_DIR"
mkdir -p "$ELECTRON_APP_DIR"

info "Copying patched app.asar..."
cp "$PATCHED_ASAR" "${ELECTRON_APP_DIR}/app.asar"

# Copy app.asar.unpacked if produced (contains any unpacked .node files)
UNPACKED_DIR="${WORK_DIR}/app_patched.asar.unpacked"
if [ -d "$UNPACKED_DIR" ]; then
    info "Copying app.asar.unpacked/..."
    cp -r "$UNPACKED_DIR" "${ELECTRON_APP_DIR}/app.asar.unpacked"
fi

# Copy resources/ alongside app.asar if present
if [ -d "${APP_ASAR_DIR}/resources" ]; then
    info "Copying resources/..."
    cp -r "${APP_ASAR_DIR}/resources" "$ELECTRON_APP_DIR/"
fi

info "Copying icon..."
cp "$ICON_SRC" "${STAGING_DIR}/claude_6_256x256x32.png"

info "Staging complete: ${STAGING_DIR}"

# ── 7. flatpak-builder ────────────────────────────────────────────────────────
section "🔧 Running flatpak-builder..."

cd "$SCRIPT_DIR"

flatpak-builder \
    --force-clean \
    --user \
    --install \
    "$BUILD_DIR" \
    com.anthropic.Claude.yml

info "Build complete."

# ── 8. Export & bundle ────────────────────────────────────────────────────────
if [ "$NO_BUNDLE" = false ]; then
    section "📤 Exporting to repository..."
    rm -rf "$REPO_DIR"
    flatpak build-export "$REPO_DIR" "$BUILD_DIR"
    info "Repository written to: ${REPO_DIR}"

    section "🎁 Creating claude-desktop.flatpak bundle..."
    flatpak build-bundle "$REPO_DIR" "${SCRIPT_DIR}/claude-desktop.flatpak" "$APP_ID"
    info "Bundle created: claude-desktop.flatpak"
    echo "   Size: $(du -h "${SCRIPT_DIR}/claude-desktop.flatpak" | cut -f1)"
else
    warn "--no-bundle: skipping export and bundle steps."
    warn "App is already installed via --install above."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
if [ "$NO_BUNDLE" = false ]; then
    echo "📦 Created: claude-desktop.flatpak"
    echo ""
    echo "To install on another machine:"
    echo "  flatpak install --user claude-desktop.flatpak"
    echo ""
fi
echo "To update:"
echo "  flatpak update --user ${APP_ID}"
echo "  # or reinstall:"
echo "  flatpak uninstall --user ${APP_ID}"
echo "  flatpak install --user claude-desktop.flatpak"
echo ""
echo "To run:"
echo "  flatpak run ${APP_ID}"
echo ""
