#!/bin/bash

# Enable error handling and logging
set -e
exec > >(tee -a /tmp/init-selkies-config.log) 2>&1
echo "$(date): Starting selkies configuration setup..."

# default file copies first run
if [[ ! -f /config/.config/openbox/autostart ]]; then
  mkdir -p /config/.config/openbox
  cp /defaults/autostart /config/.config/openbox/autostart
  chown -R appbox:appbox /config/.config/openbox
fi
if [[ ! -f /config/.config/openbox/menu.xml ]]; then
  mkdir -p /config/.config/openbox && \
  cp /defaults/menu.xml /config/.config/openbox/menu.xml && \
  chown -R appbox:appbox /config/.config
fi

# XDG Home
if [ ! -d "${HOME}/.XDG" ]; then
  mkdir -p ${HOME}/.XDG
  chown appbox:appbox ${HOME}/.XDG
fi

# Remove window borders
if [[ ! -z ${NO_DECOR+x} ]] && [[ ! -f /decorlock ]]; then
  sed -i \
    's|</applications>|  <application class="*"> <decor>no</decor> </application>\n</applications>|' \
    /etc/xdg/openbox/rc.xml
  touch /decorlock
fi

# Fullscreen everything in openbox unless the user explicitly disables it
if [[ ! -z ${NO_FULL+x} ]] && [[ ! -f /fulllock ]]; then
  sed -i \
    's|</applications>|  <application class="*"> <maximized>true</maximized> </application>\n</applications>|' \
    /etc/xdg/openbox/rc.xml
  touch /fulllock
fi

# Proot apps folder
if [[ ! -f $HOME/.local/bin/pversion ]]; then
  mkdir -p $HOME/.local/bin
  cp /proot-apps/* ${HOME}/.local/bin/
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc
  chown appbox:appbox \
    ${HOME}/.bashrc \
    ${HOME}/.local/ \
    ${HOME}/.local/bin \
    ${HOME}/.local/bin/{ncat,proot-apps,proot,jq,pversion}
elif ! diff -q /proot-apps/pversion ${HOME}/.local/bin/pversion > /dev/null; then
  cp /proot-apps/* ${HOME}/.local/bin/
  chown appbox:appbox ${HOME}/.local/bin/{ncat,proot-apps,proot,jq,pversion}
fi

# Wait for device setup to complete (with timeout)
echo "Waiting for device setup to complete..."
TIMEOUT=30
COUNTER=0
while [[ ! -f /tmp/selkies_js.log ]] && [[ $COUNTER -lt $TIMEOUT ]]; do
  sleep 0.1
  COUNTER=$((COUNTER + 1))
done

if [[ ! -f /tmp/selkies_js.log ]]; then
  echo "Warning: Device setup did not complete within ${TIMEOUT} seconds, creating log file manually"
  touch /tmp/selkies_js.log
  chmod 666 /tmp/selkies_js.log
  chown appbox:appbox /tmp/selkies_js.log 2>/dev/null || true
else
  echo "Device setup completed successfully"
fi

# Manifest creation
echo "{
  \"name\": \"${TITLE}\",
  \"short_name\": \"${TITLE}\",
  \"manifest_version\": 2,
  \"version\": \"1.0.0\",
  \"display\": \"fullscreen\",
  \"background_color\": \"#000000\",
  \"theme_color\": \"#000000\",
  \"icons\": [
    {
      \"src\": \"icon.png\",
      \"type\": \"image/png\",
      \"sizes\": \"180x180\"
    }
  ],
  \"start_url\": \"/\"
}" > /usr/share/selkies/www/manifest.json

# Create PID file for audio setup
echo $$ > /defaults/pid

echo "$(date): Selkies configuration setup completed successfully" 