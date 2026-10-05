#!/bin/bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run this installer with sudo.' >&2; exit 1; }
[[ $(cat /sys/class/dmi/id/product_uuid) == 2358362c-c6d3-48a8-b8d5-4c0fe244a4d4 ]] || {
    echo 'This installer is restricted to builder VM 254280.' >&2
    exit 1
}
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -e /usr/local/bin/desktop ]] && ! cmp -s "$source_dir/desktop" /usr/local/bin/desktop; then
    previous_sha=ebbacea57c580896291ebc0dcad87efbe3d87bd969d72f38dc6686321af85617
    [[ $(sha256sum /usr/local/bin/desktop | cut -d' ' -f1) == "$previous_sha" ]] || {
        echo '/usr/local/bin/desktop already exists with unexpected contents.' >&2
        exit 1
    }
fi
install -o root -g root -m 0755 "$source_dir/desktop" /usr/local/bin/desktop
echo 'Installed desktop. Use desktop on, desktop off, or desktop status.'
