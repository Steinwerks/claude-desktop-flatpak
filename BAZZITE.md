# Running Claude Desktop on Bazzite

Both build scripts work on Bazzite, and neither needs rpm-ostree layering or a reboot — the whole
build runs on the host.

- **`./simple-build.sh`** — fewest moving parts; uses plain `flatpak build-*` commands.
- **`./build.sh`** — uses flatpak-builder. Install it from Flathub (no root, no reboot) with
  `flatpak install -y flathub org.flatpak.Builder`; the script falls back to
  `flatpak run org.flatpak.Builder` when there's no native binary.

Steps below use `simple-build.sh`; substitute `./build.sh` at Step 2 if you prefer that path.

Don't run the build inside a toolbox. A toolbox container has its own `/usr`, so it can't see
host-layered packages, and it ships no `flatpak` binary — the script's prerequisite checks fail
immediately there.

## Step 1 — Install prerequisites

**7z** — already in the Bazzite base image, nothing to install. Confirm with:

```bash
command -v 7z    # → /usr/bin/7z
```

> If it's ever missing, the package is `7zip` (`sudo dnf install 7zip`), not `p7zip` — p7zip was
> retired from Fedora.

**node / npx** — not in Bazzite, and layering it would cost a reboot. Use a user-local tarball
instead; the build only needs it for two `npx @electron/asar` calls.

```bash
mkdir -p ~/.local/opt
curl -L https://nodejs.org/dist/v24.18.1/node-v24.18.1-linux-x64.tar.xz \
  | tar xJ -C ~/.local/opt
export PATH="$HOME/.local/opt/node-v24.18.1-linux-x64/bin:$PATH"
```

That `export` only lasts for the current shell — either build in the same shell, or add the line to
your `~/.bashrc` to keep it.

**Flatpak runtimes** — `simple-build.sh` installs whatever is missing
(`org.freedesktop.Platform`, `org.freedesktop.Sdk`, and `org.electronjs.Electron2.BaseApp`, all at
`24.08`). Bazzite's flathub remote is system-scope only, so those installs trigger a polkit prompt.
To install them user-scope with no prompt, add a user remote first:

```bash
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Step 2 — Build

```bash
cd ~/Documents/Source/claude-desktop-flatpak
./simple-build.sh
```

This downloads the Windows installer (~100MB) and Electron, patches `app.asar`, and produces
`claude-desktop.flatpak`.

## Step 3 — Install

```bash
flatpak install --user claude-desktop.flatpak
```

## Step 4 — Run

```bash
flatpak run com.anthropic.Claude
```

Or launch it from your app menu — it appears as **Claude** under Office/Utility.

---

## Troubleshooting

**`SHA-256 mismatch` or a 404 on the installer download.** The Claude Desktop version is pinned in
`simple-build.sh` (`CLAUDE_VERSION`, `EXE_HASH`, `EXE_SHA256`). Anthropic eventually rotates
releases, so an old pin will stop resolving; update all three constants together.

**`npx` wants to download `@electron/asar` on every run.** Expected — it's fetched on demand and
cached under `~/.npm`. The build needs network access anyway for the installer and Electron.

**Nothing gets layered by this guide.** If `rpm-ostree status` shows requested packages you added
for an earlier version of these instructions (e.g. `p7zip`), you can drop them:
`rpm-ostree uninstall p7zip p7zip-plugins`.
