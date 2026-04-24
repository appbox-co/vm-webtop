#!/usr/bin/env bash
# Run ON THE GUEST as root. Mirrors create_template.sh remote steps [1]–[8]; no shutdown.
# Expects runtime files in /tmp/: init-nginx.sh, selkies-nginx.service, selkies.service,
# start-selkies-pulseaudio.sh, default.conf, startwm.sh, selkies-nginx (for /etc/default).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[1/9] Install latest runtime files"
install -m 0755 /tmp/init-nginx.sh /etc/selkies/init-nginx.sh
install -m 0644 /tmp/selkies-nginx.service /etc/systemd/system/selkies-nginx.service
install -m 0644 /tmp/selkies.service /etc/systemd/system/selkies.service
install -m 0755 /tmp/start-selkies-pulseaudio.sh /usr/local/bin/start-selkies-pulseaudio.sh
install -m 0644 /tmp/default.conf /defaults/default.conf
install -m 0755 /tmp/startwm.sh /defaults/startwm.sh
install -d /etc/default
install -m 0644 /tmp/selkies-nginx /etc/default/selkies-nginx

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
# /home/appbox is often a virtiofs mount; unmounting drops live data (e.g. .ssh).
# Stash authorized_keys on the rootfs before unmount so SSH still works until shutdown.
STASH_DIR=/var/lib/vm-image-template-stash
install -d -m 0700 "$STASH_DIR"
rm -rf "$STASH_DIR/appbox-ssh" 2>/dev/null || true
if [ -d /home/appbox/.ssh ]; then
  cp -a /home/appbox/.ssh "$STASH_DIR/appbox-ssh"
fi

cp -a /etc/fstab /etc/fstab.pre-template."$(date +%Y%m%d%H%M%S)"
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

systemctl daemon-reload || true
# Close handles on TLS paths (nginx/selkies); otherwise lazy umount may never drop virtiofs.
systemctl stop selkies-nginx.service 2>/dev/null || true
systemctl stop nginx.service 2>/dev/null || true
sleep 1

# Live virtiofs mounts survive fstab edits; lazy-unmount repeatedly before rm.
if command -v findmnt >/dev/null 2>&1; then
  for _ in $(seq 1 25); do
    umount -R -l /etc/ssl/domains 2>/dev/null || true
    while read -r mnt; do
      [ -n "${mnt:-}" ] || continue
      umount -l "$mnt" 2>/dev/null || true
    done < <(findmnt -R /etc/ssl/domains -n -o TARGET 2>/dev/null | sort -u | sort -r)
    while read -r mnt; do
      [ -n "${mnt:-}" ] || continue
      [[ "$mnt" == *ssl/domains* ]] || continue
      umount -l "$mnt" 2>/dev/null || true
    done < <(findmnt -n -o TARGET -t virtiofs 2>/dev/null || true)
    for m in /APPBOX_DATA /opt/cylo/config /home/appbox; do
      findmnt -n "$m" >/dev/null 2>&1 && umount -l "$m" 2>/dev/null || true
    done
    if ! findmnt -R /etc/ssl/domains -n -o TARGET 2>/dev/null | grep -q .; then
      break
    fi
    sleep 0.5
  done
fi

rm -rf /etc/ssl/domains/*
if find /etc/ssl/domains -mindepth 1 -print -quit | grep -q .; then
  echo "Error: /etc/ssl/domains is not empty after cleanup" >&2
  find /etc/ssl/domains -mindepth 1 -maxdepth 2 -print >&2 || true
  exit 1
fi

echo "[3b/9] Placeholder TLS for sealed image (init-nginx waits for cert material)"
# Real certs are injected via virtiofs on provisioned VMs; without this, init-nginx.sh
# loops on sleep until SSL_WAIT_TIMEOUT_SECONDS.
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

echo "[9/9] Skipping shutdown (power off from control panel when ready)."
sync
echo "VPS template prep finished."
