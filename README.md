# Claude Desktop Flatpak

This directory contains the Flatpak manifest and build configuration for Claude Desktop, allowing you to run Claude on any Linux distribution (not just Debian-based ones).

## What is Flatpak?

Flatpak is a universal packaging format that works across all Linux distributions. Unlike .deb packages that only work on Debian/Ubuntu, Flatpaks work on Fedora, Arch, openSUSE, and any other Linux distro.

## Prerequisites

1. **Flatpak** must be installed on your system
2. **flatpak-builder** for building the package
3. **Flathub** repository should be enabled

### Installing prerequisites on Fedora:
```bash
sudo dnf install flatpak flatpak-builder
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

### Installing prerequisites on other distros:
- **Ubuntu/Debian**: `sudo apt install flatpak flatpak-builder`
- **Arch**: `sudo pacman -S flatpak flatpak-builder`
- **openSUSE**: `sudo zypper install flatpak flatpak-builder`

## Building the Flatpak

You have two options for building:

### Option 1: Using flatpak-builder (Recommended)

First install flatpak-builder:
```bash
# On Bazzite/Fedora (immutable)
rpm-ostree install flatpak-builder
# Then reboot

# Or on regular Fedora
sudo dnf install flatpak-builder
```

Then build:
```bash
cd ~/src/claude-desktop-flatpak
./build.sh
```

### Option 2: Simple build (No flatpak-builder needed)

If you don't want to install flatpak-builder or are on an immutable system, use the simple build:

```bash
cd ~/src/claude-desktop-flatpak
./simple-build.sh
```

This uses basic flatpak commands to create the package without requiring flatpak-builder.

Both methods will:
1. Check and install required Flatpak runtimes
2. Build the application using flatpak-builder
3. Create a flatpak bundle file (`claude-desktop.flatpak`)

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
