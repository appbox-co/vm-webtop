# Changelog: Ubuntu VM Images

## KDE image update — 2026-10-05

- Fixed remote desktop startup timeouts when the persistent home directory
  contains many files. Selkies now sets ownership on the directories it creates
  without recursively scanning existing user files.

## 3.1.0 — KDE Plasma on Selkies — 2026-04

### Breaking Changes

- Replaced the KRDP/Wayland remote desktop path with Selkies WebRTC streaming.
- Remote access is now browser-based over HTTPS instead of RDP.
- KDE Plasma now runs inside Selkies' Xvfb X11 display via `startplasma-x11`.

### Added

- Restored the `selkies/` component from `main`.
- Enabled Selkies dynamic resize with an initial `1920x1080` desktop size.
- Configured `selkies-desktop.service` for a KDE Plasma X11 session.
- Added Selkies component validation tests.

### Removed

- KRDP package installation and configuration.
- SDDM autologin setup.
- `appbox-configure-krdp.service`, `/etc/default/krdp-appbox`, and KRDP first-boot port handling.

### Why

KRDP on KDE Wayland currently has practical blockers for this image: unreliable cursor visibility and no good adaptive-resolution behavior. Selkies already provides browser resize support and cursor handling through the X11/XFixes path.

---

## 3.0.0 — KDE Plasma + SDDM + KRDP (RDP via Wayland) — 2026-04

Introduced the KDE/KRDP direction. This was superseded by 3.1.0 after testing showed cursor and resize issues with KRDP.

---

## 2.0.0 — GNOME + GDM + GNOME Remote Desktop (RDP) — 2026-04

Replaced the older Selkies/webtop components with GNOME Remote Desktop. This was superseded by the KDE work.

---

## Historical: Ubuntu VM Webtop Environment

See git history for the earlier Selkies/Xvfb/XFCE implementation.
