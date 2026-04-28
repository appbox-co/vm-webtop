# Deployment guide: GNOME + RDP

## Prerequisites

- Ubuntu **24.04 (noble)** or **26.04 (resolute)**.
- Root SSH or console access.
- Enough disk for **`ubuntu-desktop-minimal`** (order of **several GB**).
- Network for **`apt`** and **`snap`**.
- For cloud images: allow **`snap wait system seed`** to finish (the **`desktop`** installer waits when possible).

## Installation

```bash
git clone <your-fork-or-mirror>/vm_images.git
cd vm_images
sudo ./install.sh
```

Optional: **`sudo ./install.sh --skip-kernel-update`** if you do not want the **6.14** kernel path (see **`install.sh`** help).

## RDP port (`RDP_PORT`)

Production should set the listen port via **`/etc/default/gnome-remote-desktop-appbox`** (key **`RDP_PORT=...`**). This file is sourced by **`/usr/local/sbin/appbox-configure-gnome-rdp.sh`** on boot and can be overridden by your image build or cloud-init.

Example (external mapped port **30511**):

```bash
sudo tee /etc/default/gnome-remote-desktop-appbox >/dev/null <<'EOF'
RDP_PORT=30511
EOF
sudo systemctl restart appbox-configure-gnome-rdp.service gnome-remote-desktop.service
```

## RDP credentials (GDM / “Remote Login”)

1. **First factor (RDP)** — set with **`grdctl --system rdp set-credentials`** by the configure script:
   - Optional fixed values: **`GRD_RDP_USERNAME`** and **`GRD_RDP_PASSWORD`** in **`/etc/default/gnome-remote-desktop-appbox`**.
   - Otherwise a random password is stored in **`/etc/gnome-remote-desktop/rdp-secret`** (read with **`sudo cat`**).
2. **Second factor (Linux)** — normal **GDM** login (e.g. user **`appbox`**).

## Useful commands

```bash
systemctl status gdm3 gnome-remote-desktop appbox-configure-gnome-rdp
grdctl --system status
journalctl -u gnome-remote-desktop -b --no-pager
sudo ss -tlnp | grep -E '3389|30511'
```

## Firewall

Open the **same TCP port** as **`RDP_PORT`** (e.g. **`ufw allow 3389/tcp`** or your cloud SG).

## Polkit / grdctl

If **`grdctl --system`** fails with **pkexec** errors, ensure **`polkitd`** and **`pkexec`** are installed (the **`desktop`** installer pulls them in).

## Wallpaper and dconf

Defaults live under **`/etc/dconf/db/local.d/`** and **`/etc/dconf/db/gdm.d/`**. After manual edits, run **`sudo dconf update`**.

## Migrating from older images

Older images used **`/config`** as the desktop user home for Selkies. That layout is **not** used anymore; the **`desktop`** installer removes **`/config`** if present. Use **`/home/appbox`**.

## Uninstall / rollback

There is no automated uninstall. Snapshot the VM before installing, or remove packages manually (**`ubuntu-desktop-minimal`**, **`gnome-remote-desktop`**, etc.) according to your policy.
