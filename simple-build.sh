#!/bin/bash
# Simple Flatpak build for Claude Desktop with bundled Electron
# Does not require flatpak-builder — uses basic flatpak commands instead.
# Requires: flatpak, 7z (7zip), node + npx, wget or curl, unzip

set -e

echo "🔨 Claude Desktop Flatpak Builder (simple, no flatpak-builder)"
echo ""

APP_ID="com.anthropic.Claude"
RUNTIME_VERSION="24.08"
ELECTRON_VERSION="32.2.0"

# Update these when Anthropic releases a new version.
# Check what's current with:  ./simple-build.sh --check-version
#
# Pinned to 1.3109.0 deliberately. 1.24012.9 does not start under this flatpak:
# Chromium and Wayland init fine, then the app dies before its own bootstrap —
# it never writes a byte to its userData dir (no main.log, no config touch) and
# raises no exception on stdout. Symptom is a tray icon that flashes a window
# and retreats. Verify any newer version actually launches before bumping this.
# Both can be overridden from the environment to test another release without
# editing this file, e.g.
#   CLAUDE_VERSION=1.3109.0 NUPKG_SHA256=<sha> ./simple-build.sh
CLAUDE_VERSION="${CLAUDE_VERSION:-1.3109.0}"
NUPKG_SHA256="${NUPKG_SHA256:-1f0fcb6ff5831ad158f1801f67a771a94ecbaf65c61a2b68538866088660cd7a}"

# Squirrel.Windows release feed. RELEASES lists the current package as
# "<SHA-1> AnthropicClaude-<version>-full.nupkg <bytes>". The .nupkg is the
# payload — it can be fetched directly, so there is no need for the NSIS .exe
# (whose Claude-<sha1>.exe filename is not derivable from any manifest).
RELEASES_URL="https://downloads.claude.ai/releases/win32/x64/RELEASES"
NUPKG_FILE="AnthropicClaude-${CLAUDE_VERSION}-full.nupkg"
NUPKG_URL="https://downloads.claude.ai/releases/win32/x64/${NUPKG_FILE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/_deb_extract"
BUILD_DIR="simple-build"

# Latest version advertised by the release feed (RELEASES carries a UTF-8 BOM).
resolve_latest_version() {
    curl -fsSL "$RELEASES_URL" \
        | sed 's/^\xef\xbb\xbf//' \
        | awk '{print $2}' \
        | sed -n 's/^AnthropicClaude-\(.*\)-full\.nupkg$/\1/p' \
        | tail -1
}

if [ "${1:-}" = "--check-version" ]; then
    latest="$(resolve_latest_version)"
    echo "  pinned:  ${CLAUDE_VERSION}"
    if [ -z "$latest" ]; then
        echo "  current: could not read ${RELEASES_URL}"
        exit 1
    fi
    echo "  current: ${latest}"
    if [ "$latest" = "$CLAUDE_VERSION" ]; then
        echo "  ✓ up to date."
    else
        echo ""
        echo "  A newer version is available. To update, set in this script:"
        echo "    CLAUDE_VERSION=\"${latest}\""
        echo "  then get the checksum for the new pin with:"
        echo "    curl -fsSL https://downloads.claude.ai/releases/win32/x64/AnthropicClaude-${latest}-full.nupkg | sha256sum"
    fi
    exit 0
fi

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
    echo "  Bazzite:        already in the base image — nothing to install."
    echo "  Fedora:         sudo dnf install 7zip  (p7zip was retired)"
    echo "  Ubuntu/Debian:  sudo apt install p7zip-full"
    echo "  Arch:           sudo pacman -S p7zip"
    exit 1
fi

if ! command -v node &>/dev/null || ! command -v npx &>/dev/null; then
    echo "❌ Error: node / npx is not installed (needed for asar patching)."
    echo "  Bazzite (immutable — no layering or reboot needed):"
    echo "    curl -LO https://nodejs.org/dist/v24.18.1/node-v24.18.1-linux-x64.tar.xz"
    echo "    mkdir -p ~/.local/opt && tar xf node-v24.18.1-linux-x64.tar.xz -C ~/.local/opt"
    echo "    export PATH=\"\$HOME/.local/opt/node-v24.18.1-linux-x64/bin:\$PATH\""
    echo "  Fedora (mutable):  sudo dnf install nodejs npm"
    echo "  Ubuntu/Debian:     sudo apt install nodejs npm"
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

# Prefer a user-scope install (no polkit prompt), but only if the user
# installation actually has a flathub remote to pull from.
if flatpak remotes --user --columns=name 2>/dev/null | grep -qx "flathub"; then
    SCOPE="--user"
elif flatpak remotes --system --columns=name 2>/dev/null | grep -qx "flathub"; then
    SCOPE="--system"
    echo "  ℹ No user-scope flathub remote; using the system one (expect a polkit prompt)."
    echo "    To avoid that: flatpak remote-add --if-not-exists --user flathub \\"
    echo "                     https://flathub.org/repo/flathub.flatpakrepo"
else
    echo "❌ Error: no 'flathub' remote is configured."
    echo "  flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo"
    exit 1
fi

# Checks the exact branch, in any installation — `flatpak list | grep <name>`
# would match a different runtime version and silently skip the install.
ensure_ref() {
    local ref="$1"
    if flatpak info "$ref" &>/dev/null; then
        echo "  ✓ ${ref} already installed."
    else
        echo "  Installing ${ref}..."
        flatpak install -y --noninteractive $SCOPE flathub "$ref"
    fi
}

# build-init needs the Sdk present too, not just the Platform.
ensure_ref "org.freedesktop.Platform//${RUNTIME_VERSION}"
ensure_ref "org.freedesktop.Sdk//${RUNTIME_VERSION}"
ensure_ref "org.electronjs.Electron2.BaseApp//${RUNTIME_VERSION}"

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

# ── Download Claude Desktop package ──────────────────────────────────────────
cd "$SCRIPT_DIR"
if [ ! -f "$NUPKG_FILE" ]; then
    echo ""
    echo "⬇️  Downloading Claude Desktop v${CLAUDE_VERSION}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$NUPKG_FILE" "$NUPKG_URL" || {
            echo "❌ Download failed. Check the current version with: $0 --check-version"
            rm -f "$NUPKG_FILE"
            exit 1
        }
    else
        curl -fL --progress-bar -o "$NUPKG_FILE" "$NUPKG_URL" || {
            echo "❌ Download failed. Check the current version with: $0 --check-version"
            rm -f "$NUPKG_FILE"
            exit 1
        }
    fi
else
    echo "✓ ${NUPKG_FILE} already downloaded."
fi

echo "  Verifying checksum..."
echo "${NUPKG_SHA256}  ${NUPKG_FILE}" | sha256sum -c --quiet || {
    echo "❌ SHA-256 mismatch — the download may be corrupt or the constants need updating."
    rm -f "$NUPKG_FILE"
    exit 1
}
echo "  ✓ Checksum OK."

# ── Extract nupkg → app.asar ─────────────────────────────────────────────────
echo ""
echo "📂 Extracting Claude Desktop package..."

rm -rf "$WORK_DIR"
mkdir -p "${WORK_DIR}/nupkg"
7z x -y "$NUPKG_FILE" -o"${WORK_DIR}/nupkg" > /dev/null

APP_ASAR=$(find "${WORK_DIR}/nupkg" -name "app.asar" | grep -v "unpacked" | head -1)
if [ -z "$APP_ASAR" ]; then
    echo "❌ Could not find app.asar inside the nupkg."
    exit 1
fi
echo "  → Found app.asar."

# The only real app icon (256x256) is the one embedded in claude.exe. Every PNG
# shipped loose in the package is a 24-72px tray glyph, so a naive *.png search
# yields a monochrome tray icon scaled up into the app menu.
ICON_SIZE=256
ICON_SRC=""
CLAUDE_EXE=$(find "${WORK_DIR}/nupkg" -iname "claude.exe" | head -1)
if [ -n "$CLAUDE_EXE" ] && command -v wrestool &>/dev/null && command -v icotool &>/dev/null; then
    if wrestool -x -t 14 "$CLAUDE_EXE" > "${WORK_DIR}/app.ico" 2>/dev/null; then
        IDX=$(icotool -l "${WORK_DIR}/app.ico" 2>/dev/null \
              | grep -- "--width=256" | grep -o -- "--index=[0-9]*" | head -1 | cut -d= -f2)
        if [ -n "$IDX" ] && icotool -x -i "$IDX" -o "${WORK_DIR}/icon-256.png" "${WORK_DIR}/app.ico" 2>/dev/null; then
            ICON_SRC="${WORK_DIR}/icon-256.png"
            echo "  → Extracted 256x256 icon from claude.exe."
        fi
    fi
fi

if [ -z "$ICON_SRC" ]; then
    # icoutils missing, or the layout changed: fall back to the Linux tray icon,
    # installed at its real size so the desktop does not upscale it.
    ICON_SRC=$(find "${WORK_DIR}/nupkg" -name "TrayIconLinux.png" | head -1)
    ICON_SIZE=64
    echo "  ! Using the 64x64 tray icon (install 'icoutils' for the full-size app icon)."
fi
if [ -z "$ICON_SRC" ]; then
    echo "❌ Could not find an icon in the package."
    exit 1
fi

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

# The main window is frameless (titleBarStyle:"hidden") on the assumption that
# the app draws its own window controls — which it only does on Windows, via
# titleBarOverlay. On Linux that leaves no title bar at all, and the app's own
# drag strip (.nc-drag, pinned across the top) sits over the nav icons, so
# clicking them drags the window instead of activating them.
#
# Two changes, and they belong together:
#   1. Give the window a real native title bar, so it can still be moved and
#      closed. titleBarOverlay is dropped with it — it is only meaningful
#      alongside titleBarStyle:"hidden".
#   2. Make the app's internal drag strip inert, so it stops swallowing clicks.
#      Dragging moves to the native title bar from (1).
#
# The Quick Entry overlay also uses titleBarStyle:"hidden" and must stay
# frameless, so anchor on the main window's unique minWidth/minHeight.
echo "  → Patching window decorations for Linux..."
frame_patches=0
for f in "${ASAR_CONTENTS}"/.vite/build/*.js; do
    [ -f "$f" ] || continue
    if grep -q 'minWidth:600,minHeight:400,titleBarStyle:"hidden"' "$f"; then
        sed -i 's/minWidth:600,minHeight:400,titleBarStyle:"hidden",titleBarOverlay:[A-Za-z0-9_$]*/minWidth:600,minHeight:400,titleBarStyle:"default",titleBarOverlay:void 0/' "$f"
        frame_patches=$((frame_patches + 1))
    fi
done

if [ "$frame_patches" -eq 0 ]; then
    echo "❌ Could not find the main window's titleBarStyle — the app layout changed."
    exit 1
fi

DRAG_CSS="${ASAR_CONTENTS}/.vite/renderer/main_window/window-shared.css"
if ! grep -q -- '-webkit-app-region: drag' "$DRAG_CSS" 2>/dev/null; then
    echo "❌ Could not find the main window drag region CSS — the app layout changed."
    exit 1
fi
sed -i 's/-webkit-app-region: drag/-webkit-app-region: no-drag/g' "$DRAG_CSS"
echo "  → Window decorations patched (native frame + drag strip disabled)."

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
mkdir -p "$BUILD_DIR/files/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps"
mkdir -p "$BUILD_DIR/files/share/metainfo"

echo "  → Extracting Electron..."
unzip -q "$ELECTRON_FILE" -d "$BUILD_DIR/files/lib/claude-desktop/"

# Electron derives app.isPackaged from basename(process.execPath): a binary
# still named "electron" reports isPackaged=false, and Claude then looks for its
# locale files inside app.asar instead of in resources/ and dies with ENOENT.
# Renaming the binary is what electron-builder does for real packaged apps.
echo "  → Renaming electron binary (makes app.isPackaged true)..."
mv "$BUILD_DIR/files/lib/claude-desktop/electron" \
   "$BUILD_DIR/files/lib/claude-desktop/claude-desktop"

echo "  → Copying patched app.asar..."
cp "$PATCHED_ASAR" "$BUILD_DIR/files/lib/claude-desktop/resources/app.asar"

UNPACKED_DIR="${WORK_DIR}/app_patched.asar.unpacked"
if [ -d "$UNPACKED_DIR" ]; then
    echo "  → Copying app.asar.unpacked/..."
    cp -r "$UNPACKED_DIR" "$BUILD_DIR/files/lib/claude-desktop/resources/app.asar.unpacked"
fi

# The app reads its locale files from process.resourcesPath at runtime
# (resources/en-US.json and friends), so app.asar alone is not enough — the rest
# of the Windows resources/ tree has to come along. Windows .exe helpers don't.
echo "  → Copying bundled resources (locales, fonts, migrations)..."
NUPKG_RESOURCES="$(dirname "$APP_ASAR")"
find "$NUPKG_RESOURCES" -mindepth 1 -maxdepth 1 \
    ! -name 'app.asar' ! -name 'app.asar.unpacked' ! -name '*.exe' \
    -exec cp -r {} "$BUILD_DIR/files/lib/claude-desktop/resources/" \;

if [ ! -f "$BUILD_DIR/files/lib/claude-desktop/resources/en-US.json" ]; then
    echo "❌ resources/en-US.json is missing — the app would fail to launch."
    exit 1
fi

echo "  → Copying icon..."
cp "$ICON_SRC" "$BUILD_DIR/files/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps/${APP_ID}.png"

echo "  → Creating launcher..."
# No app.asar argument needed: it already sits at the default resources/app.asar
# location next to the binary, so Electron finds it on its own.
cat > "$BUILD_DIR/files/bin/claude-desktop" << 'EOF'
#!/bin/sh
export TMPDIR="$XDG_RUNTIME_DIR/app/$FLATPAK_ID"
exec zypak-wrapper /app/lib/claude-desktop/claude-desktop --ozone-platform-hint=auto "$@"
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
