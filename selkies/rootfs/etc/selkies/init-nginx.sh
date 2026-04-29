#!/bin/bash

# nginx Path
NGINX_CONFIG=/etc/nginx/sites-available/default

# user passed env vars
CPORT="${CUSTOM_PORT:-443}"
CUSER="${CUSTOM_USER:-appbox}"
SFOLDER="${SUBFOLDER:-/vnc}"

sed_escape() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

configure_subfolder_paths() {
  local raw="$1"
  if [ -z "$raw" ] || [ "$raw" = "/" ]; then
    SUBFOLDER_REDIRECT=""
    APP_ROOT="/"
    APP_DEVMODE="/devmode"
    APP_WEBSOCKET="/websocket"
    APP_FILES="/files"
    APP_50X="/50x.html"
    return
  fi

  raw="/${raw#/}"
  raw="${raw%/}"
  SUBFOLDER_REDIRECT="location = ${raw} { return 302 ${raw}/; }"
  APP_ROOT="${raw}/"
  APP_DEVMODE="${raw}/devmode"
  APP_WEBSOCKET="${raw}/websocket"
  APP_FILES="${raw}/files"
  APP_50X="${raw}/50x.html"
}

detect_server_name() {
  if [ -n "${SELKIES_SERVER_NAME:-}" ]; then
    printf '%s' "$SELKIES_SERVER_NAME"
    return
  fi
  hostname -f 2>/dev/null || hostname
}

cert_domain_for_hostname() {
  local host="$1"
  if [[ "$host" == *.appboxes.co ]]; then
    # Appboxes wildcard certs are stored by base customer domain.
    printf '%s' "${host#*.}"
  else
    printf '%s' "$host"
  fi
}

is_appboxes_hostname() {
  local host="$1"
  [[ "$host" == *.appboxes.co ]]
}

is_self_signed_cert() {
  local cert="$1"
  local subject issuer
  subject="$(openssl x509 -in "$cert" -noout -subject 2>/dev/null || true)"
  issuer="$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null || true)"
  [[ -n "$subject" && -n "$issuer" && "${subject#subject=}" == "${issuer#issuer=}" ]]
}

select_cert_from_dir() {
  local dir="$1"
  local allow_self_signed="${2:-false}"
  local cert="${dir}/fullchain.cer"
  local key

  if [ ! -f "$cert" ]; then
    return 1
  fi

  key="$(find "$dir" -maxdepth 1 -name "*.key" -type f | head -1)"
  if [ -z "$key" ]; then
    echo "Found ${cert}, but no SSL key file in ${dir}"
    return 1
  fi

  if [ "$allow_self_signed" != "true" ]; then
    if [ "$(basename "$key")" = "appbox-selfsigned.key" ] || is_self_signed_cert "$cert"; then
      echo "Ignoring self-signed certificate in ${dir}; waiting for platform certificate"
      return 1
    fi
  fi

  SSL_CERT_FILE="$cert"
  SSL_KEY_FULL_PATH="$key"
  return 0
}

SERVER_NAME="$(detect_server_name)"
CERT_DOMAIN="${SELKIES_CERT_DOMAIN:-$(cert_domain_for_hostname "$SERVER_NAME")}"
DOMAIN_SSL_DIR="/etc/ssl/domains/${CERT_DOMAIN}"
FALLBACK_SSL_DIR="/etc/ssl/appbox"
PLATFORM_CERT_WAIT_SECONDS="${SELKIES_CERT_WAIT_SECONDS:-120}"
configure_subfolder_paths "$SFOLDER"

SSL_CERT_FILE=""
SSL_KEY_FULL_PATH=""

if is_appboxes_hostname "$SERVER_NAME"; then
  for _ in $(seq 0 "$PLATFORM_CERT_WAIT_SECONDS"); do
    if select_cert_from_dir "$DOMAIN_SSL_DIR" false || select_cert_from_dir "$FALLBACK_SSL_DIR" false; then
      break
    fi
    sleep 1
  done
  if [ -z "$SSL_CERT_FILE" ]; then
    echo "Error: No platform certificate found for ${SERVER_NAME} (checked ${DOMAIN_SSL_DIR} and ${FALLBACK_SSL_DIR})"
    exit 1
  fi
elif select_cert_from_dir "$DOMAIN_SSL_DIR" false; then
  :
elif select_cert_from_dir "$FALLBACK_SSL_DIR" true; then
  :
else
  echo "No platform certificate found for ${CERT_DOMAIN}; generating temporary self-signed certificate"
  mkdir -p "$FALLBACK_SSL_DIR"
  SSL_CERT_FILE="${FALLBACK_SSL_DIR}/fullchain.cer"
  SSL_KEY_FULL_PATH="${FALLBACK_SSL_DIR}/appbox-selfsigned.key"
  openssl req -x509 -nodes -newkey rsa:3072 \
    -keyout "$SSL_KEY_FULL_PATH" \
    -out "$SSL_CERT_FILE" \
    -days 825 -batch \
    -subj "/CN=${SERVER_NAME}"
  chmod 600 "$SSL_KEY_FULL_PATH"
fi

if [ -z "$SSL_KEY_FULL_PATH" ]; then
  echo "Error: No SSL key file found"
  exit 1
fi
echo "Using server_name: $SERVER_NAME"
echo "Using SSL certificate: $SSL_CERT_FILE"
echo "Using SSL key: $SSL_KEY_FULL_PATH"

# modify nginx config
cp /defaults/default.conf "${NGINX_CONFIG}"
sed -i "s/PORT/$CPORT/g" "${NGINX_CONFIG}"
sed -i "s|SERVER_NAME|$(sed_escape "$SERVER_NAME")|g" "${NGINX_CONFIG}"
sed -i "s|SUBFOLDER_REDIRECT|$(sed_escape "$SUBFOLDER_REDIRECT")|g" "${NGINX_CONFIG}"
sed -i "s|APP_ROOT|$(sed_escape "$APP_ROOT")|g" "${NGINX_CONFIG}"
sed -i "s|APP_DEVMODE|$(sed_escape "$APP_DEVMODE")|g" "${NGINX_CONFIG}"
sed -i "s|APP_WEBSOCKET|$(sed_escape "$APP_WEBSOCKET")|g" "${NGINX_CONFIG}"
sed -i "s|APP_FILES|$(sed_escape "$APP_FILES")|g" "${NGINX_CONFIG}"
sed -i "s|APP_50X|$(sed_escape "$APP_50X")|g" "${NGINX_CONFIG}"
sed -i "s|REPLACE_HOME|$(sed_escape "$HOME")|g" "${NGINX_CONFIG}"
sed -i "s|SSL_CERT_FILE|$(sed_escape "$SSL_CERT_FILE")|g" "${NGINX_CONFIG}"
sed -i "s|SSL_KEY_FILE|$(sed_escape "$SSL_KEY_FULL_PATH")|g" "${NGINX_CONFIG}"

# nginx-extras includes the realip module by default
mkdir -p "$HOME/Desktop"
chown appbox:appbox "$HOME/Desktop"

if [ ! -z ${DISABLE_IPV6+x} ]; then
  sed -i '/listen \[::\]/d' "${NGINX_CONFIG}"
fi

if [ -n "${BASIC_AUTH:-}" ]; then
  if [[ "$BASIC_AUTH" == *:* ]]; then
    printf '%s\n' "$BASIC_AUTH" > /etc/nginx/.htpasswd
  else
    printf '%s:%s\n' "$CUSER" "$(openssl passwd -apr1 "$BASIC_AUTH")" > /etc/nginx/.htpasswd
  fi
  chmod 640 /etc/nginx/.htpasswd
  chown root:www-data /etc/nginx/.htpasswd 2>/dev/null || true
  sed -i \
    -e 's|^[[:space:]]*#auth_basic_user_file|  auth_basic_user_file|' \
    -e 's|^[[:space:]]*#auth_basic[[:space:]]|  auth_basic               |' \
    "${NGINX_CONFIG}"
elif [ -n "${PASSWORD:-}" ]; then
  printf '%s:%s\n' "$CUSER" "$(openssl passwd -apr1 "$PASSWORD")" > /etc/nginx/.htpasswd
  chmod 640 /etc/nginx/.htpasswd
  chown root:www-data /etc/nginx/.htpasswd 2>/dev/null || true
  sed -i \
    -e 's|^[[:space:]]*#auth_basic_user_file|  auth_basic_user_file|' \
    -e 's|^[[:space:]]*#auth_basic[[:space:]]|  auth_basic               |' \
    "${NGINX_CONFIG}"
fi

if [ ! -z ${DEV_MODE+x} ]; then
  sed -i \
    -e 's:location / {:location /null {:g' \
    -e 's:location /devmode:location /:g' \
    "${NGINX_CONFIG}"
fi

# copy favicon
cp /usr/share/selkies/www/icon.png /usr/share/selkies/www/favicon.ico 