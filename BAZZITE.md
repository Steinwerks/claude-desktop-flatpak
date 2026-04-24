# Running Claude Desktop on Bazzite

`simple-build.sh` is the recommended path on Bazzite — it avoids the `flatpak-builder` + reboot requirement.

## Step 1 — Install prerequisites

Bazzite is immutable, so `7z` needs to be layered via rpm-ostree. `node` is best run from a toolbox to avoid a reboot.

```bash
# Layer 7z (requires reboot)
rpm-ostree install p7zip p7zip-plugins
systemctl reboot
```

```bash
# After reboot — get node inside a toolbox
toolbox create && toolbox enter
sudo dnf install nodejs npm
exit
```

## Step 2 — Build

Open a terminal **inside the toolbox** (so `node`/`npx` are available):

```bash
toolbox enter
cd ~/Documents/Source/claude-desktop-flatpak
./simple-build.sh
```

This will download the Windows installer (~100MB), patch `app.asar`, build the Flatpak, and produce `claude-desktop.flatpak`.

## Step 3 — Install

Back on the **host** (outside toolbox):

```bash
flatpak install --user claude-desktop.flatpak
```

## Step 4 — Run

```bash
flatpak run com.anthropic.Claude
```

Or launch it from your app menu — it will appear as **Claude** under Office/Utility.

---

> **Note:** If you hit Flatpak permission issues inside the toolbox, run the `flatpak install` step on the host side only. Toolbox mounts the host's Flatpak socket, so most commands work, but installation occasionally needs to happen outside the container.
