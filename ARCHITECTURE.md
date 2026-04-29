# Architecture: KDE Plasma on Selkies

This image runs KDE Plasma in a virtual X11 display and streams it with Selkies. This replaces the KRDP/Wayland direction because KRDP currently has poor cursor behavior and no reliable dynamic resolution path for this VM use case.

## Directory Layout

```text
vm_images/
├── install.sh              # Master installer: desktop + selkies
├── desktop/
│   ├── install.sh          # KDE packages, appbox user, app provisioning
│   └── rootfs/             # First-boot, polkit, Chromium, wallpaper files
├── selkies/
│   ├── install.sh          # Selkies, Xvfb, nginx, PulseAudio, WebRTC stack
│   └── rootfs/             # Selkies services and desktop startup scripts
├── testing/
├── custom-rootfs/
└── custom-scripts/
```

## Runtime Flow

1. `appbox-first-boot.service` runs after cloud-init:
   - Sets the `appbox` password from `/tmp/user_pw` if present.
   - Sends the optional installed callback.
2. `selkies-setup.service` prepares devices and permissions.
3. `xvfb.service` starts the virtual X11 display on `:1`.
4. `selkies-pulseaudio.service` starts audio for the virtual desktop.
5. `selkies-nginx.service` exposes the web UI at `/vnc/` on HTTPS port `443` with `proxy_protocol` and the platform domain certificate when present.
6. `selkies.service` starts the WebRTC streamer with `SELKIES_ENABLE_RESIZE=true`.
7. `selkies-desktop.service` runs `/etc/selkies/svc-de.sh`, which starts `startplasma-x11` inside `DISPLAY=:1`.

## Desktop Component

The `desktop` component installs the KDE payload and user-facing applications. It does not provide remote access directly.

Key packages:

- `kde-plasma-desktop`
- `plasma-session-x11` and `kwin-x11` when available
- `plasma-nm`, `plasma-pa`, `plasma-discover`
- `konsole`, `dolphin`, `kate`, `kde-spectacle`
- `flatpak`, `snapd`, Chromium wrapper support

## Selkies Component

The `selkies` component owns remote access:

- Xvfb virtual display with RANDR enabled
- Selkies GStreamer/WebRTC streamer
- Dynamic resize through `SELKIES_ENABLE_RESIZE=true`
- Cursor rendering via XFixes/DataChannel rather than KDE Wayland cursor metadata
- Nginx HTTPS front end on the base hostname, with websocket proxying at `/vnc/websocket`
- PulseAudio for desktop audio

The initial display size is `1920x1080`, but Selkies can resize the virtual display to match the browser window.

## Security Notes

- Selkies is exposed through HTTPS on port `443` by default.
- The `appbox` Linux user remains the primary desktop user.
- Snap/Flatpak polkit rules allow `appbox` to manage app stores from inside the desktop.
- `custom-rootfs/` and `custom-scripts/` run after components, so deployments can override service ports or add hardening.
