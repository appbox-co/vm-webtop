#!/bin/bash
# TEST_DESCRIPTION: Verifies KDE Plasma packages for Selkies desktop sessions
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

dpkg -s kde-plasma-desktop &>/dev/null || fail "kde-plasma-desktop not installed"
if apt-cache show plasma-session-x11 >/dev/null 2>&1; then
    dpkg -s plasma-session-x11 &>/dev/null || fail "plasma-session-x11 not installed"
fi
id appbox &>/dev/null || fail "appbox user missing"

systemctl is-enabled appbox-first-boot.service &>/dev/null || fail "appbox-first-boot not enabled"
systemctl is-enabled appbox-reset-snap-namespaces.service &>/dev/null || fail "snap namespace reset not enabled"

[[ -x /usr/local/sbin/appbox-first-boot.sh ]] || fail "first boot script missing"
[[ -x /usr/local/sbin/appbox-apply-kde-defaults.sh ]] || fail "KDE defaults script missing"
[[ -x /usr/local/sbin/appbox-reset-snap-namespaces.sh ]] || fail "snap namespace reset script missing"

exit 0
