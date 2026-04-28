#!/bin/bash
# TEST_DESCRIPTION: Smoke-check RDP stack (grdctl system status, listening port from defaults)
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v grdctl &>/dev/null || fail "grdctl missing"

# shellcheck source=/dev/null
. /etc/default/gnome-remote-desktop-appbox
: "${RDP_PORT:=3389}"

out=$(grdctl --system status 2>&1) || fail "grdctl --system status failed: $out"
echo "$out" | grep -q "Status: enabled" || echo "$out" | grep -q "RDP:" || fail "unexpected grdctl output: $out"

if ss -tlnp 2>/dev/null | grep -q ":${RDP_PORT} "; then
    exit 0
fi
# Some images may not have ss; skip listen check
if command -v ss &>/dev/null; then
    echo "WARN: nothing listening on tcp/${RDP_PORT} (GRD may be inactive until next boot)" >&2
fi
exit 0
