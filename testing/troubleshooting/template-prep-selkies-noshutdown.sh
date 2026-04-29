#!/usr/bin/env bash
# Run on the guest as root. Prepares the KDE/Selkies VM for templating without
# shutting it down; power off from the control panel after this completes.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log_step() {
  echo "[$1/10] $2"
}

sync_tree_without_runtime_state() {
  local src="$1"
  local dst="$2"
  [ -d "$src" ] || return 0
  install -d -m 0755 -o appbox -g appbox "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.ssh' \
      --exclude='.cache' \
      --exclude='.dbus' \
      --exclude='.Xauthority' \
      --exclude='.ICEauthority' \
      --exclude='.local/share/Trash' \
      "$src"/ "$dst"/
  else
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    rm -rf "$dst/.ssh" "$dst/.cache" "$dst/.dbus" "$dst/.Xauthority" "$dst/.ICEauthority" "$dst/.local/share/Trash"
  fi
  chown -R appbox:appbox "$dst"
}

log_step 1 "Snapshot KDE/Selkies user defaults"
install -d -m 0755 -o appbox -g appbox /defaults /defaults/home-appbox
sync_tree_without_runtime_state /home/appbox /defaults/home-appbox
sync_tree_without_runtime_state /config /defaults/home-appbox
rm -rf /defaults/home-appbox/.cache \
  /defaults/home-appbox/.config/pulse/cookie \
  /defaults/home-appbox/.local/share/Trash \
  /defaults/home-appbox/.Xauthority \
  /defaults/home-appbox/.ICEauthority 2>/dev/null || true
install -d -m 0755 -o appbox -g appbox \
  /defaults/home-appbox/Desktop \
  /defaults/home-appbox/snap/snap-store/common/.cache
chown -R appbox:appbox /defaults/home-appbox

log_step 2 "Enable Selkies units and disable legacy desktop units"
systemctl daemon-reload
systemctl enable appbox-first-boot.service selkies-setup.service selkies.service selkies-desktop.service appbox-reset-snap-namespaces.service
systemctl disable --now sddm.service appbox-configure-krdp.service 2>/dev/null || true
systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
systemctl enable NetworkManager.service NetworkManager-wait-online.service 2>/dev/null || true
chown root:root / /etc /etc/default /usr /usr/local /usr/local/sbin
chown root:root /usr/local/sbin/appbox-first-boot.sh
chmod 0750 /usr/local/sbin/appbox-first-boot.sh

log_step 3 "Optionally update packages and clean apt cache"
if [ "${SKIP_APT_UPGRADE:-0}" != "1" ]; then
  apt-get update
  apt-get -y full-upgrade
  apt-get -y autoremove --purge
fi
apt-get clean

log_step 4 "Stop runtime services for capture"
systemctl stop selkies-desktop.service selkies.service selkies-pulseaudio.service selkies-nginx.service xvfb.service 2>/dev/null || true

log_step 5 "Remove stale fstab and mount-unit state"
STASH_DIR=/var/lib/vm-image-template-stash
install -d -m 0700 "$STASH_DIR"
rm -rf "$STASH_DIR/appbox-ssh" 2>/dev/null || true
if [ -d /home/appbox/.ssh ]; then
  cp -a /home/appbox/.ssh "$STASH_DIR/appbox-ssh"
fi

if [ -f /etc/fstab ]; then
  cp -a /etc/fstab /etc/fstab.pre-template."$(date +%Y%m%d%H%M%S)"
  sed -i '/[[:space:]]virtiofs[[:space:]]/d' /etc/fstab
  sed -i '/[[:space:]]\/etc\/ssl\/domains\//d' /etc/fstab
  sed -i '/[[:space:]]\/APPBOX_DATA[[:space:]]/d' /etc/fstab
  sed -i '/[[:space:]]\/opt\/cylo\/config[[:space:]]/d' /etc/fstab
  sed -i '/[[:space:]]\/home\/appbox[[:space:]]/d' /etc/fstab
  sed -i '/^# Virtiofs mounts added by Cylo$/d' /etc/fstab
  awk 'NF || !blank {print} {blank = (NF==0)}' /etc/fstab >/etc/fstab.new
  install -m 0644 -o root -g root /etc/fstab.new /etc/fstab
  rm -f /etc/fstab.new
fi

for u in APPBOX_DATA.mount home-appbox.mount opt-cylo-config.mount; do
  systemctl disable --now "$u" 2>/dev/null || true
done
while read -r unit _; do
  [ -n "${unit:-}" ] || continue
  case "$unit" in
    etc-ssl-domains-*.mount) systemctl disable --now "$unit" 2>/dev/null || true ;;
  esac
done < <(systemctl list-unit-files --type=mount --no-legend)
rm -f /etc/systemd/system/APPBOX_DATA.mount \
  /etc/systemd/system/home-appbox.mount \
  /etc/systemd/system/opt-cylo-config.mount \
  /etc/systemd/system/etc-ssl-domains-*.mount 2>/dev/null || true
rm -f /etc/systemd/system/local-fs.target.wants/APPBOX_DATA.mount \
  /etc/systemd/system/local-fs.target.wants/home-appbox.mount \
  /etc/systemd/system/local-fs.target.wants/opt-cylo-config.mount \
  /etc/systemd/system/local-fs.target.wants/etc-ssl-domains-*.mount 2>/dev/null || true
rm -f /etc/systemd/system/local-fs.target.requires/APPBOX_DATA.mount \
  /etc/systemd/system/local-fs.target.requires/home-appbox.mount \
  /etc/systemd/system/local-fs.target.requires/opt-cylo-config.mount \
  /etc/systemd/system/local-fs.target.requires/etc-ssl-domains-*.mount 2>/dev/null || true
systemctl daemon-reload || true

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

log_step 6 "Restore rootfs SSH access and remove host-specific runtime state"
if [ -d "$STASH_DIR/appbox-ssh" ]; then
  install -d -m 0755 /home/appbox
  rm -rf /home/appbox/.ssh
  cp -a "$STASH_DIR/appbox-ssh" /home/appbox/.ssh
  chown -R appbox:appbox /home/appbox /home/appbox/.ssh
  chmod 700 /home/appbox/.ssh
  find /home/appbox/.ssh -type f -exec chmod 600 {} +
  rm -rf "$STASH_DIR/appbox-ssh"
fi
rmdir "$STASH_DIR" 2>/dev/null || true

rm -rf /var/lib/appbox-first-boot
rm -f /tmp/user_pw
rm -f /etc/appbox-rdp-download/htpasswd 2>/dev/null || true
rm -f /etc/nginx/.htpasswd 2>/dev/null || true
rm -rf /etc/ssl/appbox /etc/ssl/domains/* 2>/dev/null || true
install -d -m 0755 -o root -g root /etc/ssl/appbox /etc/ssl/domains
rm -rf /home/appbox/.cache /config/.cache /config/.local/share/Trash /home/appbox/.local/share/Trash 2>/dev/null || true
rm -f /home/appbox/.Xauthority /home/appbox/.ICEauthority /config/.Xauthority /config/.ICEauthority 2>/dev/null || true
install -d -m 0755 -o appbox -g appbox /home/appbox /config /home/appbox/Desktop /config/Desktop
install -d -m 0755 -o appbox -g appbox /home/appbox/snap/snap-store/common/.cache
chown -R appbox:appbox /home/appbox /config /defaults/home-appbox 2>/dev/null || true

log_step 7 "Trim filesystem and clean identity"
timeout 180s fstrim -av || true
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instance /var/lib/cloud/instances/* || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /root/.bash_history || true
truncate -s 0 /home/appbox/.bash_history || true
truncate -s 0 /config/.bash_history || true
rm -f /root/.zsh_history /home/appbox/.zsh_history /config/.zsh_history || true
find /root -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
journalctl --rotate || true
journalctl --vacuum-time=1s || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
install -d -m 1777 -o root -g root /tmp /var/tmp /tmp/.X11-unix

log_step 8 "Validate template state"
systemctl daemon-reload
systemctl reset-failed
systemd-analyze verify \
  /etc/systemd/system/appbox-first-boot.service \
  /etc/systemd/system/selkies-setup.service \
  /etc/systemd/system/selkies.service \
  /etc/systemd/system/selkies-desktop.service
systemctl is-enabled appbox-first-boot.service selkies-setup.service selkies.service selkies-desktop.service appbox-reset-snap-namespaces.service
systemctl is-enabled sddm.service >/dev/null 2>&1 && {
  echo "Error: sddm.service is still enabled" >&2
  exit 1
} || true
test -d /defaults/home-appbox/.config
test -d /defaults/home-appbox/Desktop
test -f /usr/share/selkies/www/index.html
test -z "$(ls /etc/ssh/ssh_host_* 2>/dev/null || true)"
test -z "$(find /etc/ssl/appbox /etc/ssl/domains -type f -print -quit 2>/dev/null || true)"
sed -n '1,80p' /etc/fstab
systemctl list-unit-files --type=mount --no-legend | awk '{print $1}' | awk '/^APPBOX_DATA\.mount$|^home-appbox\.mount$|^opt-cylo-config\.mount$|^etc-ssl-domains-.*\.mount$/' || true
systemctl --failed --no-pager || true

log_step 9 "Sync disks"
sync

log_step 10 "Ready for template capture"
echo "KDE/Selkies VPS template prep finished. Power off from the control panel when ready."
