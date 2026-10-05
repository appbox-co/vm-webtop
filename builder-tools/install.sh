#!/bin/bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run this installer with sudo.' >&2; exit 1; }
[[ $(cat /sys/class/dmi/id/product_uuid) == 2358362c-c6d3-48a8-b8d5-4c0fe244a4d4 ]] || {
    echo 'This installer is restricted to builder VM 254280.' >&2
    exit 1
}
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -e /usr/local/bin/desktop ]] && ! cmp -s "$source_dir/desktop" /usr/local/bin/desktop; then
    echo '/usr/local/bin/desktop already exists with different contents.' >&2
    exit 1
fi
install -o root -g root -m 0755 "$source_dir/desktop" /usr/local/bin/desktop
echo 'Installed desktop. Use desktop on, desktop off, or desktop status.'
