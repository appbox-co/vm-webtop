#!/bin/bash
# TEST_DESCRIPTION: Smoke-check Selkies web desktop stack
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x /etc/selkies/svc-de.sh ]] || fail "Selkies desktop startup script missing"
grep -q "startplasma-x11" /etc/selkies/svc-de.sh || fail "Selkies desktop does not start Plasma"

if ss -tlnp 2>/dev/null | grep -q ":443 "; then
    exit 0
fi
if command -v ss &>/dev/null; then
    echo "WARN: nothing listening on tcp/443 (Selkies/nginx may not be running yet)" >&2
fi
exit 0
