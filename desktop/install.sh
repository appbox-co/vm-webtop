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

cleanup_legacy_desktop_environment() {
    # Old Selkies/webtop images set global X11/audio/container variables that poison
    # GDM's Wayland greeter and GNOME Remote Desktop's handover path.
    chown root:root / /etc /srv /usr /var 2>/dev/null || true
    chmod 1777 /tmp /var/tmp 2>/dev/null || true
    rm -rf /tmp/.X11-unix
    install -d -m 1777 -o root -g root /tmp/.X11-unix

    systemctl disable --now \
        selkies.service \
        selkies-desktop.service \
        selkies-setup.service \
        selkies-pulseaudio.service \
        selkies-nginx.service \
        xvfb.service \
        2>/dev/null || true

    if [[ -f /etc/environment ]]; then
        local tmp_env
        tmp_env="$(mktemp /var/tmp/appbox-environment.XXXXXX)"
        awk '
            !/^(HOME=\/config|DISPLAY=|PERL5LIB=|START_DOCKER=|PULSE_RUNTIME_PATH=|PULSE_SERVER=|SELKIES_|NVIDIA_DRIVER_CAPABILITIES=|DISABLE_ZINK=|GST_DEBUG=|DISPLAY_SIZEW=|DISPLAY_SIZEH=|DISPLAY_REFRESH=|DISPLAY_DPI=|DISPLAY_CDEPTH=)/
        ' /etc/environment >"$tmp_env"
        if ! cmp -s /etc/environment "$tmp_env"; then
            info "Removing legacy Selkies/webtop variables from /etc/environment"
            install -m 0644 -o root -g root "$tmp_env" /etc/environment
        fi
        rm -f "$tmp_env"
    fi

    rm -f /etc/security/pam_env.conf.d/selkies.conf /etc/profile.d/user-systemd.sh
    rm -f \
        /etc/default/selkies-nginx \
        /etc/systemd/system/selkies.service \
        /etc/systemd/system/selkies-desktop.service \
        /etc/systemd/system/selkies-setup.service \
        /etc/systemd/system/selkies-pulseaudio.service \
        /etc/systemd/system/selkies-nginx.service \
        /etc/systemd/system/xvfb.service \
        /etc/systemd/user-services/selkies.service \
        /etc/systemd/user-services/selkies-desktop.service \
        /etc/systemd/user-services/selkies-pulseaudio.service \
        /etc/systemd/user/xfce-session.target \
        /etc/xdg/autostart/cleanup-user-services.desktop \
        /usr/local/bin/cleanup-user-services \
        /usr/local/bin/pulse-alsa-fix \
        /usr/local/bin/start-selkies-pulseaudio.sh
    systemctl daemon-reload 2>/dev/null || true

    if [[ -f /etc/pulse/client.conf ]] && grep -Eq '/defaults|selkies|default-server|PULSE_SERVER|native' /etc/pulse/client.conf; then
        info "Removing legacy Selkies PulseAudio client overrides"
        sed -i -E '/\/defaults|selkies|default-server|PULSE_SERVER|native/d' /etc/pulse/client.conf
    fi
}

configure_nsswitch_for_systemd_users() {
    # GDM uses transient DynamicUser accounts (gdm-greeter, gdm-greeter-2, ...).
    # They only resolve when the passwd/group NSS chains include systemd.
    local f=/etc/nsswitch.conf
    local tmp
    touch "$f"
    tmp="$(mktemp /var/tmp/appbox-nsswitch.XXXXXX)"

    awk '
        BEGIN {
            seen_passwd = seen_group = seen_shadow = seen_gshadow = 0
        }
        function ensure_systemd(line) {
            if (line !~ /(^|[[:space:]])systemd($|[[:space:]])/) {
                line = line " systemd"
            }
            return line
        }
        /^passwd:[[:space:]]*/ {
            print ensure_systemd($0)
            seen_passwd = 1
            next
        }
        /^group:[[:space:]]*/ {
            print ensure_systemd($0)
            seen_group = 1
            next
        }
        /^shadow:[[:space:]]*/ {
            print ensure_systemd($0)
            seen_shadow = 1
            next
        }
        /^gshadow:[[:space:]]*/ {
            print ensure_systemd($0)
            seen_gshadow = 1
            next
        }
        { print }
        END {
            if (!seen_passwd) print "passwd: files systemd"
            if (!seen_group) print "group: files systemd"
            if (!seen_shadow) print "shadow: files systemd"
            if (!seen_gshadow) print "gshadow: files systemd"
        }
    ' "$f" >"$tmp"

    if ! cmp -s "$f" "$tmp"; then
        info "Ensuring NSS resolves systemd DynamicUser accounts for GDM"
        install -m 0644 -o root -g root "$tmp" "$f"
    fi
    rm -f "$tmp"
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
    # Some legacy rootfs copies preserved appbox ownership on system directories.
    # Keep app/user data alone, but repair package/config paths that must be root-owned.
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

# Production: cloud-init (or similar) writes the plaintext password here before this
# installer runs. We apply it with chpasswd and remove the file immediately.
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

configure_gdm_xorg_for_remote_desktop() {
    # Ubuntu 26.04+ (resolute): GNOME-on-Xorg session files were removed upstream; GDM
    # must keep Wayland or there is no valid default GNOME session (only Wayland .desktop
    # entries under /usr/share/wayland-sessions). WaylandEnable=false here breaks RDP.
    # Ubuntu 24.04 (noble): still ships an Xorg session path; disabling Wayland for GDM
    # can fix black-screen RDP after login on some hardware.
    local c
    c="$(ubuntu_codename)"
    if [[ "$c" != noble ]]; then
        info "Skipping GDM WaylandEnable=false (only applied on noble; this release is $c)"
        return 0
    fi
    local f=/etc/gdm3/custom.conf
    [[ -f "$f" ]] || return 0
    if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$f"; then
        return 0
    fi
    info "GDM: set WaylandEnable=false (Xorg) for GNOME Remote Desktop stability"
    sed -i \
        -e 's/^[[:space:]]*WaylandEnable=true/WaylandEnable=false/' \
        -e 's/^[[:space:]]*#WaylandEnable=false/WaylandEnable=false/' \
        "$f"
    if ! grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$f"; then
        if grep -q '^\[daemon\]' "$f"; then
            sed -i '/^\[daemon\]/a WaylandEnable=false' "$f"
        else
            printf '\n[daemon]\nWaylandEnable=false\n' >>"$f"
        fi
    fi
}

configure_network_manager_ownership() {
    # Desktop images use NetworkManager. A dracut-generated systemd-networkd
    # fallback can also try to manage the same NIC, leaving networkd's
    # wait-online unit stuck in "configuring" even though NM is online. Leave
    # networkd itself alone because existing instances may still depend on the
    # dracut fallback until netplan/NM has fully taken ownership.
    systemctl disable --now systemd-networkd-wait-online.service 2>/dev/null || true
    systemctl enable NetworkManager.service NetworkManager-wait-online.service 2>/dev/null || true
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
        nginx \
        curl \
        ca-certificates \
        dbus-x11 \
        software-properties-common

    # Chromium via snap (matches typical Ubuntu integration)
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

publish_snap_store_desktop_file() {
    local source=/var/lib/snapd/desktop/applications/snap-store_snap-store.desktop
    local bundled=/usr/share/applications/snap-store_snap-store.desktop
    if [[ -f "$bundled" ]]; then
        update-desktop-database /usr/share/applications 2>/dev/null || true
        return 0
    fi
    if [[ ! -f "$source" ]]; then
        return 0
    fi
    install -m 0644 -o root -g root "$source" "$bundled"
    sed -i 's/^Categories=.*/Categories=System;PackageManager;/' "$bundled"
    grep -q '^StartupNotify=' "$bundled" || printf 'StartupNotify=true\n' >>"$bundled"
    update-desktop-database /usr/share/applications 2>/dev/null || true
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
    chmod 750 /usr/local/sbin/appbox-first-boot.sh
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
    info "Updating dconf databases (wallpaper and dock defaults)"
    if command -v dconf >/dev/null 2>&1; then
        dconf update
    fi
}

enable_systemd_units() {
    systemctl daemon-reload
    systemctl enable appbox-first-boot.service
    systemctl enable appbox-configure-gnome-rdp.service
    systemctl enable appbox-rdp-download.service
    systemctl enable gdm3.service
    systemctl enable gnome-remote-desktop.service
    systemctl set-default graphical.target
    # Run configuration once now (also runs at boot before GRD)
    systemctl start appbox-configure-gnome-rdp.service
    systemctl restart gnome-remote-desktop.service || systemctl start gnome-remote-desktop.service
    systemctl start gdm3.service || true
}

cleanup_artifacts() {
    # Do not `rm -rf /config`: on some images /config is the appbox home or contains the install tree.
    apt-get autoremove -y || true
    apt-get autoclean || true
}

main() {
    info "GNOME + GDM + GNOME Remote Desktop (RDP) installer"
    validate_release
    cleanup_legacy_desktop_environment
    configure_nsswitch_for_systemd_users
    configure_apt_sandbox
    ensure_appbox_user
    repair_appbox_owned_system_paths
    configure_appbox_password_from_cloud_init
    install_packages
    configure_network_manager_ownership
    configure_gdm_xorg_for_remote_desktop
    install_rootfs
    patch_chromium_desktop_files
    publish_snap_store_desktop_file
    configure_flatpak
    apply_dconf_wallpaper
    enable_systemd_units
    cleanup_artifacts

    ok "Installation finished."
    info "If /tmp/user_pw existed at install time, appbox's login password was set from it and the file was removed."
    info "RDP: set RDP_PORT (and optional GRD_RDP_USERNAME / GRD_RDP_PASSWORD) in /etc/default/gnome-remote-desktop-appbox then:"
    info "  sudo systemctl restart appbox-configure-gnome-rdp.service gnome-remote-desktop.service"
    info "If no GRD_RDP_PASSWORD is set, the installer wrote a random password to /etc/gnome-remote-desktop/rdp-secret"
    info "  sudo cat /etc/gnome-remote-desktop/rdp-secret"
    info "Connect with Windows Remote Desktop to this host on the configured port; use RDP credentials first, then log in at GDM as appbox."
}

main "$@"
