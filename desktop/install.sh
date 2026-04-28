#!/bin/bash
# Ubuntu 24.04 / 26.04 — GNOME desktop + GDM + GNOME Remote Desktop (RDP / headless login).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="${SCRIPT_DIR}/rootfs"
LOG_TAG="[desktop]"

info() { echo -e "\033[0;34m${LOG_TAG}\033[0m $*"; }
ok() { echo -e "\033[0;32m${LOG_TAG}\033[0m $*"; }
err() { echo -e "\033[0;31m${LOG_TAG}\033[0m $*" >&2; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root (sudo ./install.sh)"
    exit 1
fi

configure_apt_sandbox() {
    local f="/etc/apt/apt.conf.d/01ubuntu-vm-webtop-apt-sandbox.conf"
    if [[ ! -f "$f" ]]; then
        info "Apt sandbox: use root for gpgv (some minimal/resolute images break with _apt user)"
        mkdir -p /etc/apt/apt.conf.d
        printf '%s\n' '// ubuntu-vm-images / desktop installer' 'APT::Sandbox::User "root";' >"$f"
    fi
}

ubuntu_codename() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -cs
    else
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${VERSION_CODENAME:?}"
    fi
}

validate_release() {
    local c
    c="$(ubuntu_codename)"
    case "$c" in
        noble | resolute) ;;
        *)
            err "Unsupported Ubuntu codename: $c (need noble or resolute)"
            exit 1
            ;;
    esac
    ok "Ubuntu codename: $c"
}

ensure_appbox_user() {
    if ! id appbox &>/dev/null; then
        info "Creating user appbox"
        useradd -m -s /bin/bash appbox
    fi
    usermod -s /bin/bash appbox
    usermod -aG sudo appbox
    mkdir -p /home/appbox/.local/share/flatpak
    chown -R appbox:appbox /home/appbox/.local/share/flatpak
}

install_packages() {
    info "apt-get update"
    apt-get update -qq

    info "Installing desktop stack (this may take several minutes)"
    apt-get install -y \
        ubuntu-desktop-minimal \
        gnome-remote-desktop \
        winpr-utils \
        polkitd \
        pkexec \
        mousepad \
        gnome-software \
        gnome-software-plugin-snap \
        gnome-software-plugin-flatpak \
        flatpak \
        snapd \
        openssl \
        curl \
        ca-certificates \
        dbus-x11 \
        software-properties-common

    # Chromium via snap (matches typical Ubuntu integration)
    if command -v snap >/dev/null 2>&1; then
        snap wait system seed 2>/dev/null || true
    fi

    if ! snap list chromium &>/dev/null; then
        info "Installing chromium snap"
        snap install chromium
    fi

    if ! snap list snap-store &>/dev/null; then
        info "Installing snap-store snap"
        snap install snap-store
    fi
}

patch_chromium_desktop_files() {
    local d
    for d in /var/lib/snapd/desktop/applications/chromium_chromium.desktop \
        /usr/share/applications/chromium.desktop \
        /usr/share/applications/chromium-browser.desktop; do
        if [[ -f "$d" ]]; then
            if grep -q 'Exec=/usr/local/bin/wrapped-chromium' "$d" 2>/dev/null; then
                continue
            fi
            sed -i 's#^Exec=chromium#Exec=/usr/local/bin/wrapped-chromium#g' "$d" || true
            sed -i 's#^Exec=/snap/bin/chromium#Exec=/usr/local/bin/wrapped-chromium#g' "$d" || true
        fi
    done
}

install_rootfs() {
    if [[ ! -d "$ROOTFS" ]]; then
        err "Missing rootfs: $ROOTFS"
        exit 1
    fi
    info "Installing rootfs from $ROOTFS"
    rsync -a "$ROOTFS/" /
    chmod 755 /usr/local/bin/wrapped-chromium 2>/dev/null || true
    chmod 755 /usr/bin/chromium 2>/dev/null || true
    chmod 750 /usr/local/sbin/appbox-configure-gnome-rdp.sh
}

configure_flatpak() {
    if flatpak remote-list --columns=name | grep -qx flathub; then
        return 0
    fi
    info "Adding flathub remote for user appbox"
    sudo -u appbox flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

apply_dconf_wallpaper() {
    info "Updating dconf databases (wallpaper)"
    if command -v dconf >/dev/null 2>&1; then
        dconf update
    fi
}

enable_systemd_units() {
    systemctl daemon-reload
    systemctl enable appbox-configure-gnome-rdp.service
    systemctl enable gdm3.service
    systemctl enable gnome-remote-desktop.service
    systemctl set-default graphical.target
    # Run configuration once now (also runs at boot before GRD)
    systemctl start appbox-configure-gnome-rdp.service
    systemctl restart gnome-remote-desktop.service || systemctl start gnome-remote-desktop.service
    systemctl start gdm3.service || true
}

cleanup_artifacts() {
    rm -rf /config 2>/dev/null || true
    apt-get autoremove -y || true
    apt-get autoclean || true
}

main() {
    info "GNOME + GDM + GNOME Remote Desktop (RDP) installer"
    validate_release
    configure_apt_sandbox
    ensure_appbox_user
    install_packages
    install_rootfs
    patch_chromium_desktop_files
    configure_flatpak
    apply_dconf_wallpaper
    enable_systemd_units
    cleanup_artifacts

    ok "Installation finished."
    info "RDP: set RDP_PORT (and optional GRD_RDP_USERNAME / GRD_RDP_PASSWORD) in /etc/default/gnome-remote-desktop-appbox then:"
    info "  sudo systemctl restart appbox-configure-gnome-rdp.service gnome-remote-desktop.service"
    info "If no GRD_RDP_PASSWORD is set, the installer wrote a random password to /etc/gnome-remote-desktop/rdp-secret"
    info "  sudo cat /etc/gnome-remote-desktop/rdp-secret"
    info "Connect with Windows Remote Desktop to this host on the configured port; use RDP credentials first, then log in at GDM as appbox."
}

main "$@"
