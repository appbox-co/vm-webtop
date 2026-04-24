#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash testing/troubleshooting/create_template.sh \
    --host <vm-host> \
    --port <vm-ssh-port> \
    --src-image <source-qcow2> \
    --dst-image <template-output-image> \
    [--user appbox] \
    [--ssh-key ~/.ssh/appbox_ubuntuvps2_webtop] \
    [--tmp-root /cylostore/disk16/qemu-tmp]

What this script does:
  1) Pushes latest Selkies runtime files from this repo to the VM
  2) Applies boot-race/domain fixes and verifies services
  3) Cleans VM for templating (fstab/mount units/cloud-init/machine-id/ssh keys/history)
  4) Shuts VM down
  5) Builds compressed qcow2 template with qemu-img convert -c
EOF
}

USER_NAME="appbox"
SSH_KEY="${HOME}/.ssh/appbox_ubuntuvps2_webtop"
TMP_ROOT="/cylostore/disk16/qemu-tmp"
HOST=""
PORT=""
SRC_IMAGE=""
DST_IMAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --src-image) SRC_IMAGE="$2"; shift 2 ;;
    --dst-image) DST_IMAGE="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --tmp-root) TMP_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$HOST" || -z "$PORT" || -z "$SRC_IMAGE" || -z "$DST_IMAGE" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi

if [[ ! -f "$SRC_IMAGE" ]]; then
  echo "Source image not found: $SRC_IMAGE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ssh_cmd() {
  ssh -tt \
    -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -p "$PORT" \
    "${USER_NAME}@${HOST}" "$@"
}

scp_cmd() {
  scp \
    -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -P "$PORT" \
    "$@"
}

echo "==> Upload latest Selkies files to VM"
scp_cmd \
  "${REPO_ROOT}/selkies/rootfs/etc/selkies/init-nginx.sh" \
  "${REPO_ROOT}/selkies/rootfs/etc/systemd/system/selkies-nginx.service" \
  "${REPO_ROOT}/selkies/rootfs/etc/systemd/system/selkies.service" \
  "${REPO_ROOT}/selkies/rootfs/usr/local/bin/start-selkies-pulseaudio.sh" \
  "${REPO_ROOT}/selkies/rootfs/defaults/default.conf" \
  "${REPO_ROOT}/selkies/rootfs/defaults/startwm.sh" \
  "${USER_NAME}@${HOST}:/tmp/"

echo "==> Apply fixes + seal VM + shutdown"
set +e
ssh_cmd "sudo bash -s" <<'REMOTE_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[1/9] Install latest runtime files"
install -m 0755 /tmp/init-nginx.sh /etc/selkies/init-nginx.sh
install -m 0644 /tmp/selkies-nginx.service /etc/systemd/system/selkies-nginx.service
install -m 0644 /tmp/selkies.service /etc/systemd/system/selkies.service
install -m 0755 /tmp/start-selkies-pulseaudio.sh /usr/local/bin/start-selkies-pulseaudio.sh
install -m 0644 /tmp/default.conf /defaults/default.conf
install -m 0755 /tmp/startwm.sh /defaults/startwm.sh

echo "[2/9] Update package state"
apt-get update
apt-get -y full-upgrade
apt-get -y install xclip

echo "[2b/9] Purge unused kernel packages"
CURRENT_KERNEL="$(uname -r)"
mapfile -t OLD_KERNEL_PKGS < <(
  dpkg -l | awk '/^ii/ && ($2 ~ /^linux-(image|headers|modules|modules-extra)-[0-9]/) {print $2}' \
  | grep -v -- "$CURRENT_KERNEL" || true
)
if [ "${#OLD_KERNEL_PKGS[@]}" -gt 0 ]; then
  apt-get -y purge "${OLD_KERNEL_PKGS[@]}"
fi
apt-get -y autoremove --purge
apt-get clean

echo "[3/9] Remove stale fstab and mount-unit state"
STASH_DIR=/var/lib/vm-image-template-stash
install -d -m 0700 "$STASH_DIR"
rm -rf "$STASH_DIR/appbox-ssh" 2>/dev/null || true
if [ -d /home/appbox/.ssh ]; then
  cp -a /home/appbox/.ssh "$STASH_DIR/appbox-ssh"
fi

cp -a /etc/fstab /etc/fstab.pre-template.$(date +%Y%m%d%H%M%S)
sed -i '/[[:space:]]virtiofs[[:space:]]/d' /etc/fstab
sed -i '/[[:space:]]\/etc\/ssl\/domains\//d' /etc/fstab
sed -i '/[[:space:]]\/APPBOX_DATA[[:space:]]/d' /etc/fstab
sed -i '/[[:space:]]\/opt\/cylo\/config[[:space:]]/d' /etc/fstab
sed -i '/[[:space:]]\/home\/appbox[[:space:]]/d' /etc/fstab
sed -i '/^# Virtiofs mounts added by Cylo$/d' /etc/fstab
awk 'NF || !blank {print} {blank = (NF==0)}' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab

for u in APPBOX_DATA.mount home-appbox.mount opt-cylo-config.mount; do
  systemctl disable --now "$u" 2>/dev/null || true
done
while read -r unit _; do
  [ -n "${unit:-}" ] || continue
  case "$unit" in
    etc-ssl-domains-*.mount) systemctl disable --now "$unit" 2>/dev/null || true ;;
  esac
done < <(systemctl list-unit-files --type=mount --no-legend)
rm -f /etc/systemd/system/APPBOX_DATA.mount /etc/systemd/system/home-appbox.mount /etc/systemd/system/opt-cylo-config.mount /etc/systemd/system/etc-ssl-domains-*.mount 2>/dev/null || true
rm -f /etc/systemd/system/local-fs.target.wants/APPBOX_DATA.mount /etc/systemd/system/local-fs.target.wants/home-appbox.mount /etc/systemd/system/local-fs.target.wants/opt-cylo-config.mount /etc/systemd/system/local-fs.target.wants/etc-ssl-domains-*.mount 2>/dev/null || true
rm -f /etc/systemd/system/local-fs.target.requires/APPBOX_DATA.mount /etc/systemd/system/local-fs.target.requires/home-appbox.mount /etc/systemd/system/local-fs.target.requires/opt-cylo-config.mount /etc/systemd/system/local-fs.target.requires/etc-ssl-domains-*.mount 2>/dev/null || true

# Unmount nested SSL domain mounts first; stale virtiofs mountpoints can survive
# rm -rf and cause cert resolution to pick old/incomplete domain folders.
if command -v findmnt >/dev/null 2>&1; then
  for _ in $(seq 1 10); do
    while read -r mnt; do
      [ -n "${mnt:-}" ] || continue
      umount -l "$mnt" 2>/dev/null || true
    done < <(findmnt -R /etc/ssl/domains -n -o TARGET 2>/dev/null | sort -r)
    for m in /APPBOX_DATA /opt/cylo/config /home/appbox; do
      findmnt -n "$m" >/dev/null 2>&1 && umount -l "$m" 2>/dev/null || true
    done
    sleep 0.4
  done
fi

rm -rf /etc/ssl/domains/*
if find /etc/ssl/domains -mindepth 1 -print -quit | grep -q .; then
  echo "Error: /etc/ssl/domains is not empty after cleanup" >&2
  find /etc/ssl/domains -mindepth 1 -maxdepth 2 -print >&2 || true
  exit 1
fi

echo "[3b/9] Placeholder TLS for sealed image (init-nginx waits for cert material)"
install -d -m 0755 /etc/ssl/appbox
openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
  -subj "/CN=sealed-template.invalid" \
  -keyout /etc/ssl/appbox/sealed-template.key \
  -out /etc/ssl/appbox/fullchain.cer 2>/dev/null
chmod 0644 /etc/ssl/appbox/fullchain.cer
chmod 0600 /etc/ssl/appbox/sealed-template.key

echo "[4/9] Reload and validate Selkies stack"
systemctl daemon-reload
systemctl reset-failed
systemctl restart selkies-nginx.service
systemctl restart selkies.service
sleep 3
systemctl is-active selkies-nginx.service
systemctl is-active selkies.service
nginx -t

echo "[4b/9] Restore appbox .ssh on rootfs (after virtiofs home unmount)"
if [ -d "$STASH_DIR/appbox-ssh" ]; then
  install -d -m 0755 /home/appbox
  rm -rf /home/appbox/.ssh
  cp -a "$STASH_DIR/appbox-ssh" /home/appbox/.ssh
  chown -R appbox:appbox /home/appbox /home/appbox/.ssh
  chmod 700 /home/appbox/.ssh
  rm -rf "$STASH_DIR/appbox-ssh"
fi
rmdir "$STASH_DIR" 2>/dev/null || true

echo "[5/9] Trim (bounded; don't hang template pipeline)"
timeout 180s fstrim -av || true

echo "[6/9] Clean cloud-init and identity"
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instance /var/lib/cloud/instances/* || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "[7/9] Remove host SSH keys + shell history"
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /root/.bash_history || true
truncate -s 0 /home/appbox/.bash_history || true
rm -f /root/.zsh_history /home/appbox/.zsh_history || true
find /root -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +

echo "[8/9] Final pre-shutdown checks"
sed -n '1,80p' /etc/fstab
systemctl list-unit-files --type=mount --no-legend | awk '{print $1}' | awk '/^APPBOX_DATA\.mount$|^home-appbox\.mount$|^opt-cylo-config\.mount$|^etc-ssl-domains-.*\.mount$/' || true
systemctl --failed --no-pager || true

echo "[9/9] Shutdown"
sync
shutdown -h now
REMOTE_EOF
set -e

echo "==> Wait for VM to power off"
for _ in $(seq 1 30); do
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$PORT" "${USER_NAME}@${HOST}" "echo up" >/dev/null 2>&1; then
    sleep 2
  else
    break
  fi
done

if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$PORT" "${USER_NAME}@${HOST}" "echo up" >/dev/null 2>&1; then
  echo "VM is still reachable; aborting image conversion." >&2
  exit 1
fi

echo "==> Build compressed template image with qemu-img"
mkdir -p "$TMP_ROOT" "$(dirname "$DST_IMAGE")"
TMP_IMAGE="${TMP_ROOT}/$(basename "$DST_IMAGE").tmp"
qemu-img info "$SRC_IMAGE"
qemu-img convert -p -f qcow2 -O qcow2 -c -S 4k "$SRC_IMAGE" "$TMP_IMAGE"
qemu-img info "$TMP_IMAGE"
qemu-img check "$TMP_IMAGE"
mv -f "$TMP_IMAGE" "$DST_IMAGE"

echo "==> Final template info"
ls -lah "$SRC_IMAGE" "$DST_IMAGE"
qemu-img info "$DST_IMAGE"
echo "Template creation complete."
