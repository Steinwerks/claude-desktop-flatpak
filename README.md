# Claude Desktop Flatpak

This directory contains the Flatpak manifest and build configuration for Claude Desktop, allowing you to run Claude on any Linux distribution (not just Debian-based ones).

## What is Flatpak?

Flatpak is a universal packaging format that works across all Linux distributions. Unlike .deb packages that only work on Debian/Ubuntu, Flatpaks work on Fedora, Arch, openSUSE, and any other Linux distro.

## Prerequisites

1. **Flatpak** must be installed on your system
2. **flatpak-builder** — only for `./build.sh`; `./simple-build.sh` does without it
3. **Flathub** repository should be enabled
4. **7z**, **node/npx**, and **unzip**, to unpack and patch the Windows installer

### Installing prerequisites on Fedora:
```bash
sudo dnf install flatpak flatpak-builder 7zip nodejs npm unzip
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

### Installing prerequisites on other distros:
- **Ubuntu/Debian**: `sudo apt install flatpak flatpak-builder p7zip-full nodejs npm unzip`
- **Arch**: `sudo pacman -S flatpak flatpak-builder p7zip nodejs npm unzip`
- **openSUSE**: `sudo zypper install flatpak flatpak-builder p7zip nodejs npm unzip`

On immutable systems (Bazzite, Silverblue), see [BAZZITE.md](BAZZITE.md) — none of this
needs layering or a reboot.

## Building the Flatpak

You have two options for building:

Both produce the same `claude-desktop.flatpak`. Pick whichever suits your system.

### Option 1: Using flatpak-builder

Install flatpak-builder — the Flathub app works everywhere, needs no root, and is the
easiest route on immutable systems:

```bash
flatpak install -y flathub org.flatpak.Builder

# Or natively, on a mutable distro
sudo dnf install flatpak-builder
```

Then build:
```bash
cd ~/src/claude-desktop-flatpak
./build.sh
```

`build.sh` uses a native `flatpak-builder` when present and falls back to
`flatpak run org.flatpak.Builder` otherwise.

### Option 2: Simple build (No flatpak-builder needed)

Uses basic flatpak commands (`build-init`, `build-finish`, `build-export`) instead:

```bash
cd ~/src/claude-desktop-flatpak
./simple-build.sh
```

Both methods will:
1. Check and install the required Flatpak runtimes
2. Download Electron and the Claude Desktop Windows installer
3. Patch `app.asar` for Linux and bundle it with Electron
4. Create a flatpak bundle file (`claude-desktop.flatpak`)

## Installing the Flatpak

After building, install it with:

```bash
flatpak install --user claude-desktop.flatpak
```

Or to install system-wide (requires sudo):
```bash
flatpak install claude-desktop.flatpak
```

## Running Claude Desktop

After installation, you can run it from your application menu or from terminal:

```bash
flatpak run com.anthropic.Claude
```

## Permissions

The Flatpak includes these permissions:
- **Network access**: Required for communicating with Claude API
- **Home directory access**: For reading/writing your files
- **GPU acceleration**: For better performance
- **Audio**: For any audio features
- **X11/Wayland**: For windowing system
- **Desktop integration**: For notifications and file pickers

## Updating

To update to a new version, simply rebuild and reinstall:

```bash
./build.sh
flatpak update --user com.anthropic.Claude
```

## Uninstalling

To remove the Flatpak:

```bash
flatpak uninstall com.anthropic.Claude
```

## Desktop Commander Integration

Claude Desktop with Desktop Commander will work inside the Flatpak, but with these considerations:

1. **File access**: The Flatpak has access to your home directory by default
2. **System commands**: Will work but run in the Flatpak sandbox context
3. **MCP servers**: Can be configured in `~/.config/claude/` as usual

## Troubleshooting

### Build fails with missing runtimes
Make sure you have Flathub enabled:
```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

### Application won't start
Check logs:
```bash
flatpak run --command=sh com.anthropic.Claude
journalctl --user -xe | grep claude
```

### Need more permissions
Edit `com.anthropic.Claude.yml` and add finish-args as needed.

## File Structure

- `com.anthropic.Claude.yml` - Main Flatpak manifest
- `com.anthropic.Claude.desktop` - Desktop entry file
- `com.anthropic.Claude.metainfo.xml` - AppStream metadata
- `build.sh` - Automated build script
- `README.md` - This file

## Distribution

You can distribute the generated `claude-desktop.flatpak` bundle file to others. They can install it with:

```bash
flatpak install claude-desktop.flatpak
```

No need for them to build it themselves!

## Contributing

Feel free to modify the manifest to suit your needs. Common modifications:

- **Reduce permissions**: Remove finish-args you don't need
- **Add dependencies**: Add modules for additional tools
- **Change runtime version**: Update to newer Freedesktop Platform versions

## Notes

- This is a community-created Flatpak configuration
- Claude Desktop is developed by Anthropic
- Based on version 0.14.10 of the Debian package

## License

The Claude Desktop application is proprietary software by Anthropic. This Flatpak manifest configuration is provided as-is for packaging purposes.
