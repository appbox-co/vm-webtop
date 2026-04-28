# Overview: Ubuntu VM Images — GNOME + RDP

## Goal

Provide a **script-driven** image setup for Ubuntu **24.04** or **26.04** that delivers:

- **GNOME** (via **`ubuntu-desktop-minimal`**)
- **GDM** graphical login
- **GNOME Remote Desktop** with **RDP** in **system (headless / Remote Login)** mode, compatible with **Windows Remote Desktop**
- The same **Appbox-style wallpaper**, **Chromium** (snap + wrapper), **mousepad**, **Snap Store**, **GNOME Software** with **snap** and **flatpak** support, and **polkit** rules so user **`appbox`** can manage snaps and flatpaks

## What was removed

The old **LinuxServer.io-style** stack (**Selkies** in the browser, **Xvfb**, **nginx**, Pulse/WebRTC streaming, **GNOME Flashback** on a virtual X server) is **gone**. Access is **native RDP** only.

## First-boot provisioning

On boot, **`appbox-first-boot.service`** reads **`RDP_PORT`** from the systemd service environment (including **`/etc/environment`** and **`/etc/default/appbox-first-boot`**) and writes it into **`/etc/default/gnome-remote-desktop-appbox`** before GNOME Remote Desktop is configured.

If **`/tmp/user_pw`** exists, the service applies it to the Linux **`appbox`** user and stores the same password as GNOME Remote Desktop’s first-hop RDP secret, then deletes the file. See **`testing/docs/DEPLOYMENT_GUIDE.md`** for details.

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

- Export **`RDP_PORT`** into **`/etc/environment`** or **`/etc/default/appbox-first-boot`** before first boot; **`appbox-first-boot.service`** persists it for the GRD configure service.
- **`GRD_RDP_USERNAME`** defaults to **`appbox`** for the **first** RDP handshake (GDM login screen).
- If **`/tmp/user_pw`** exists on first boot, the Linux **`appbox`** password and first-hop RDP password are set to that value. Otherwise, **`GRD_RDP_PASSWORD`** or the persistent random secret in **`/etc/gnome-remote-desktop/rdp-secret`** is used.

Example for a port-forwarded lab host (external port **18691**):

```bash
echo 'RDP_PORT=18691' | sudo tee /etc/default/appbox-first-boot
sudo systemctl restart appbox-first-boot.service appbox-configure-gnome-rdp.service gnome-remote-desktop.service
```

Then connect with **mstsc** to **`host:18691`** (or your mapped hostname/port).

## Microsoft Remote Desktop: no login UI / **0x4** (Windows **or** Mac)

GNOME **Remote Login** uses **Server Redirection**. Put **`use redirection server name:i:1`** in your **`.rdp`** file (Windows **mstsc** *Save As*, or Mac **Import from RDP file** / an **`rdp://`** URI). Microsoft’s docs list that flag for **Mac** as well. Details: **`testing/docs/DEPLOYMENT_GUIDE.md`** (and the SUSE GNOME headless article linked there).

**Mac / third-party RDP:** Even with a correct **`.rdp`**, many **macOS** clients (Microsoft **Windows App**, **Royal TSX**, **Remote Desktop Manager**, etc.) still **drop after GDM** with a black screen — they often mishandle the same **post-login redirection** as each other. **Windows `mstsc`** remains the supported path; see **`testing/docs/DEPLOYMENT_GUIDE.md`** § **D** for workarounds (e.g. small **Windows VM** on the Mac to run **mstsc**).

## Customization

- **`custom-rootfs/`**: files merged on top of `/` after the main install (see **`custom-rootfs/README.md`**).
- **`custom-scripts/`**: executable scripts run in sorted order (see **`custom-scripts/README.md`**).

## Documentation

- **`ARCHITECTURE.md`** — components and boot order  
- **`testing/docs/DEPLOYMENT_GUIDE.md`** — operations and troubleshooting  
- **`testing/docs/TESTING_GUIDE.md`** — test harness  
- **`CHANGELOG.md`** — history  
