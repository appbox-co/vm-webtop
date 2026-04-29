#!/usr/bin/env bash
# Run ON THE GUEST as root. Prepares the GNOME/RDP VM for templating without
# shutting it down; power off from the control panel after this completes.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log_step() {
  echo "[$1/10] $2"
}

copy_if_present() {
  local src="$1"
  local dst="$2"
  local mode="$3"
  if [ -f "$src" ]; then
    install -m "$mode" -o root -g root "$src" "$dst"
  fi
}

log_step 1 "Install latest GNOME/RDP runtime files from /tmp when present"
install -d -m 0755 /usr/local/sbin /etc/systemd/system /etc/default /etc/appbox-rdp-download /var/lib/appbox-rdp-download
install -d -m 0750 -o gnome-remote-desktop -g gnome-remote-desktop /etc/gnome-remote-desktop
copy_if_present /tmp/appbox-first-boot.sh /usr/local/sbin/appbox-first-boot.sh 0750
copy_if_present /tmp/appbox-configure-gnome-rdp.sh /usr/local/sbin/appbox-configure-gnome-rdp.sh 0750
copy_if_present /tmp/appbox-first-boot.service /etc/systemd/system/appbox-first-boot.service 0644
copy_if_present /tmp/appbox-configure-gnome-rdp.service /etc/systemd/system/appbox-configure-gnome-rdp.service 0644
copy_if_present /tmp/gnome-remote-desktop-appbox /etc/default/gnome-remote-desktop-appbox 0644
copy_if_present /tmp/appbox-configure-rdp-download.sh /usr/local/sbin/appbox-configure-rdp-download.sh 0750
copy_if_present /tmp/appbox-rdp-download.service /etc/systemd/system/appbox-rdp-download.service 0644
copy_if_present /tmp/appbox-rdp-download /etc/default/appbox-rdp-download 0644

# Reset host-specific runtime values. First boot will apply RDP_PORT from the
# provisioned environment and /tmp/user_pw from cloud-init.
cat >/etc/default/gnome-remote-desktop-appbox <<'EOF'
# shellcheck shell=bash disable=SC2034
RDP_PORT=3389
GRD_RDP_USERNAME='appbox'
EOF

systemctl daemon-reload
systemctl enable appbox-first-boot.service appbox-configure-gnome-rdp.service appbox-rdp-download.service gdm3.service gnome-remote-desktop.service
systemctl --global enable gnome-remote-desktop-handover.service 2>/dev/null || true
systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
systemctl enable NetworkManager.service NetworkManager-wait-online.service 2>/dev/null || true
if [ -f /var/lib/snapd/desktop/applications/snap-store_snap-store.desktop ]; then
  install -m 0644 -o root -g root \
    /var/lib/snapd/desktop/applications/snap-store_snap-store.desktop \
    /usr/share/applications/snap-store_snap-store.desktop
  sed -i 's/^Categories=.*/Categories=System;PackageManager;/' /usr/share/applications/snap-store_snap-store.desktop
  grep -q '^StartupNotify=' /usr/share/applications/snap-store_snap-store.desktop || printf 'StartupNotify=true\n' >>/usr/share/applications/snap-store_snap-store.desktop
fi
update-desktop-database /usr/share/applications 2>/dev/null || true
dconf update 2>/dev/null || true

log_step 2 "Update package state and clean package cache"
if [ "${SKIP_APT_UPGRADE:-0}" != "1" ]; then
  apt-get update
  apt-get -y full-upgrade
fi

echo "Purge unused kernel packages"
CURRENT_KERNEL="$(uname -r)"
mapfile -t OLD_KERNEL_PKGS < <(
  dpkg -l | awk '/^ii/ && ($2 ~ /^linux-(image|headers|modules|modules-extra)-[0-9]/) {print $2}' \
  | grep -v -- "$CURRENT_KERNEL" || true
)
if [ "${#OLD_KERNEL_PKGS[@]}" -gt 0 ]; then
  apt-get -y purge "${OLD_KERNEL_PKGS[@]}"
fi
# Keep the kernel metapackage installed so templated VMs continue to receive
# kernel updates; purging stale header packages can otherwise remove it.
apt-get -y install linux-virtual
apt-get -y autoremove --purge
apt-get clean

log_step 3 "Stop desktop/RDP services before removing provision-time mounts"
systemctl stop nginx.service appbox-rdp-download.service 2>/dev/null || true
systemctl stop gnome-remote-desktop.service 2>/dev/null || true
systemctl stop gdm3.service 2>/dev/null || true
systemctl stop selkies-nginx.service selkies.service selkies-setup.service xvfb.service 2>/dev/null || true

log_step 4 "Remove stale fstab and mount-unit state"
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

log_step 5 "Remove host-specific GNOME Remote Desktop state"
rm -f /etc/gnome-remote-desktop/rdp-secret
rm -f /var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/rdp-tls.key
rm -f /var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/rdp-tls.crt
rm -rf /var/lib/appbox-first-boot
rm -f /etc/appbox-rdp-download/htpasswd /etc/appbox-rdp-download/auth
rm -rf /var/lib/appbox-rdp-download
rm -f /etc/nginx/sites-enabled/appbox-rdp-download /etc/nginx/sites-available/appbox-rdp-download
systemctl disable nginx.service 2>/dev/null || true
rm -f /tmp/user_pw

log_step 6 "Restore appbox SSH access on rootfs after virtiofs home unmount"
if [ -d "$STASH_DIR/appbox-ssh" ]; then
  install -d -m 0755 /home/appbox
  rm -rf /home/appbox/.ssh
  cp -a "$STASH_DIR/appbox-ssh" /home/appbox/.ssh
  chown -R appbox:appbox /home/appbox /home/appbox/.ssh
  chmod 700 /home/appbox/.ssh
  find /home/appbox/.ssh -type f -exec chmod 600 {} +
  rm -rf "$STASH_DIR/appbox-ssh"
fi
install -d -m 0755 -o appbox -g appbox /home/appbox/snap /home/appbox/snap/snap-store /home/appbox/snap/snap-store/common /home/appbox/snap/snap-store/common/.cache
chown -R appbox:appbox /home/appbox/snap
rmdir "$STASH_DIR" 2>/dev/null || true

log_step 7 "Trim filesystem"
timeout 180s fstrim -av || true

log_step 8 "Clean cloud-init, machine identity, logs, and shell history"
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instance /var/lib/cloud/instances/* || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

rm -f /etc/ssh/ssh_host_*
truncate -s 0 /root/.bash_history || true
truncate -s 0 /home/appbox/.bash_history || true
rm -f /root/.zsh_history /home/appbox/.zsh_history || true
find /root -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
journalctl --rotate || true
journalctl --vacuum-time=1s || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
install -d -m 1777 -o root -g root /tmp /var/tmp /tmp/.X11-unix

log_step 9 "Validate template state"
systemctl daemon-reload
systemctl reset-failed
install -d -m 0750 -o gnome-remote-desktop -g gnome-remote-desktop /etc/gnome-remote-desktop
if [ -f /etc/gnome-remote-desktop/grd.conf ]; then
  chown gnome-remote-desktop:gnome-remote-desktop /etc/gnome-remote-desktop/grd.conf
  chmod 0664 /etc/gnome-remote-desktop/grd.conf
fi
systemd-analyze verify /etc/systemd/system/appbox-first-boot.service /etc/systemd/system/appbox-configure-gnome-rdp.service /etc/systemd/system/appbox-rdp-download.service
systemctl is-enabled appbox-first-boot.service appbox-configure-gnome-rdp.service appbox-rdp-download.service gdm3.service gnome-remote-desktop.service
systemctl --global is-enabled gnome-remote-desktop-handover.service 2>/dev/null || true
sed -n '1,80p' /etc/fstab
systemctl list-unit-files --type=mount --no-legend | awk '{print $1}' | awk '/^APPBOX_DATA\.mount$|^home-appbox\.mount$|^opt-cylo-config\.mount$|^etc-ssl-domains-.*\.mount$/' || true
systemctl --failed --no-pager || true

log_step 10 "Ready for template capture"
sync
echo "GNOME/RDP VPS template prep finished. Power off from the control panel when ready."
