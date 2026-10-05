#!/bin/bash
# Apply this release from its Git checkout to the existing KDE builder.
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source_file="$repo_dir/selkies/rootfs/etc/selkies/init-selkies-config.sh"
target_file=/etc/selkies/init-selkies-config.sh
old_sha=bac291d482e5233a0f0edff2414d56f8cb3928f39a3c2e829634d1adc3939529
new_sha=431782676de2c3562dcbc931ff53cdf5f7529d93ea70a2ab6adaeff43f4a9e85
backup_dir=/var/lib/appbox-vm-image-updates/20261005-kde-selkies-startup

[[ $(sha256sum "$source_file" | cut -d' ' -f1) == "$new_sha" ]]
bash -n "$source_file"
current_sha=$(sha256sum "$target_file" | cut -d' ' -f1)
[[ "$current_sha" == "$old_sha" || "$current_sha" == "$new_sha" ]] || {
    echo 'The installed startup script differs from the verified baseline.' >&2
    exit 1
}
if [[ "$current_sha" == "$old_sha" ]]; then
    install -d -m 0700 "$backup_dir"
    if [[ -e "$backup_dir/init-selkies-config.sh" ]]; then
        [[ $(sha256sum "$backup_dir/init-selkies-config.sh" | cut -d' ' -f1) == "$old_sha" ]]
    else
        cp --preserve=all "$target_file" "$backup_dir/init-selkies-config.sh"
    fi
    systemctl stop selkies-desktop.service selkies.service
    install -o root -g root -m 0755 "$source_file" "$target_file"
fi
systemctl reset-failed selkies.service selkies-desktop.service
SECONDS=0
systemctl start selkies.service selkies-desktop.service
systemctl is-active selkies.service selkies-desktop.service
[[ $(sha256sum "$target_file" | cut -d' ' -f1) == "$new_sha" ]]
echo "Selkies and KDE started in ${SECONDS}s."
