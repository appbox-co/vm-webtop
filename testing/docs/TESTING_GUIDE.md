# Testing Guide

## Scope

Tests target a VM where `sudo ./install.sh` has completed successfully.

## Running the Suite

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

Results and HTML output are written under `/tmp/vm-images-tests/`.

## Coverage

| Script | Intent |
|--------|--------|
| `testing/component/test_desktop_installation.sh` | Confirms KDE Plasma packages, X11 session support when available, `appbox`, and first-boot provisioning. |
| `testing/component/test_selkies_installation.sh` | Confirms Selkies packages, Xvfb, services, `/etc/selkies/` scripts, resize environment, and Plasma desktop startup. |
| `testing/integration/test_end_to_end.sh` | Smoke-checks that Selkies is configured to start Plasma and that HTTPS port `443` is listening when services are active. |

## Manual Checks

1. Open the Selkies web desktop over HTTPS.
2. Confirm KDE Plasma loads inside the browser.
3. Resize the browser window and confirm the remote desktop adapts.
4. Confirm the cursor is visible and input works.
5. Launch KDE Discover, Chromium, Kate, Konsole, and Dolphin.
