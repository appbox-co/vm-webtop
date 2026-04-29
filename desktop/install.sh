#!/bin/bash
# Ubuntu 26.04 — KDE Plasma desktop payload for Selkies/Xvfb.
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

cleanup_legacy_desktop_environment() {
    chown root:root / /etc /srv /usr /var 2>/dev/null || true
    chmod 1777 /tmp /var/tmp 2>/dev/null || true
    rm -rf /tmp/.X11-unix
    install -d -m 1777 -o root -g root /tmp/.X11-unix

    systemctl disable --now \
        appbox-configure-krdp.service \
        app-org.kde.krdpserver.service \
        sddm.service \
        gdm3.service \
        gnome-remote-desktop.service \
        2>/dev/null || true

    rm -f \
        /etc/default/krdp-appbox \
        /etc/systemd/system/appbox-configure-krdp.service \
        /usr/local/sbin/appbox-configure-krdp.sh
    rm -f \
        /home/appbox/.config/systemd/user/plasma-workspace.target.wants/app-org.kde.krdpserver.service \
        /home/appbox/.config/systemd/user/default.target.wants/app-org.kde.krdpserver.service
    pkill -u appbox -f krdpserver 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

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

repair_appbox_owned_system_paths() {
    info "Repairing appbox-owned system paths outside /home/appbox"
    local appbox_uid appbox_gid
    appbox_uid="$(id -u appbox)"
    appbox_gid="$(id -g appbox)"
    APPBOX_UID="$appbox_uid" APPBOX_GID="$appbox_gid" python3 - <<'PY'
import os

roots = ["/etc", "/usr", "/var", "/srv"]
skip = {"/var/tmp"}
appbox_uid = int(os.environ["APPBOX_UID"])
appbox_gid = int(os.environ["APPBOX_GID"])

for start in roots:
    if not os.path.exists(start):
        continue
    for root, dirs, files in os.walk(start, topdown=True, followlinks=False):
        dirs[:] = [
            d for d in dirs
            if os.path.join(root, d) not in skip
            and not os.path.islink(os.path.join(root, d))
        ]
        for path in [root] + [os.path.join(root, name) for name in files]:
            try:
                st = os.lstat(path)
            except OSError:
                continue
            if os.path.islink(path):
                continue
            if st.st_uid == appbox_uid or st.st_gid == appbox_gid:
                try:
                    os.chown(path, 0, 0)
                except OSError:
                    pass
PY
}

configure_appbox_password_from_cloud_init() {
    local pw_file=/tmp/user_pw
    if [[ ! -f "$pw_file" ]]; then
        info "No $pw_file — leaving appbox password unchanged (use cloud-init to create $pw_file before install in production)"
        return 0
    fi
    info "Setting appbox password from $pw_file (file will be removed)"
    local pw
    pw=$(tr -d '\n\r' <"$pw_file")
    if [[ -z "$pw" ]]; then
        err "$pw_file is empty; refusing to set password"
        rm -f "$pw_file"
        exit 1
    fi
    echo "appbox:${pw}" | chpasswd
    rm -f "$pw_file"
    ok "appbox password updated; $pw_file removed"
}

configure_network_manager_ownership() {
    systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
    systemctl enable NetworkManager.service NetworkManager-wait-online.service 2>/dev/null || true
}

install_packages() {
    info "apt-get update"
    apt-get update -qq

    info "Installing KDE Plasma desktop stack for Selkies (this may take several minutes)"
    local packages=(
        kde-plasma-desktop
        plasma-nm
        plasma-pa
        kde-spectacle
        dolphin
        konsole
        kate
        polkitd
        pkexec
        flatpak
        plasma-discover
        plasma-discover-backend-flatpak
        plasma-discover-backend-snap
        snapd
        openssl
        curl
        ca-certificates
        software-properties-common
        dbus-x11
        x11-xserver-utils
        xdg-utils
    )

    for optional_package in plasma-session-x11 kwin-x11 libkf6config-bin libkf5config-bin; do
        if apt-cache show "$optional_package" >/dev/null 2>&1; then
            packages+=("$optional_package")
        fi
    done

    apt-get install -y "${packages[@]}"

    if command -v snap >/dev/null 2>&1; then
        snap wait system seed 2>/dev/null || true
    fi

    if [[ -x /usr/bin/chromium || -x /usr/lib/chromium/chromium ]]; then
        info "Chromium package is already installed; skipping chromium snap"
    elif ! snap list chromium &>/dev/null; then
        info "Installing chromium snap"
        snap install chromium
    fi

    if ! snap list snap-store &>/dev/null; then
        info "Installing snap-store snap"
        snap install snap-store
    fi

    mkdir -p /home/appbox/snap/snap-store/common/.cache
    chown -R appbox:appbox /home/appbox/snap
    snap connect snap-store:audio-playback :audio-playback 2>/dev/null || true
    snap connect snap-store:pulseaudio :pulseaudio 2>/dev/null || true
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
    rsync -a --chown=root:root "$ROOTFS/" /
    chown root:root / /etc /srv /usr /var 2>/dev/null || true
    chmod 755 /usr/local/bin/wrapped-chromium 2>/dev/null || true
    chmod 755 /usr/bin/chromium 2>/dev/null || true
    chmod 750 /usr/local/sbin/appbox-configure-rdp-download.sh 2>/dev/null || true
    chmod 755 /usr/local/sbin/appbox-apply-kde-defaults.sh 2>/dev/null || true
    chmod 750 /usr/local/sbin/appbox-reset-snap-namespaces.sh 2>/dev/null || true
    chmod 750 /usr/local/sbin/appbox-first-boot.sh
}

configure_flatpak() {
    if flatpak remote-list --columns=name | grep -qx flathub; then
        return 0
    fi
    info "Adding flathub remote for user appbox"
    sudo -u appbox flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

enable_systemd_units() {
    systemctl daemon-reload
    systemctl enable appbox-first-boot.service
    systemctl enable appbox-rdp-download.service
    systemctl enable appbox-reset-snap-namespaces.service
}

cleanup_artifacts() {
    apt-get autoremove -y || true
    apt-get autoclean || true
}

main() {
    info "KDE Plasma payload installer for Selkies"
    validate_release
    cleanup_legacy_desktop_environment
    configure_apt_sandbox
    ensure_appbox_user
    repair_appbox_owned_system_paths
    configure_appbox_password_from_cloud_init
    install_packages
    configure_network_manager_ownership
    install_rootfs
    patch_chromium_desktop_files
    configure_flatpak
    enable_systemd_units
    cleanup_artifacts

    ok "Installation finished."
    info "If /tmp/user_pw existed at install time, appbox's login password was set from it and the file was removed."
    info "Remote access is provided by the Selkies component."
}

main "$@"
