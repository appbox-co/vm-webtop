#!/bin/bash

# nginx Path
NGINX_CONFIG=/etc/nginx/sites-available/default

# user passed env vars
CPORT="${CUSTOM_PORT:-443}"
CUSER="${CUSTOM_USER:-appbox}"
SFOLDER="${SUBFOLDER:-/}"
BASIC_AUTH_VALUE="${BASIC_AUTH:-}"
SSL_WAIT_TIMEOUT_SECONDS="${SSL_WAIT_TIMEOUT_SECONDS:-1800}"
SSL_WAIT_INTERVAL_SECONDS="${SSL_WAIT_INTERVAL_SECONDS:-5}"

extract_domain_from_nginx_config() {
  local config_path="$1"
  if [ ! -f "$config_path" ]; then
    return 0
  fi

  sed -n 's|.*ssl_certificate[[:space:]]\+/etc/ssl/domains/\([^/]*\)/fullchain\.cer;.*|\1|p' "$config_path" | head -1
}

# Resolve SSL cert directory.
# Priority:
# 1. First domain folder under /etc/ssl/domains/<domain> that has valid materials
#    (search newest-to-oldest to prefer current mounts/updates)
# 2. Legacy fallback /etc/ssl/appbox, if valid
resolve_ssl_dir() {
  local resolved_dir=""
  local candidate_dir=""
  if [ -d "/etc/ssl/domains" ]; then
    while read -r candidate_dir; do
      candidate_dir="${candidate_dir%/}"
      [ -n "$candidate_dir" ] || continue
      if validate_ssl_materials "$candidate_dir"; then
        resolved_dir="$candidate_dir"
        break
      fi
    done < <(ls -1td /etc/ssl/domains/*/ 2>/dev/null || true)
  fi
  if [ -z "$resolved_dir" ] && validate_ssl_materials "/etc/ssl/appbox"; then
    resolved_dir="/etc/ssl/appbox"
  fi
  printf "%s" "$resolved_dir"
}

validate_ssl_materials() {
  local base_dir="$1"
  if [ -z "$base_dir" ] || [ ! -d "$base_dir" ]; then
    return 1
  fi

  local cert_file="${base_dir}/fullchain.cer"
  local key_file
  key_file=$(find "$base_dir" -name "*.key" -type f | head -1)

  if [ -f "$cert_file" ] && [ -n "$key_file" ] && [ -f "$key_file" ]; then
    SSL_CERT_FILE="$cert_file"
    SSL_KEY_FULL_PATH="$key_file"
    return 0
  fi
  return 1
}

SSL_BASE_DIR=""
SSL_CERT_FILE=""
SSL_KEY_FULL_PATH=""
SECONDS_WAITED=0

while true; do
  SSL_BASE_DIR="$(resolve_ssl_dir)"
  if validate_ssl_materials "$SSL_BASE_DIR"; then
    break
  fi

  if [ "$SECONDS_WAITED" -ge "$SSL_WAIT_TIMEOUT_SECONDS" ]; then
    echo "Error: SSL cert/key not ready after ${SSL_WAIT_TIMEOUT_SECONDS}s."
    echo "Last checked directory: ${SSL_BASE_DIR:-<none>}"
    echo "Expected files: fullchain.cer and *.key in a valid /etc/ssl/domains/<domain> directory (or /etc/ssl/appbox fallback)."
    exit 1
  fi

  if [ "$SECONDS_WAITED" -eq 0 ]; then
    echo "Waiting for SSL cert materials from cloud-init/provisioning..."
  fi
  sleep "$SSL_WAIT_INTERVAL_SECONDS"
  SECONDS_WAITED=$((SECONDS_WAITED + SSL_WAIT_INTERVAL_SECONDS))
done

echo "Using SSL cert directory: $SSL_BASE_DIR"
echo "Using SSL key file: $SSL_KEY_FULL_PATH"

SSL_DOMAIN_NAME=""
if [[ "$SSL_BASE_DIR" == /etc/ssl/domains/* ]]; then
  SSL_DOMAIN_NAME="$(basename "$SSL_BASE_DIR")"
fi

CURRENT_NGINX_DOMAIN="$(extract_domain_from_nginx_config /etc/nginx/sites-enabled/default)"
if [ -n "$SSL_DOMAIN_NAME" ] && [ -n "$CURRENT_NGINX_DOMAIN" ] && [ "$SSL_DOMAIN_NAME" != "$CURRENT_NGINX_DOMAIN" ]; then
  echo "Detected domain mismatch in nginx default config: expected '$SSL_DOMAIN_NAME', found '$CURRENT_NGINX_DOMAIN'. Regenerating config."
fi

# modify nginx config
cp /defaults/default.conf ${NGINX_CONFIG}
sed -i "s/PORT/$CPORT/g" ${NGINX_CONFIG}
sed -i "s|SUBFOLDER|$SFOLDER|g" ${NGINX_CONFIG}
sed -i "s|REPLACE_HOME|$HOME|g" ${NGINX_CONFIG}
sed -i "s|SSL_CERT_FILE|$SSL_CERT_FILE|g" ${NGINX_CONFIG}
sed -i "s|SSL_KEY_FILE|$SSL_KEY_FULL_PATH|g" ${NGINX_CONFIG}

# Basic auth handling:
# - Preferred: BASIC_AUTH env var with pre-hashed line (e.g. appbox:$apr1$...)
# - Fallback: PASSWORD env var (plain; hashed with APR1 here). Empty PASSWORD disables this path.
if [ -z "$BASIC_AUTH_VALUE" ] && [ -n "${PASSWORD:-}" ]; then
  BASIC_AUTH_VALUE="${CUSER}:$(openssl passwd -apr1 "${PASSWORD}")"
fi

if [ -n "$BASIC_AUTH_VALUE" ]; then
  printf "%s\n" "$BASIC_AUTH_VALUE" > /etc/nginx/.htpasswd
  chmod 640 /etc/nginx/.htpasswd
  chown root:www-data /etc/nginx/.htpasswd 2>/dev/null || chown root:root /etc/nginx/.htpasswd
  sed -i 's|^[[:space:]]*#auth_basic|  auth_basic|g' ${NGINX_CONFIG}
  sed -i 's|^[[:space:]]*#auth_basic_user_file|  auth_basic_user_file|g' ${NGINX_CONFIG}
  echo "Enabled nginx basic auth from BASIC_AUTH/PASSWORD environment."
else
  rm -f /etc/nginx/.htpasswd
  sed -i 's|^[[:space:]]*auth_basic|  #auth_basic|g' ${NGINX_CONFIG}
  sed -i 's|^[[:space:]]*auth_basic_user_file|  #auth_basic_user_file|g' ${NGINX_CONFIG}
  echo "BASIC_AUTH not set; nginx basic auth disabled."
fi

if [ -n "$SSL_DOMAIN_NAME" ]; then
  RENDERED_NGINX_DOMAIN="$(extract_domain_from_nginx_config ${NGINX_CONFIG})"
  if [ "$RENDERED_NGINX_DOMAIN" != "$SSL_DOMAIN_NAME" ]; then
    echo "Error: nginx SSL domain mismatch after render (expected '$SSL_DOMAIN_NAME', got '${RENDERED_NGINX_DOMAIN:-<empty>}')"
    exit 1
  fi
fi

# nginx-extras includes the realip module by default
mkdir -p $HOME/Desktop
chown appbox:appbox $HOME/Desktop

if [ ! -z ${DISABLE_IPV6+x} ]; then
  sed -i '/listen \[::\]/d' ${NGINX_CONFIG}
fi

if [ ! -z ${DEV_MODE+x} ]; then
  sed -i \
    -e 's:location / {:location /null {:g' \
    -e 's:location /devmode:location /:g' \
    ${NGINX_CONFIG}
fi

# copy favicon
cp /usr/share/selkies/www/icon.png /usr/share/selkies/www/favicon.ico 