#!/bin/bash
set -euo pipefail
set +x
export DEBIAN_FRONTEND=noninteractive

if [[ ${1:-} == --help ]]; then
    printf 'Usage: sudo bash coolify/install.sh\nRun only in a fresh Ubuntu 26.04 amd64 template VM.\n'
    exit 0
fi
if [[ $# != 0 || $EUID != 0 || $(uname -m) != x86_64 ]]; then
    printf 'A fresh Ubuntu 26.04 amd64 template VM and root access are required.\n' >&2
    exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 26.04 ]]; then
    printf 'This image installer supports Ubuntu 26.04 only.\n' >&2
    exit 1
fi
if [[ -e /data/coolify/source/.env || -e /data/coolify/source/.appbox-ready ]]; then
    printf 'This VM contains Coolify state. Use a fresh template VM.\n' >&2
    exit 1
fi
if systemctl is-active --quiet nginx.service selkies-nginx.service; then
    printf 'A web server is already running. Start from a server image without a desktop.\n' >&2
    exit 1
fi

coolify_source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Refresh the fresh template, including its kernel, before sealing it.
# A released cloud image can lag current Ubuntu filesystem and kernel fixes.
apt-get update
apt-get dist-upgrade -y
apt-get install -y --no-install-recommends ca-certificates curl openssl openssh-server python3 \
    xfsprogs gdisk rsync
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
    cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker.service
docker compose version >/dev/null

install -d -m 0755 /usr/local/lib/appbox-coolify
for coolify_file in runtime.py provision.php compose.yaml proxy.yaml template_mounts.py storage.py; do
    install -m 0644 "$coolify_source_dir/$coolify_file" "/usr/local/lib/appbox-coolify/$coolify_file"
done
chmod 0755 /usr/local/lib/appbox-coolify/runtime.py
chmod 0755 /usr/local/lib/appbox-coolify/storage.py
# Large thin-provisioned disks should trim through the timer, not each root write.
python3 /usr/local/lib/appbox-coolify/template_mounts.py
# Keep the 32 GiB template OS partition. The Coolify storage service uses the
# remaining virtual disk space for XFS data before either container daemon starts.
touch /etc/growroot-disabled
for coolify_daemon in docker.service docker.socket containerd.service; do
    install -d -m 0755 "/etc/systemd/system/$coolify_daemon.d"
    install -m 0644 "$coolify_source_dir/systemd/storage.conf" \
        "/etc/systemd/system/$coolify_daemon.d/coolify-storage.conf"
done
install -m 0644 "$coolify_source_dir/systemd/appbox-coolify-storage.service" \
    /etc/systemd/system/appbox-coolify-storage.service
install -d -m 0755 /etc/systemd/system/fstrim.service.d
install -m 0644 "$coolify_source_dir/systemd/fstrim.conf" \
    /etc/systemd/system/fstrim.service.d/coolify-first-boot.conf
install -m 0755 "$coolify_source_dir/moduser.sh" /moduser.sh
for coolify_unit in appbox-coolify.service appbox-coolify-certificates.service appbox-coolify-certificates.timer; do
    install -m 0644 "$coolify_source_dir/systemd/$coolify_unit" "/etc/systemd/system/$coolify_unit"
done
install -d -m 0755 /etc/systemd/system/cylo-callback.service.d
install -m 0644 "$coolify_source_dir/systemd/callback.conf" \
    /etc/systemd/system/cylo-callback.service.d/coolify.conf
systemctl daemon-reload
systemctl enable appbox-coolify.service appbox-coolify-certificates.timer appbox-coolify-storage.service

# Cache public upstream images, without creating containers, databases, keys or credentials.
for coolify_image in coollabsio/coolify:4.3.23 postgres:15-alpine redis:7-alpine \
    coollabsio/coolify-realtime:1.0.19 traefik:v3.6; do
    docker pull --platform linux/amd64 "$coolify_image"
done
printf 'Coolify template preparation completed. First-boot provisioning has not run.\n'
