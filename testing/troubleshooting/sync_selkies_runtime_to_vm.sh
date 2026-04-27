#!/usr/bin/env bash
# Push Selkies runtime files from this repo to a running VM (step [1/9] only; no seal/shutdown).
# Usage:
#   bash testing/troubleshooting/sync_selkies_runtime_to_vm.sh \
#     --host ubuntu26remo.tester2.appboxes.co --port 11768 \
#     --ssh-key ~/.ssh/appbox_ubuntuvps2_webtop
set -euo pipefail

USER_NAME="appbox"
SSH_KEY="${HOME}/.ssh/appbox_ubuntuvps2_webtop"
HOST=""
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    -h|--help)
      head -n 12 "$0" | tail -n 8
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$HOST" || -z "$PORT" ]]; then
  echo "Required: --host and --port" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Prefer an isolated config so Host * IdentityFile entries do not add extra keys (MaxAuthTries).
SSH_OPTS=(ssh -F /dev/null -i "$SSH_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none)
SCP_OPTS=(scp -F /dev/null -i "$SSH_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none)

echo "==> Upload Selkies runtime files"
# Empty agent path avoids ssh offering keys from a running agent when IdentitiesOnly is ignored by older tools.
export SSH_AUTH_SOCK=""

"${SCP_OPTS[@]}" -P "$PORT" \
  "${REPO_ROOT}/selkies/rootfs/etc/selkies/init-nginx.sh" \
  "${REPO_ROOT}/selkies/rootfs/etc/selkies/init-device-setup.sh" \
  "${REPO_ROOT}/selkies/rootfs/etc/systemd/system/selkies-nginx.service" \
  "${REPO_ROOT}/selkies/rootfs/etc/systemd/system/selkies.service" \
  "${REPO_ROOT}/selkies/rootfs/etc/systemd/system/selkies-setup.service" \
  "${REPO_ROOT}/selkies/rootfs/usr/local/bin/start-selkies-pulseaudio.sh" \
  "${REPO_ROOT}/selkies/rootfs/defaults/default.conf" \
  "${REPO_ROOT}/selkies/rootfs/defaults/startwm.sh" \
  "${REPO_ROOT}/selkies/rootfs/etc/default/selkies-nginx" \
  "${USER_NAME}@${HOST}:/tmp/"

"${SCP_OPTS[@]}" -P "$PORT" -r \
  "${REPO_ROOT}/selkies/rootfs/defaults/home-appbox" \
  "${USER_NAME}@${HOST}:/tmp/"

echo "==> Install on guest and reload systemd"
"${SSH_OPTS[@]}" -p "$PORT" "${USER_NAME}@${HOST}" 'sudo bash -s' <<'REMOTE_EOF'
set -euo pipefail
install -m 0755 /tmp/init-nginx.sh /etc/selkies/init-nginx.sh
install -m 0755 /tmp/init-device-setup.sh /etc/selkies/init-device-setup.sh
install -m 0644 /tmp/selkies-nginx.service /etc/systemd/system/selkies-nginx.service
install -m 0644 /tmp/selkies.service /etc/systemd/system/selkies.service
install -m 0644 /tmp/selkies-setup.service /etc/systemd/system/selkies-setup.service
install -m 0755 /tmp/start-selkies-pulseaudio.sh /usr/local/bin/start-selkies-pulseaudio.sh
install -m 0644 /tmp/default.conf /defaults/default.conf
install -m 0755 /tmp/startwm.sh /defaults/startwm.sh
install -d /etc/default
install -m 0644 /tmp/selkies-nginx /etc/default/selkies-nginx
systemctl daemon-reload

if [ -d /tmp/home-appbox ]; then
  install -d /defaults
  rm -rf /defaults/home-appbox
  cp -a /tmp/home-appbox /defaults/home-appbox
  chown -R appbox:appbox /defaults/home-appbox
  rm -rf /tmp/home-appbox
fi

systemctl restart selkies-setup.service || systemctl start selkies-setup.service
echo "selkies-setup.service: $(systemctl is-active selkies-setup.service)"
REMOTE_EOF

echo "==> Done."
