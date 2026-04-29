#!/bin/bash
# Generate the HTTPS nginx endpoint for downloading the Appbox RDP profile.
set -euo pipefail

RDP_ENV_FILE=/etc/default/gnome-remote-desktop-appbox
SYSTEM_ENV_FILE=/etc/environment
FIRST_BOOT_ENV_FILE=/etc/default/appbox-first-boot
DOWNLOAD_ENV_FILE=/etc/default/appbox-rdp-download
RDP_DIR=/var/lib/appbox-rdp-download
AUTH_DIR=/etc/appbox-rdp-download
HTPASSWD_FILE="${AUTH_DIR}/htpasswd"
NGINX_SITE=/etc/nginx/sites-available/appbox-rdp-download
NGINX_SITE_ENABLED=/etc/nginx/sites-enabled/appbox-rdp-download

load_env_file() {
    local file="$1"
    local line key value
    [[ -f "$file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

        if [[ ( "$value" == \"*\" && "$value" == *\" ) || ( "$value" == \'*\' && "$value" == *\' ) ]]; then
            value="${value:1:${#value}-2}"
        fi

        case "$key" in
            RDP_PORT | RDP_FILE_HOSTNAME | APPBOX_RDP_HOSTNAME | RDP_HOSTNAME | RDP_DOWNLOAD_USERNAME)
                printf -v "$key" '%s' "$value"
                ;;
        esac
    done <"$file"
}

load_env_file "$RDP_ENV_FILE"
load_env_file "$SYSTEM_ENV_FILE"
load_env_file "$FIRST_BOOT_ENV_FILE"
load_env_file "$DOWNLOAD_ENV_FILE"

: "${RDP_PORT:=3389}"
: "${RDP_DOWNLOAD_USERNAME:=appbox}"

rdp_hostname() {
    if [[ -n "${RDP_FILE_HOSTNAME:-}" ]]; then
        printf '%s' "$RDP_FILE_HOSTNAME"
        return 0
    fi
    hostname -f 2>/dev/null || hostname
}

cert_domain_for_hostname() {
    local host="$1"
    if [[ "$host" == *appboxes.co ]]; then
        local labels
        IFS='.' read -r -a labels <<<"$host"
        local count="${#labels[@]}"
        if ((count >= 4)); then
            printf '%s.%s.%s' "${labels[count - 3]}" "${labels[count - 2]}" "${labels[count - 1]}"
            return 0
        fi
    fi
    printf '%s' "$host"
}

write_rdp_file() {
    local host="$1"
    install -d -m 0755 -o root -g root "$RDP_DIR"
    cat >"${RDP_DIR}/appbox.rdp" <<EOF
full address:s:${host}
server port:i:${RDP_PORT}
use redirection server name:i:1
username:s:${RDP_DOWNLOAD_USERNAME}
prompt for credentials:i:1
EOF
    chmod 0644 "${RDP_DIR}/appbox.rdp"
}

write_nginx_site() {
    local host="$1"
    local cert_domain="$2"
    local cert_dir="/etc/ssl/domains/${cert_domain}"
    local cert="${cert_dir}/fullchain.cer"
    local key_pattern="${cert_dir}/*.${cert_domain}.key"
    local key

    key="$(compgen -G "$key_pattern" | head -n 1 || true)"
    if [[ ! -f "$cert" || -z "$key" || ! -f "$key" ]]; then
        echo "appbox-configure-rdp-download: waiting for TLS files in ${cert_dir}" >&2
        return 75
    fi

    install -d -m 0755 -o root -g root /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat >"$NGINX_SITE" <<EOF
server {
    listen 443 ssl proxy_protocol;
    listen [::]:443 ssl proxy_protocol;
    server_name ${host};

    ssl_certificate           ${cert};
    ssl_certificate_key       ${key};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    access_log /var/log/nginx/appbox-rdp-download.access.log;
    error_log /var/log/nginx/appbox-rdp-download.error.log;

    location / {
        auth_basic "Appbox RDP";
        auth_basic_user_file ${HTPASSWD_FILE};
        default_type application/x-rdp;
        add_header Content-Disposition 'attachment; filename="${host}.rdp"';
        add_header Cache-Control "no-store";
        root ${RDP_DIR};
        try_files /appbox.rdp =404;
    }
}
EOF
    ln -sfn "$NGINX_SITE" "$NGINX_SITE_ENABLED"
    rm -f /etc/nginx/sites-enabled/default
}

main() {
    local host cert_domain
    host="$(rdp_hostname)"
    cert_domain="$(cert_domain_for_hostname "$host")"

    if [[ ! -f "$HTPASSWD_FILE" ]]; then
        echo "appbox-configure-rdp-download: missing $HTPASSWD_FILE; waiting for first boot password" >&2
        exit 0
    fi

    write_rdp_file "$host"
    write_nginx_site "$host" "$cert_domain"

    if nginx -t; then
        systemctl enable nginx.service >/dev/null 2>&1 || true
        systemctl restart nginx.service
    fi
}

main "$@"
