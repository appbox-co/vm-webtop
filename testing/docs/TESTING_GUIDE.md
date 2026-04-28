# Testing guide

## Scope

Tests target a VM where **`sudo ./install.sh`** (or **`sudo ./install.sh --component desktop`**) has **already** completed successfully.

## Requirements

- Run the harness as **root** (it checks **`EUID`**).
- Ubuntu **24.04** or **26.04** recommended.

## Running the suite

```bash
cd /path/to/vm_images
sudo ./testing/test-framework.sh
```

Categories:

```bash
sudo ./testing/test-framework.sh -c component
sudo ./testing/test-framework.sh -c integration
sudo ./testing/test-framework.sh -l
```

Results and HTML report default under **`/tmp/vm-images-tests/`**.

## What is covered

| Script | Intent |
|--------|--------|
| **`testing/component/test_desktop_installation.sh`** | Packages present, **`appbox`** user, required systemd units enabled, configure script and defaults file on disk. |
| **`testing/integration/test_end_to_end.sh`** | **`grdctl --system status`** succeeds; optional **`ss`** check for **`RDP_PORT`** from **`/etc/default/gnome-remote-desktop-appbox`**. |

## Manual checks (recommended)

1. From another machine: **RDP** to **`host:$RDP_PORT`** with the system RDP password.
2. Complete **GDM** login as **`appbox`**.
3. Launch **GNOME Software**, **Snap Store**, **Chromium**, **mousepad**.
4. Confirm wallpaper matches **`/usr/share/backgrounds/appbox/appbox.svg`**.

## Continuous integration

The repository does not ship a CI matrix by default; run **`test-framework.sh`** on a disposable VM after changes to **`desktop/install.sh`** or **`desktop/rootfs/`**.
