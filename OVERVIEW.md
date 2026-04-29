# Overview: Ubuntu VM Images — KDE Plasma on Selkies

## Goal

Provide a script-driven Ubuntu **24.04** or **26.04** image that runs **KDE Plasma** inside a **Selkies WebRTC** remote desktop session.

The remote desktop is browser-based rather than RDP-based:

- **Selkies + GStreamer + WebRTC** serves the desktop over HTTPS.
- **Xvfb** provides a virtual X11 display with RANDR support for dynamic browser resizing.
- **KDE Plasma** runs via `startplasma-x11` inside that virtual display.
- **Selkies cursor support** uses XFixes/DataChannel cursor updates, avoiding the KRDP/KDE Wayland cursor capture issues.

## Installed Desktop

- KDE Plasma via `kde-plasma-desktop`
- Plasma X11 session support when available (`plasma-session-x11`, `kwin-x11`)
- KDE apps: Konsole, Dolphin, Kate, Spectacle, Discover
- Snap and Flatpak integration for the `appbox` user
- Chromium wrapper and Appbox wallpaper

## Remote Access

The master installer installs two components:

```bash
sudo ./install.sh
```

Components can also be run individually:

```bash
sudo ./install.sh --component desktop
sudo ./install.sh --component selkies
```

After installation, open the Selkies web UI at `/vnc/` on the VM's HTTPS hostname. The generated nginx config listens on **443** with `proxy_protocol`, serves Selkies from `/vnc`, and uses the platform certificate under `/etc/ssl/domains/` when present.

## First Boot

`appbox-first-boot.service` handles VM provisioning:

- If `/tmp/user_pw` exists, it sets the Linux password for `appbox`, then deletes the file.
- If `APPBOX_INSTALLED_CALLBACK_URL` is set, it sends a one-time installed callback.

## Customization

- `custom-rootfs/`: files merged on top of `/` after component installation.
- `custom-scripts/`: executable scripts run in sorted order after installation.

## Documentation

- `ARCHITECTURE.md`: components and boot order
- `testing/docs/DEPLOYMENT_GUIDE.md`: deployment notes
- `testing/docs/TESTING_GUIDE.md`: validation harness
- `CHANGELOG.md`: history
