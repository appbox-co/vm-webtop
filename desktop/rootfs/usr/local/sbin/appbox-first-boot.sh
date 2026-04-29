#!/bin/bash
# First-boot provisioning hooks for Appbox KDE/Selkies templates.
set -euo pipefail

STATE_DIR=/var/lib/appbox-first-boot
CALLBACK_STAMP="${STATE_DIR}/installed-callback.done"
RDP_DOWNLOAD_HTPASSWD_FILE=/etc/appbox-rdp-download/htpasswd

log() {
    echo "appbox-first-boot: $*"
}

configure_rdp_download_auth() {
    local pw="$1"
    if [[ -z "$pw" ]]; then
        return 0
    fi

    install -d -m 0750 -o root -g www-data "$(dirname "$RDP_DOWNLOAD_HTPASSWD_FILE")"
    printf 'appbox:%s\n' "$(openssl passwd -apr1 "$pw")" >"$RDP_DOWNLOAD_HTPASSWD_FILE"
    chown root:www-data "$RDP_DOWNLOAD_HTPASSWD_FILE"
    chmod 640 "$RDP_DOWNLOAD_HTPASSWD_FILE"
}

configure_appbox_password() {
    local pw_file=/tmp/user_pw
    if [[ ! -f "$pw_file" ]]; then
        return 0
    fi

    local pw
    pw="$(tr -d '\r\n' <"$pw_file")"
    rm -f "$pw_file"

    if [[ -z "$pw" ]]; then
        log "$pw_file was empty; not changing appbox password"
        return 0
    fi

    log "Setting appbox Linux password from $pw_file"
    printf 'appbox:%s\n' "$pw" | chpasswd
    configure_rdp_download_auth "$pw"
}

callback_url() {
    printf '%s' "${APPBOX_INSTALLED_CALLBACK_URL:-${APPBOX_CALLBACK_URL:-${APPBOX_API_CALLBACK_URL:-}}}"
}

send_installed_callback() {
    local url
    url="$(callback_url)"
    if [[ -z "$url" || -f "$CALLBACK_STAMP" ]]; then
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log "curl is unavailable; cannot send installed callback"
        return 0
    fi

    local hostname machine_id payload auth_args=()
    hostname="$(hostname -f 2>/dev/null || hostname)"
    machine_id="$(cat /etc/machine-id 2>/dev/null || true)"
    payload="$(printf '{"status":"installed","hostname":"%s","machine_id":"%s"}' "$hostname" "$machine_id")"

    if [[ -n "${APPBOX_CALLBACK_TOKEN:-}" ]]; then
        auth_args=(-H "Authorization: Bearer ${APPBOX_CALLBACK_TOKEN}")
    fi

    log "Sending installed callback"
    if curl -fsS --retry 8 --retry-delay 5 --max-time 20 \
        -H 'Content-Type: application/json' \
        "${auth_args[@]}" \
        -X POST \
        --data "$payload" \
        "$url"; then
        install -d -m 0755 -o root -g root "$STATE_DIR"
        date -Is >"$CALLBACK_STAMP"
    else
        log "Installed callback failed; will retry on next boot"
    fi
}

main() {
    configure_appbox_password
    send_installed_callback
}

main "$@"
