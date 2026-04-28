#!/bin/bash
# Apply system-level GNOME Remote Desktop (headless / Remote Login) settings.
set -euo pipefail

ENV_FILE=/etc/default/gnome-remote-desktop-appbox
STATE_DIR=/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop
SECRET_FILE=/etc/gnome-remote-desktop/rdp-secret

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi

: "${RDP_PORT:=3389}"
USER_NAME="${GRD_RDP_USERNAME:-rdp-login}"

if ! command -v grdctl >/dev/null 2>&1; then
    echo "appbox-configure-gnome-rdp: grdctl not installed, skipping" >&2
    exit 0
fi

install -d -o gnome-remote-desktop -g gnome-remote-desktop -m 0755 "$STATE_DIR"

if [[ ! -f "$STATE_DIR/rdp-tls.crt" || ! -f "$STATE_DIR/rdp-tls.key" ]]; then
    sudo -u gnome-remote-desktop winpr-makecert -silent -rdp -path "$STATE_DIR" rdp-tls
fi

grdctl --system rdp set-tls-key "$STATE_DIR/rdp-tls.key"
grdctl --system rdp set-tls-cert "$STATE_DIR/rdp-tls.crt"
grdctl --system rdp set-port "$RDP_PORT"

if [[ -n "${GRD_RDP_PASSWORD:-}" ]]; then
    PASSWORD="$GRD_RDP_PASSWORD"
elif [[ -f "$SECRET_FILE" ]]; then
    PASSWORD=$(tr -d '\n' <"$SECRET_FILE")
else
    install -d -m 0755 /etc/gnome-remote-desktop
    PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
    umask 077
    printf '%s' "$PASSWORD" >"$SECRET_FILE"
    umask 022
    chmod 600 "$SECRET_FILE"
fi

grdctl --system rdp set-credentials "$USER_NAME" "$PASSWORD"
grdctl --system rdp enable

exit 0
