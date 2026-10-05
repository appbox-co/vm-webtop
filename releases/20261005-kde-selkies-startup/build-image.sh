#!/bin/bash
# Build on the dedicated builder from the clean released KDE template.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'Usage: build-image.sh BASE_IMAGE OUTPUT_DIRECTORY' >&2; exit 1; }
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source_file="$repo_dir/selkies/rootfs/etc/selkies/init-selkies-config.sh"
base_image=$(realpath -- "$1")
output_dir=$(realpath -- "$2")
output_file="$output_dir/resolute-server-cloudimg-amd64v3-remote-desktop-kde-20261005.img"
new_sha=431782676de2c3562dcbc931ff53cdf5f7529d93ea70a2ab6adaeff43f4a9e85
base_sha=16e62a26155e4650d2e848852d785e268e20ff9712cdc3fc4e53c575fa6f37b0
[[ -f "$base_image" && -d "$output_dir" && ! -e "$output_file" ]]
[[ $(sha256sum "$source_file" | cut -d' ' -f1) == "$new_sha" ]]
[[ $(sha256sum "$base_image" | cut -d' ' -f1) == "$base_sha" ]]
bash -n "$source_file"
qemu-img check -q "$base_image"
build_dir=$(mktemp -d "$output_dir/.kde-build.XXXXXX")
trap 'rm -f -- "$build_dir/image.img"; rmdir -- "$build_dir"' EXIT

qemu-img convert -f qcow2 -O qcow2 -S 4k "$base_image" "$build_dir/image.img"
virt-customize --no-network -a "$build_dir/image.img" \
    --copy-in "$source_file:/etc/selkies" \
    --chmod 0755:/etc/selkies/init-selkies-config.sh \
    --chown 0:0:/etc/selkies/init-selkies-config.sh \
    --mkdir /tmp/appbox-kde-20261005-check \
    --copy-in "$repo_dir/testing/component/test_selkies_installation.sh:/tmp/appbox-kde-20261005-check" \
    --run-command 'bash /tmp/appbox-kde-20261005-check/test_selkies_installation.sh' \
    --delete /tmp/appbox-kde-20261005-check
actual_sha=$(virt-cat -a "$build_dir/image.img" /etc/selkies/init-selkies-config.sh | sha256sum | cut -d' ' -f1)
[[ "$actual_sha" == "$new_sha" ]]
qemu-img check "$build_dir/image.img"
qemu-img info --output=json "$build_dir/image.img" | python3 -c \
    'import json,sys; i=json.load(sys.stdin); assert i["format"] == "qcow2"; assert not i.get("backing-filename"); assert i["virtual-size"] == 3758096384000; print("Standalone qcow2; original virtual size preserved.")'
mv -- "$build_dir/image.img" "$output_file"
sha256sum "$output_file"
