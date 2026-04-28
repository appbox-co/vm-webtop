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
USER_NAME="${GRD_RDP_USERNAME:-appbox}"

if ! command -v grdctl >/dev/null 2>&1; then
    echo "appbox-configure-gnome-rdp: grdctl not installed, skipping" >&2
    exit 0
fi

install -d -o gnome-remote-desktop -g gnome-remote-desktop -m 0755 "$STATE_DIR"

primary_ipv4() {
    local p
    if command -v ip >/dev/null 2>&1; then
        p=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src / {for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}' || true)
    fi
    if [[ -z "$p" ]] && command -v hostname >/dev/null 2>&1; then
        p=$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)
    fi
    echo "${p:-}"
}

# Windows mstsc often closes before any prompt if the TLS CN/SAN does not match the
# PC name or IP you type. winpr-makecert only encodes the local hostname — use openssl
# with SAN when openssl is available.
ensure_rdp_tls_cert() {
    local key="$STATE_DIR/rdp-tls.key"
    local crt="$STATE_DIR/rdp-tls.crt"
    local regen=false

    if [[ ! -f "$key" || ! -f "$crt" ]]; then
        regen=true
    fi
    if [[ "${RDP_TLS_REGEN:-0}" == "1" ]]; then
        regen=true
    fi

    if [[ "$regen" != true ]]; then
        return 0
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        sudo -u gnome-remote-desktop winpr-makecert -silent -rdp -path "$STATE_DIR" rdp-tls
        return 0
    fi

    local fq short cn primary san tmp
    fq=$(hostname -f 2>/dev/null || hostname)
    short=$(hostname -s 2>/dev/null || echo "$fq")
    cn="${RDP_TLS_CN:-$fq}"
    primary=$(primary_ipv4)

    san="DNS:${fq},DNS:${short}"
    if [[ -n "$primary" ]]; then
        san="${san},IP:${primary}"
    fi
    if [[ -n "${RDP_TLS_EXTRA_SAN:-}" ]]; then
        san="${san},${RDP_TLS_EXTRA_SAN}"
    fi

    tmp=$(mktemp -d)
    chmod 700 "$tmp"
    openssl req -x509 -nodes -newkey rsa:3072 \
        -keyout "$tmp/rdp-tls.key" \
        -out "$tmp/rdp-tls.crt" \
        -days 825 \
        -subj "/CN=${cn}" \
        -addext "subjectAltName=${san}"

    install -m 0640 -o gnome-remote-desktop -g gnome-remote-desktop "$tmp/rdp-tls.key" "$key"
    install -m 0644 -o gnome-remote-desktop -g gnome-remote-desktop "$tmp/rdp-tls.crt" "$crt"
    rm -rf "$tmp"
}

ensure_rdp_tls_cert

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
