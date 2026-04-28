# Overview: Ubuntu VM Images — GNOME + RDP

## Goal

Provide a **script-driven** image setup for Ubuntu **24.04** or **26.04** that delivers:

- **GNOME** (via **`ubuntu-desktop-minimal`**)
- **GDM** graphical login
- **GNOME Remote Desktop** with **RDP** in **system (headless / Remote Login)** mode, compatible with **Windows Remote Desktop**
- The same **Appbox-style wallpaper**, **Chromium** (snap + wrapper), **mousepad**, **Snap Store**, **GNOME Software** with **snap** and **flatpak** support, and **polkit** rules so user **`appbox`** can manage snaps and flatpaks

## What was removed

The old **LinuxServer.io-style** stack (**Selkies** in the browser, **Xvfb**, **nginx**, Pulse/WebRTC streaming, **GNOME Flashback** on a virtual X server) is **gone**. Access is **native RDP** only.

## Quick start

On a fresh Ubuntu **noble** or **resolute** VM (run as **root**):

```bash
sudo ./install.sh
```

Single component:

```bash
sudo ./install.sh --component desktop
```

## RDP port and credentials

- Edit **`/etc/default/gnome-remote-desktop-appbox`** and set **`RDP_PORT`** (production uses whatever your environment exports; the installer reads this file at boot).
- Optional: set **`GRD_RDP_USERNAME`** and **`GRD_RDP_PASSWORD`** for the **first** RDP handshake (GDM login screen).
- If **`GRD_RDP_PASSWORD`** is not set, a random password is stored in **`/etc/gnome-remote-desktop/rdp-secret`**.

Example for a port-forwarded lab host (external port **30511**):

```bash
echo 'RDP_PORT=30511' | sudo tee /etc/default/gnome-remote-desktop-appbox
sudo systemctl restart appbox-configure-gnome-rdp.service gnome-remote-desktop.service
```

Then connect with **mstsc** to **`host:30511`** (or your mapped hostname/port).

## Customization

- **`custom-rootfs/`**: files merged on top of `/` after the main install (see **`custom-rootfs/README.md`**).
- **`custom-scripts/`**: executable scripts run in sorted order (see **`custom-scripts/README.md`**).

## Documentation

- **`ARCHITECTURE.md`** — components and boot order  
- **`testing/docs/DEPLOYMENT_GUIDE.md`** — operations and troubleshooting  
- **`testing/docs/TESTING_GUIDE.md`** — test harness  
- **`CHANGELOG.md`** — history  
