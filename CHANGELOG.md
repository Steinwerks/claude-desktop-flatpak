# Changelog

All notable changes to the Claude Desktop Flatpak project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2024-11-02

### Added
- Proper Wayland window decorations for native minimize/maximize/close buttons
- Window dragging functionality
- Support for both X11 and Wayland display servers
- Bundled Electron v32.2.0 for full self-containment

### Changed
- Updated launcher script to use Wayland-native window decorations
- Switched to Electron Ozone platform with Wayland support
- Improved window manager integration

### Fixed
- Missing window controls (minimize/maximize/close buttons)
- Unable to drag/move window
- Window decoration rendering issues on Wayland
- SUID sandbox configuration errors

## [1.0.0] - 2024-11-02

### Added
- Initial Flatpak package for Claude Desktop v0.14.10
- Simple build script that doesn't require flatpak-builder
- Bundled Electron to avoid runtime dependencies
- Full home directory access for Desktop Commander
- Network access for Claude API communication
- GPU acceleration support
- Audio support
- Desktop notifications integration
- File picker integration
- Proper sandboxing with zypak-wrapper

### Features
- Universal Linux distribution support
- Works on immutable systems (Silverblue, Bazzite, etc.)
- Desktop Commander fully functional
- MCP server support
- Configuration stored in ~/.config/claude/

### Technical Details
- Runtime: org.freedesktop.Platform 24.08
- Base: org.electronjs.Electron2.BaseApp 24.08
- Electron Version: 32.2.0
- Claude Desktop Version: 0.14.10

### Security
- Flatpak sandboxing
- zypak-wrapper for Electron sandbox handling
- Controlled filesystem access
- D-Bus mediation for system integration

## [Unreleased]

### Planned
- Automated CI/CD for releases
- Pre-built flatpak bundles in GitHub releases
- Flathub submission
- Version update automation
- Better error handling and user feedback
- Offline mode improvements

---

## Version Numbering

- **Major version** (X.0.0): Breaking changes or major feature additions
- **Minor version** (0.X.0): New features, improvements, or significant fixes
- **Patch version** (0.0.X): Bug fixes and minor improvements

## Notes

- This packaging tracks Claude Desktop's official releases
- Electron version may be updated independently for security fixes
- Runtime versions follow Flatpak's support lifecycle
