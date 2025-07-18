#!/bin/bash

# nginx Path
NGINX_CONFIG=/etc/nginx/sites-available/default

# user passed env vars
CPORT="${CUSTOM_PORT:-443}"
CUSER="${CUSTOM_USER:-abc}"
SFOLDER="${SUBFOLDER:-/}"

# Find SSL key file in /etc/ssl/appbox/
SSL_KEY_FILE=""
if [ -d "/etc/ssl/appbox" ]; then
  SSL_KEY_FULL_PATH=$(find /etc/ssl/appbox -name "*.key" -type f | head -1)
  if [ -z "$SSL_KEY_FULL_PATH" ]; then
    echo "Error: No SSL key file found in /etc/ssl/appbox/"
    exit 1
  fi
  SSL_KEY_FILE=$(basename "$SSL_KEY_FULL_PATH")
  echo "Using SSL key file: $SSL_KEY_FILE"
else
  echo "Error: /etc/ssl/appbox directory not found"
  exit 1
fi

# Check if fullchain.cer exists
if [ ! -f "/etc/ssl/appbox/fullchain.cer" ]; then
  echo "Error: /etc/ssl/appbox/fullchain.cer not found"
  exit 1
fi

# modify nginx config
cp /defaults/default.conf ${NGINX_CONFIG}
sed -i "s/PORT/$CPORT/g" ${NGINX_CONFIG}
sed -i "s|SUBFOLDER|$SFOLDER|g" ${NGINX_CONFIG}
sed -i "s|REPLACE_HOME|$HOME|g" ${NGINX_CONFIG}
sed -i "s|SSL_KEY_FILE|$SSL_KEY_FILE|g" ${NGINX_CONFIG}

# nginx-extras includes the realip module by default
mkdir -p $HOME/Desktop
chown abc:abc $HOME/Desktop

if [ ! -z ${DISABLE_IPV6+x} ]; then
  sed -i '/listen \[::\]/d' ${NGINX_CONFIG}
fi

if [ ! -z ${PASSWORD+x} ]; then
  printf "${CUSER}:$(openssl passwd -apr1 ${PASSWORD})\n" > /etc/nginx/.htpasswd
  sed -i 's/#//g' ${NGINX_CONFIG}
fi

if [ ! -z ${DEV_MODE+x} ]; then
  sed -i \
    -e 's:location / {:location /null {:g' \
    -e 's:location /devmode:location /:g' \
    ${NGINX_CONFIG}
fi

# copy favicon
cp /usr/share/selkies/www/icon.png /usr/share/selkies/www/favicon.ico 