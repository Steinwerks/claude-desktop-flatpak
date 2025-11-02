#!/bin/bash
# Simple Flatpak build for Claude Desktop with bundled Electron

set -e

echo "🔨 Claude Desktop Flatpak Builder (with Electron)"
echo ""

APP_ID="com.anthropic.Claude"
RUNTIME_VERSION="24.08"
ELECTRON_VERSION="32.2.0"  # Latest stable as of Nov 2024

# Check prerequisites
if ! command -v flatpak &> /dev/null; then
    echo "❌ Error: flatpak is not installed"
    exit 1
fi

# Install required runtimes if missing
echo "📦 Checking runtimes..."
if ! flatpak list | grep -q "org.freedesktop.Platform/.*/${RUNTIME_VERSION}"; then
    echo "Installing Platform runtime ${RUNTIME_VERSION}..."
    flatpak install -y flathub org.freedesktop.Platform//${RUNTIME_VERSION}
fi

if ! flatpak list | grep -q "org.electronjs.Electron2.BaseApp/.*/${RUNTIME_VERSION}"; then
    echo "Installing Electron BaseApp ${RUNTIME_VERSION}..."
    flatpak install -y flathub org.electronjs.Electron2.BaseApp//${RUNTIME_VERSION}
fi

# Clean and create build directory
BUILD_DIR="simple-build"
rm -rf "$BUILD_DIR"

# Download Electron if not already present
ELECTRON_FILE="electron-v${ELECTRON_VERSION}-linux-x64.zip"
if [ ! -f "$ELECTRON_FILE" ]; then
    echo ""
    echo "⬇️  Downloading Electron ${ELECTRON_VERSION}..."
    wget -q --show-progress "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_FILE}"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to download Electron"
        exit 1
    fi
else
    echo "✓ Electron ${ELECTRON_VERSION} already downloaded"
fi

echo ""
echo "📦 Initializing flatpak..."

# Initialize the build directory
flatpak build-init "$BUILD_DIR" \
    ${APP_ID} \
    org.freedesktop.Sdk \
    org.freedesktop.Platform \
    ${RUNTIME_VERSION} \
    --base=org.electronjs.Electron2.BaseApp \
    --base-version=${RUNTIME_VERSION}

echo ""
echo "📁 Setting up application files..."

# Create directory structure
mkdir -p "$BUILD_DIR/files/lib/claude-desktop"
mkdir -p "$BUILD_DIR/files/bin"
mkdir -p "$BUILD_DIR/files/share/applications"
mkdir -p "$BUILD_DIR/files/share/icons/hicolor/256x256/apps"
mkdir -p "$BUILD_DIR/files/share/metainfo"

# Extract Electron
echo "  → Extracting Electron..."
unzip -q "$ELECTRON_FILE" -d "$BUILD_DIR/files/lib/claude-desktop/"

# Copy app.asar
echo "  → Copying app.asar..."
cp ../claude-desktop/build/electron-app/app.asar "$BUILD_DIR/files/lib/claude-desktop/resources/"

# Copy icon
echo "  → Copying icon..."
cp ../claude-desktop/build/claude_6_256x256x32.png \
   "$BUILD_DIR/files/share/icons/hicolor/256x256/apps/${APP_ID}.png"

# Create launcher script
echo "  → Creating launcher..."
cat > "$BUILD_DIR/files/bin/claude-desktop" << 'EOF'
#!/bin/sh
export TMPDIR="$XDG_RUNTIME_DIR/app/$FLATPAK_ID"
exec zypak-wrapper /app/lib/claude-desktop/electron /app/lib/claude-desktop/resources/app.asar "$@"
EOF
chmod +x "$BUILD_DIR/files/bin/claude-desktop"

# Copy desktop file
echo "  → Installing desktop file..."
cp ${APP_ID}.desktop "$BUILD_DIR/files/share/applications/"

# Copy metainfo
echo "  → Installing metainfo..."
cp ${APP_ID}.metainfo.xml "$BUILD_DIR/files/share/metainfo/"

echo ""
echo "🔧 Finishing build..."

# Finish the flatpak with all permissions
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

# Export to repository
echo "📤 Exporting to repository..."
rm -rf repo
mkdir -p repo
flatpak build-export repo "$BUILD_DIR"

# Create bundle
echo "🎁 Creating bundle..."
flatpak build-bundle repo claude-desktop.flatpak ${APP_ID}

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 Created: claude-desktop.flatpak"
echo "   Size: $(du -h claude-desktop.flatpak | cut -f1)"
echo ""
echo "To update your installation, run:"
echo "  flatpak update --user ${APP_ID}"
echo "  # or reinstall:"
echo "  flatpak uninstall --user ${APP_ID}"
echo "  flatpak install --user claude-desktop.flatpak"
echo ""
echo "To run:"
echo "  flatpak run ${APP_ID}"
echo ""
