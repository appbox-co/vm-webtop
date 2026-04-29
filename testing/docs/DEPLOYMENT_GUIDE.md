# Deployment Guide: KDE Plasma on Selkies

## Prerequisites

- Ubuntu **24.04 (noble)** or **26.04 (resolute)**.
- Root SSH or console access.
- Network access for `apt`, Docker image pulls, Node.js, snap, and Selkies source builds.
- Enough disk for KDE Plasma, Selkies, Docker build dependencies, and browser assets.

## Install

```bash
git clone <your-fork-or-mirror>/vm_images.git
cd vm_images
sudo ./install.sh
```

The full install runs:

- `desktop`: KDE Plasma packages and app provisioning.
- `selkies`: Xvfb, Selkies, nginx, PulseAudio, and the Plasma desktop service.

Optional component-only runs:

```bash
sudo ./install.sh --component desktop
sudo ./install.sh --component selkies
```

## Password Provisioning

To set the `appbox` password during first boot, create `/tmp/user_pw` before `appbox-first-boot.service` runs:

```yaml
runcmd:
  - install -m 600 /dev/null /tmp/user_pw
  - echo -n 'YOUR_SECURE_PASSWORD' > /tmp/user_pw
```

The service applies the password with `chpasswd` and deletes the file.

## Connecting

Open the Selkies web desktop under `/vnc` on the VM's HTTPS hostname, for example:

```text
https://HOSTNAME/vnc/
```

`selkies-nginx.service` generates an nginx server block for port **443** with `proxy_protocol`, `server_name` set to `hostname -f`, and Selkies served from `/vnc`. The websocket endpoint is `/vnc/websocket`.

Certificate selection:

- If the hostname is under `appboxes.co`, the certificate directory is the parent domain. For `ubuntukde.tester2.appboxes.co`, nginx uses `/etc/ssl/domains/tester2.appboxes.co/`.
- For Appboxes hostnames, nginx also accepts the platform certificate at `/etc/ssl/appbox/`, matching the existing production images.
- For Appboxes hostnames, self-signed fallback certificates are ignored; `selkies-nginx.service` waits for the platform certificate and restarts until it is present.
- For non-Appboxes hostnames, the full hostname is used as the certificate directory under `/etc/ssl/domains/`, with `/etc/ssl/appbox/` allowed as a self-signed fallback.

Optional overrides can be placed in `/etc/default/selkies`:

```bash
sudo install -m 0644 /dev/null /etc/default/selkies
echo 'SELKIES_SERVER_NAME=custom.example.com' | sudo tee -a /etc/default/selkies
echo 'SELKIES_CERT_DOMAIN=example.com' | sudo tee -a /etc/default/selkies
echo 'SUBFOLDER=/vnc' | sudo tee -a /etc/default/selkies
sudo systemctl restart selkies-nginx.service
```

Useful service checks:

```bash
systemctl status xvfb
systemctl status selkies
systemctl status selkies-desktop
systemctl status selkies-nginx
```

Logs:

```bash
journalctl -u selkies -f
journalctl -u selkies-desktop -f
journalctl -u selkies-nginx -f
```

## Resize and Cursor Behavior

Selkies starts with `DISPLAY_SIZEW=1920`, `DISPLAY_SIZEH=1080`, `SELKIES_ENABLE_RESIZE=true`, `SELKIES_USE_CSS_SCALING=true`, and `SELKIES_SCALING_DPI=96,120,144,168,192,216,240,264,288`. The dashboard build is patched so first load defaults to 100% (`96` DPI) instead of deriving a HiDPI scale from the browser device pixel ratio.

Cursor images are captured from X11 with XFixes and sent to the browser separately, avoiding the KRDP/KDE Wayland cursor metadata issue.

## Installed Callback

Set `APPBOX_INSTALLED_CALLBACK_URL` before first boot to make `appbox-first-boot.service` send a one-time HTTP `POST` after local provisioning completes. `APPBOX_CALLBACK_URL` and `APPBOX_API_CALLBACK_URL` are accepted aliases. If `APPBOX_CALLBACK_TOKEN` is set, it is sent as a bearer token.
