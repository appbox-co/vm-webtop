#!/bin/bash
# TEST_DESCRIPTION: Verifies GNOME + GDM + GNOME Remote Desktop packages and units
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

dpkg -s ubuntu-desktop-minimal &>/dev/null || fail "ubuntu-desktop-minimal not installed"
dpkg -s gnome-remote-desktop &>/dev/null || fail "gnome-remote-desktop not installed"
dpkg -s gdm3 &>/dev/null || fail "gdm3 not installed"
command -v grdctl &>/dev/null || fail "grdctl not in PATH"
id appbox &>/dev/null || fail "appbox user missing"

systemctl is-enabled gdm3 &>/dev/null || fail "gdm3 not enabled"
systemctl is-enabled gnome-remote-desktop.service &>/dev/null || fail "gnome-remote-desktop not enabled"
systemctl is-enabled appbox-configure-gnome-rdp.service &>/dev/null || fail "appbox-configure-gnome-rdp not enabled"

[[ -x /usr/local/sbin/appbox-configure-gnome-rdp.sh ]] || fail "configure script missing"
[[ -f /etc/default/gnome-remote-desktop-appbox ]] || fail "default RDP config missing"

exit 0
