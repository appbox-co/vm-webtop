# Architecture: Ubuntu VM GNOME + RDP (GNOME Remote Desktop)

This repository installs a **full GNOME desktop** on Ubuntu **24.04 (noble)** or **26.04 (resolute)** with **GDM** and **GNOME Remote Desktop** in **system / headless** mode so users can connect with **Windows Remote Desktop (mstsc)** before logging in at the GDM screen (“Remote Login”).

The previous **Selkies + Xvfb + browser streaming** stack has been removed.

## Directory layout

```
vm_images/
├── install.sh              # Master installer (validation, kernel helper, desktop component)
├── desktop/
│   ├── install.sh          # APT: ubuntu-desktop-minimal, GRD, snaps, polkit, dconf, systemd
│   └── rootfs/             # Files merged to / (see below)
├── testing/
│   ├── test-framework.sh   # Optional test harness (run on an installed VM as root)
│   ├── component/
│   └── integration/
├── custom-rootfs/          # (optional) extra files copied by master install — see README
└── custom-scripts/         # (optional) post-install hooks — see README
```

## Runtime flow

1. **Boot** reaches `graphical.target`; **GDM** starts the greeter (no local monitor required for RDP path).
2. **`appbox-configure-gnome-rdp.service`** (oneshot, `Before=gnome-remote-desktop.service`) runs **`/usr/local/sbin/appbox-configure-gnome-rdp.sh`**:
   - Sources **`/etc/default/gnome-remote-desktop-appbox`** for **`RDP_PORT`** (and optional **`GRD_RDP_USERNAME`** / **`GRD_RDP_PASSWORD`**).
   - Ensures TLS material under **`/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/`** via **`winpr-makecert`**.
   - Applies settings with **`grdctl --system`** (`set-tls-*`, `set-port`, `set-credentials`, `enable`).
   - If **`GRD_RDP_PASSWORD`** is unset, a random password is written once to **`/etc/gnome-remote-desktop/rdp-secret`** (mode `0600`).
3. **`gnome-remote-desktop.service`** listens on **`RDP_PORT`** (default **3389** in the shipped defaults file).
4. The user connects with an RDP client using the **system RDP credentials**, then authenticates on **GDM** as **`appbox`** (or another local user).

**`polkitd` / `pkexec`** are required so **`grdctl --system`** can talk to the polkit-backed configuration path.

## Desktop component (`desktop/`)

| Area | Role |
|------|------|
| **Packages** | `ubuntu-desktop-minimal`, `gnome-remote-desktop`, `winpr-utils`, `polkitd`, `pkexec`, `mousepad`, `gnome-software` + snap/flatpak plugins, `flatpak`, `snapd`; **Chromium** and **Snap Store** via snap. |
| **Polkit** | `etc/polkit-1/rules.d/50-snap-appbox.rules`, `50-flatpak-appbox.rules` so user **`appbox`** can use snap/flatpak from the session. |
| **Wallpaper** | `appbox.svg` under **`/usr/share/backgrounds/appbox/`**; dconf keyfiles under **`/etc/dconf/db/local.d/`** and **`/etc/dconf/db/gdm.d/`** (run **`dconf update`** after install). |
| **Chromium** | **`/usr/local/bin/wrapped-chromium`** and **`/usr/bin/chromium`** wrapper; `.desktop` files patched where present to call the wrapper. |
| **User** | **`appbox`** created if missing, in group **`sudo`**, with **`~/.local/share/flatpak`** prepared; **flathub** added for **`appbox`** (user remote). |

## Master installer (`install.sh`)

- Validates Ubuntu **noble** or **resolute**, memory/disk, network, systemd.
- Optional **kernel 6.14** path for virtiofs `execv` issues (unchanged behaviour).
- **`configure_apt_release_verification`**: optional apt sandbox tweak for some minimal images.
- Installs the **`desktop`** component only.
- Copies **`custom-rootfs/`** and runs **`custom-scripts/`** if present.

## Testing

Post-install on the VM (as **root**): **`sudo ./testing/test-framework.sh`**. Tests assume the **`desktop`** component is installed and enabled.

## Security notes

- **System RDP credentials** are only for reaching GDM; users still need a **local Unix password** (or your auth setup) at login.
- Rotate **`/etc/gnome-remote-desktop/rdp-secret`** or set **`GRD_RDP_PASSWORD`** in **`/etc/default/gnome-remote-desktop-appbox`** for production.
- Expose **`RDP_PORT`** only through your platform’s firewall / port mapping.
