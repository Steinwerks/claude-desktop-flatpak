#!/bin/bash
# Simple Flatpak build for Claude Desktop with bundled Electron
# Does not require flatpak-builder — uses basic flatpak commands instead.
# Requires: flatpak, 7z (p7zip), node + npx, wget or curl, unzip

set -e

echo "🔨 Claude Desktop Flatpak Builder (simple, no flatpak-builder)"
echo ""

APP_ID="com.anthropic.Claude"
RUNTIME_VERSION="24.08"
ELECTRON_VERSION="32.2.0"

# Update these when Anthropic releases a new version.
# Find the current installer URL at: https://downloads.claude.ai/releases/win32/x64/latest/
CLAUDE_VERSION="1.3109.0"
EXE_HASH="35cbf6530e05912137624cde0f075dc7f121fa60"
EXE_FILE="Claude-${EXE_HASH}.exe"
EXE_URL="https://downloads.claude.ai/releases/win32/x64/${CLAUDE_VERSION}/${EXE_FILE}"
EXE_SHA256="616a7a1c6235709650b0dabe3a06d32f9ade08340891713bd647dff47065f230"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/_deb_extract"
BUILD_DIR="simple-build"

# ── Cleanup ───────────────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ── Prerequisites ─────────────────────────────────────────────────────────────
echo "🔍 Checking prerequisites..."

if ! command -v flatpak &>/dev/null; then
    echo "❌ Error: flatpak is not installed."
    echo "  Fedora/Bazzite: sudo dnf install flatpak"
    echo "  Ubuntu/Debian:  sudo apt install flatpak"
    exit 1
fi

if ! command -v 7z &>/dev/null; then
    echo "❌ Error: 7z is not installed (needed to extract the Windows installer)."
    echo "  Bazzite/Fedora (immutable): rpm-ostree install p7zip p7zip-plugins  (then reboot)"
    echo "  Fedora (mutable):           sudo dnf install p7zip p7zip-plugins"
    echo "  Ubuntu/Debian:              sudo apt install p7zip-full"
    echo "  Arch:                       sudo pacman -S p7zip"
    exit 1
fi

if ! command -v node &>/dev/null || ! command -v npx &>/dev/null; then
    echo "❌ Error: node / npx is not installed (needed for asar patching)."
    echo "  Bazzite/Fedora (immutable): toolbox enter && sudo dnf install nodejs npm"
    echo "  Fedora (mutable):           sudo dnf install nodejs npm"
    echo "  Ubuntu/Debian:              sudo apt install nodejs npm"
    exit 1
fi

if ! command -v unzip &>/dev/null; then
    echo "❌ Error: unzip is not installed."
    echo "  Fedora:        sudo dnf install unzip"
    echo "  Ubuntu/Debian: sudo apt install unzip"
    exit 1
fi

if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
    echo "❌ Error: Neither wget nor curl is installed. Please install one."
    exit 1
fi

# ── Runtimes ──────────────────────────────────────────────────────────────────
echo ""
echo "📦 Checking runtimes..."
if ! flatpak list --runtime | grep -qF "org.freedesktop.Platform"; then
    echo "  Installing Platform runtime ${RUNTIME_VERSION}..."
    flatpak install -y --noninteractive flathub org.freedesktop.Platform//${RUNTIME_VERSION}
else
    echo "  ✓ org.freedesktop.Platform already installed."
fi

if ! flatpak list --runtime | grep -qF "org.electronjs.Electron2.BaseApp"; then
    echo "  Installing Electron BaseApp ${RUNTIME_VERSION}..."
    flatpak install -y --noninteractive flathub org.electronjs.Electron2.BaseApp//${RUNTIME_VERSION}
else
    echo "  ✓ org.electronjs.Electron2.BaseApp already installed."
fi

# ── Download Electron ─────────────────────────────────────────────────────────
ELECTRON_FILE="electron-v${ELECTRON_VERSION}-linux-x64.zip"
if [ ! -f "$ELECTRON_FILE" ]; then
    echo ""
    echo "⬇️  Downloading Electron ${ELECTRON_VERSION}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_FILE}"
    else
        curl -L --progress-bar -o "$ELECTRON_FILE" "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_FILE}"
    fi
else
    echo "✓ Electron ${ELECTRON_VERSION} already downloaded."
fi

# ── Download Claude Desktop Windows installer ─────────────────────────────────
cd "$SCRIPT_DIR"
if [ ! -f "$EXE_FILE" ]; then
    echo ""
    echo "⬇️  Downloading Claude Desktop v${CLAUDE_VERSION}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$EXE_FILE" "$EXE_URL"
    else
        curl -L --progress-bar -o "$EXE_FILE" "$EXE_URL"
    fi
else
    echo "✓ ${EXE_FILE} already downloaded."
fi

echo "  Verifying checksum..."
echo "${EXE_SHA256}  ${EXE_FILE}" | sha256sum -c --quiet || {
    echo "❌ SHA-256 mismatch — the download may be corrupt or the constants need updating."
    rm -f "$EXE_FILE"
    exit 1
}
echo "  ✓ Checksum OK."

# ── Extract installer → nupkg → app.asar ─────────────────────────────────────
echo ""
echo "📂 Extracting Claude Desktop installer..."

rm -rf "$WORK_DIR"
mkdir -p "${WORK_DIR}/exe"
cp "$EXE_FILE" "${WORK_DIR}/"
cd "${WORK_DIR}/exe"

echo "  → Extracting NSIS installer with 7z..."
7z x -y "${WORK_DIR}/${EXE_FILE}" > /dev/null

NUPKG=$(find . -maxdepth 2 -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG" ]; then
    echo "❌ Could not find AnthropicClaude-*.nupkg inside the installer."
    exit 1
fi
echo "  → Found nupkg: $(basename "$NUPKG")"

mkdir -p "${WORK_DIR}/nupkg"
echo "  → Extracting nupkg..."
7z x -y "$NUPKG" -o"${WORK_DIR}/nupkg" > /dev/null

APP_ASAR=$(find "${WORK_DIR}/nupkg" -name "app.asar" | grep -v "unpacked" | head -1)
if [ -z "$APP_ASAR" ]; then
    echo "❌ Could not find app.asar inside the nupkg."
    exit 1
fi
echo "  → Found app.asar."

ICON_SRC=$(find "${WORK_DIR}/nupkg" -name "*.png" | grep -i "256\|icon\|claude" | head -1)
[ -z "$ICON_SRC" ] && ICON_SRC=$(find "${WORK_DIR}/nupkg" -name "*.png" | head -1)
if [ -z "$ICON_SRC" ]; then
    echo "❌ Could not find an icon in the extracted installer."
    exit 1
fi
echo "  → Found icon: $(basename "$ICON_SRC")"

cd "$SCRIPT_DIR"

# ── Patch app.asar ────────────────────────────────────────────────────────────
echo ""
echo "🔧 Patching app.asar for Linux..."

ASAR_CONTENTS="${WORK_DIR}/app.asar.contents"
PATCHED_ASAR="${WORK_DIR}/app_patched.asar"

echo "  → Extracting app.asar..."
npx --yes @electron/asar extract "$APP_ASAR" "$ASAR_CONTENTS"

STUB_DIR="${ASAR_CONTENTS}/node_modules/@ant/claude-native"
mkdir -p "$STUB_DIR"
cp "${SCRIPT_DIR}/scripts/claude-native-stub.js" "${STUB_DIR}/index.js"
printf '{"name":"@ant/claude-native","version":"1.0.0","main":"index.js"}' > "${STUB_DIR}/package.json"
echo "  → Native module stub installed."

echo "  → Repacking app.asar..."
npx --yes @electron/asar pack "$ASAR_CONTENTS" "$PATCHED_ASAR" --unpack '**/*.node'
echo "  → app.asar patched."

# ── Initialise Flatpak build dir ──────────────────────────────────────────────
echo ""
echo "📦 Initializing flatpak..."

rm -rf "$BUILD_DIR"
flatpak build-init "$BUILD_DIR" \
    "$APP_ID" \
    org.freedesktop.Sdk \
    org.freedesktop.Platform \
    "$RUNTIME_VERSION" \
    --base=org.electronjs.Electron2.BaseApp \
    --base-version="$RUNTIME_VERSION"

# ── Populate build directory ──────────────────────────────────────────────────
echo ""
echo "📁 Setting up application files..."

mkdir -p "$BUILD_DIR/files/lib/claude-desktop/resources"
mkdir -p "$BUILD_DIR/files/bin"
mkdir -p "$BUILD_DIR/files/share/applications"
mkdir -p "$BUILD_DIR/files/share/icons/hicolor/256x256/apps"
mkdir -p "$BUILD_DIR/files/share/metainfo"

echo "  → Extracting Electron..."
unzip -q "$ELECTRON_FILE" -d "$BUILD_DIR/files/lib/claude-desktop/"

echo "  → Copying patched app.asar..."
cp "$PATCHED_ASAR" "$BUILD_DIR/files/lib/claude-desktop/resources/app.asar"

UNPACKED_DIR="${WORK_DIR}/app_patched.asar.unpacked"
if [ -d "$UNPACKED_DIR" ]; then
    echo "  → Copying app.asar.unpacked/..."
    cp -r "$UNPACKED_DIR" "$BUILD_DIR/files/lib/claude-desktop/resources/app.asar.unpacked"
fi

echo "  → Copying icon..."
cp "$ICON_SRC" "$BUILD_DIR/files/share/icons/hicolor/256x256/apps/${APP_ID}.png"

echo "  → Creating launcher..."
cat > "$BUILD_DIR/files/bin/claude-desktop" << 'EOF'
#!/bin/sh
export TMPDIR="$XDG_RUNTIME_DIR/app/$FLATPAK_ID"
exec zypak-wrapper /app/lib/claude-desktop/electron /app/lib/claude-desktop/resources/app.asar --ozone-platform-hint=auto "$@"
EOF
chmod +x "$BUILD_DIR/files/bin/claude-desktop"

echo "  → Installing desktop file..."
cp "${APP_ID}.desktop" "$BUILD_DIR/files/share/applications/"

echo "  → Installing metainfo..."
cp "${APP_ID}.metainfo.xml" "$BUILD_DIR/files/share/metainfo/"

# ── Finish, export, bundle ────────────────────────────────────────────────────
echo ""
echo "🔧 Finishing build..."

flatpak build-finish "$BUILD_DIR" \
    --share=network \
    --share=ipc \
    --socket=x11 \
    --socket=wayland \
    --socket=pulseaudio \
    --socket=session-bus \
    --device=dri \
    --filesystem=home \
    --filesystem=xdg-config/claude:create \
    --talk-name=org.freedesktop.Notifications \
    --talk-name=org.kde.StatusNotifierWatcher \
    --talk-name=org.freedesktop.portal.FileChooser \
    --command=claude-desktop

echo "📤 Exporting to repository..."
rm -rf repo
flatpak build-export repo "$BUILD_DIR"

echo "🎁 Creating bundle..."
flatpak build-bundle repo claude-desktop.flatpak "$APP_ID"

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 Created: claude-desktop.flatpak"
echo "   Size: $(du -h claude-desktop.flatpak | cut -f1)"
echo ""
echo "To install:"
echo "  flatpak install --user claude-desktop.flatpak"
echo ""
echo "To update your installation:"
echo "  flatpak update --user ${APP_ID}"
echo "  # or reinstall:"
echo "  flatpak uninstall --user ${APP_ID}"
echo "  flatpak install --user claude-desktop.flatpak"
echo ""
echo "To run:"
echo "  flatpak run ${APP_ID}"
echo ""
