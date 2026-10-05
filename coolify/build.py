#!/usr/bin/python3
"""Build a sealed Coolify qcow2 on the dedicated builder, using a fresh guest."""
import argparse
from datetime import datetime, timezone
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.request

BUILDER_HOSTS = {'builder.grant.appboxes.co', 'builder.tester2.appboxes.co'}
BASE_URL = 'https://cloud-images.ubuntu.com/releases/26.04/release/'
BASE_NAME = 'ubuntu-26.04-server-cloudimg-amd64.img'
IMAGES = ('coollabsio/coolify:4.3.23', 'postgres:15-alpine', 'redis:7-alpine',
          'coollabsio/coolify-realtime:1.0.19', 'traefik:v3.6')


def run(arguments, *, input_data=None, timeout=3600, log=None):
    result = subprocess.run(arguments, input=input_data, capture_output=True,
                            text=True, timeout=timeout)
    if log is not None:
        log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{Path(arguments[0]).name} failed with status {result.returncode}.')
    return result.stdout


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


class SeedHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_arguments):
        pass


def build(arguments):
    if socket.getfqdn() not in BUILDER_HOSTS or os.geteuid() == 0:
        raise RuntimeError('Run as appbox on the dedicated builder.')
    if not re.fullmatch(r'[a-f0-9]{40}', arguments.commit):
        raise RuntimeError('A full committed Git revision is required.')
    work = Path(arguments.work_dir).resolve()
    if work.parent != Path('/home/appbox/builds') or not re.fullmatch(r'coolify-vps-[A-Za-z0-9._-]+', work.name):
        raise RuntimeError('Use a unique Coolify build directory under /home/appbox/builds.')
    scratch = work / 'guest'
    scratch.mkdir(mode=0o700)  # Refuse to reuse a previous guest or overwrite an image.
    output = work / 'artifacts'
    output.mkdir(mode=0o700)
    archive = Path(arguments.archive).resolve()
    archive_hash = digest(archive)
    for executable in ('qemu-img', 'qemu-system-x86_64', 'ssh', 'ssh-keygen', 'curl'):
        if not shutil.which(executable):
            raise RuntimeError(f'{executable} is required on the builder.')

    print('Downloading the official Ubuntu 26.04 cloud image.', flush=True)
    sums = urllib.request.urlopen(BASE_URL + 'SHA256SUMS', timeout=60).read().decode()
    matches = re.findall(r'^([a-f0-9]{64})\s+\*?' + re.escape(BASE_NAME) + r'$', sums, re.MULTILINE)
    if len(matches) != 1:
        raise RuntimeError('Could not uniquely identify the Ubuntu image checksum.')
    base = scratch / BASE_NAME
    run(['curl', '--fail', '--silent', '--show-error', '--location', '--retry', '3',
         '--max-time', '1800', BASE_URL + BASE_NAME, '-o', str(base)])
    if digest(base) != matches[0]:
        raise RuntimeError('Ubuntu image checksum did not match.')
    disk = scratch / 'guest.qcow2'
    run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'qcow2', '-b', str(base), str(disk), '32G'])
    key = scratch / 'build-key'
    run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'coolify-image-build', '-f', str(key)])
    seed = scratch / 'seed'
    seed.mkdir(mode=0o700)
    shutil.copyfile(archive, seed / 'source.tgz')
    configuration = {
        'users': [{'name': 'appbox', 'uid': 1000, 'shell': '/bin/bash', 'lock_passwd': True,
                   'sudo': ['ALL=(ALL) NOPASSWD:ALL'], 'groups': ['sudo'],
                   'ssh_authorized_keys': [key.with_suffix('.pub').read_text().strip()]}],
        'ssh_pwauth': False,
        'runcmd': [['bash', '-c', "{ printf 'APPBOX_BUILD_HOST_KEY '; cat /etc/ssh/ssh_host_ed25519_key.pub; } > /dev/ttyS0"]],
    }
    (seed / 'user-data').write_text('#cloud-config\n' + json.dumps(configuration) + '\n')
    (seed / 'meta-data').write_text(json.dumps({'instance-id': work.name, 'local-hostname': 'coolify-image-build'}) + '\n')
    (seed / 'vendor-data').write_text('#cloud-config\n{}\n')
    (seed / 'network-config').write_text(json.dumps({'version': 2, 'ethernets': {'build': {
        'match': {'name': 'en*'}, 'dhcp4': True}}}) + '\n')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(SeedHandler, directory=str(seed)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        ssh_port = probe.getsockname()[1]
    console = scratch / 'console.log'
    qemu_errors = scratch / 'qemu.log'
    accelerator = 'kvm' if os.access('/dev/kvm', os.R_OK | os.W_OK) else 'tcg,thread=multi'
    qemu = subprocess.Popen([
        'qemu-system-x86_64', '-machine', 'q35', '-accel', accelerator,
        '-cpu', 'host' if accelerator == 'kvm' else 'max', '-smp', '4', '-m', '4096',
        '-drive', f'file={disk},if=virtio,format=qcow2',
        '-netdev', f'user,id=build,hostfwd=tcp:127.0.0.1:{ssh_port}-:22',
        '-device', 'virtio-net-pci,netdev=build',
        '-smbios', f'type=1,serial=ds=nocloud;s=http://10.0.2.2:{server.server_port}/',
        '-display', 'none', '-monitor', 'none', '-serial', f'file:{console}', '-no-reboot',
    ], stdout=subprocess.DEVNULL, stderr=qemu_errors.open('wb'))
    try:
        print('Booting a fresh isolated guest using ' + accelerator.split(',')[0] + '.', flush=True)
        deadline = time.monotonic() + 1200
        host_key = None
        while time.monotonic() < deadline:
            if qemu.poll() is not None:
                raise RuntimeError('The guest stopped before SSH provisioning; inspect the build console.')
            text = console.read_text(errors='replace') if console.exists() else ''
            match = re.search(r'APPBOX_BUILD_HOST_KEY (ssh-ed25519 [A-Za-z0-9+/=]+)', text)
            if match:
                host_key = match[1]
                break
            time.sleep(3)
        if host_key is None:
            raise RuntimeError('Timed out waiting for the guest public host key.')
        known_hosts = scratch / 'known-hosts'
        known_hosts.write_text(f'[127.0.0.1]:{ssh_port} {host_key}\n')
        ssh = ['ssh', '-p', str(ssh_port), '-i', str(key), '-o', 'IdentitiesOnly=yes',
               '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
               '-o', 'UserKnownHostsFile=' + str(known_hosts), '-o', 'ConnectTimeout=10',
               '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4', 'appbox@127.0.0.1']
        run(ssh + ['sudo -n cloud-init status --wait'], timeout=1200,
            log=scratch / 'cloud-init.log')
        print('Installing Docker and caching the five upstream images inside the guest.', flush=True)
        script = f'''set -eu
sudo -n install -d -m 0755 /opt/appbox-coolify-build
curl --fail --silent --show-error http://10.0.2.2:{server.server_port}/source.tgz -o /tmp/coolify-source.tgz
printf '%s  %s\\n' '{archive_hash}' /tmp/coolify-source.tgz | sha256sum -c -
sudo -n tar -xzf /tmp/coolify-source.tgz -C /opt/appbox-coolify-build
sudo -n bash /opt/appbox-coolify-build/coolify/install.sh
'''
        # The installer handles only public images and creates no instance secrets.
        run(ssh + ['bash -s'], input_data=script, timeout=5400, log=scratch / 'install.log')
        print('Checking the prepared guest and recording upstream image digests.', flush=True)
        checks = '''set -eu
# shellcheck disable=SC1091
test "$( . /etc/os-release; printf '%s' "$VERSION_ID")" = 26.04
test ! -e /data/coolify/source/.env
test ! -e /data/coolify/source/.appbox-ready
test ! -e /data/coolify/ssh/keys/id.root@host.docker.internal
test -z "$(sudo -n docker ps -aq)"
test -z "$(sudo -n docker volume ls -q)"
test "$(sudo -n systemctl is-enabled appbox-coolify.service)" = enabled
test "$(sudo -n systemctl is-enabled appbox-coolify-certificates.timer)" = enabled
sudo -n systemd-analyze verify /etc/systemd/system/appbox-coolify.service /etc/systemd/system/appbox-coolify-certificates.service /etc/systemd/system/appbox-coolify-certificates.timer
'''
        run(ssh + ['bash -s'], input_data=checks, timeout=120, log=scratch / 'checks.log')
        image_output = run(ssh + ["sudo -n docker image inspect --format '{{json .RepoDigests}}' " + ' '.join(IMAGES)], timeout=120)
        image_info = [json.loads(line) for line in image_output.splitlines()]
        if len(image_info) != len(IMAGES) or any(not entries for entries in image_info):
            raise RuntimeError('Upstream image digests are incomplete.')
        print('Sealing the guest and shutting it down.', flush=True)
        seal = '''set -eu
sudo -n bash -s <<'SEAL'
set -eu
test ! -e /data/coolify/source/.env
test -z "$(docker ps -aq)"
systemctl stop docker.service docker.socket containerd.service
rm -f /var/lib/docker/engine-id
apt-get clean
rm -rf /opt/appbox-coolify-build
rm -f /tmp/coolify-source.tgz /home/appbox/.ssh/authorized_keys /root/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_* /var/lib/systemd/random-seed /etc/netplan/50-cloud-init.yaml
rm -f /root/.bash_history /home/appbox/.bash_history
cloud-init clean --logs --seed --machine-id
hostnamectl set-hostname coolify-template
sync
systemd-run --quiet --on-active=3 --unit=appbox-coolify-build-poweroff systemctl poweroff
SEAL
'''
        run(ssh + ['bash -s'], input_data=seal, timeout=180, log=scratch / 'seal.log')
        qemu.wait(timeout=180)
        if qemu.returncode:
            raise RuntimeError('QEMU exited with an error; refusing image conversion.')
        image = output / f'coolify-ubuntu-26.04-4.3.23-{arguments.commit[:12]}.qcow2'
        print('Converting the stopped disk into a standalone compressed qcow2.', flush=True)
        run(['qemu-img', 'convert', '-f', 'qcow2', '-O', 'qcow2', '-c', '-S', '4k', str(disk), str(image)], timeout=5400)
        run(['qemu-img', 'check', str(image)], timeout=600)
        info = json.loads(run(['qemu-img', 'info', '--output=json', str(image)]))
        if 'backing-filename' in info:
            raise RuntimeError('The output image still depends on a backing file.')
        record = {'created_at': datetime.now(timezone.utc).isoformat(), 'commit': arguments.commit,
                  'archive_sha256': archive_hash, 'base_url': BASE_URL + BASE_NAME,
                  'base_sha256': matches[0], 'image': image.name, 'image_sha256': digest(image),
                  'image_bytes': image.stat().st_size, 'virtual_bytes': info['virtual-size'],
                  'accelerator': accelerator, 'builder_hostname': socket.getfqdn(),
                  'upstream_images': dict(zip(IMAGES, image_info)),
                  'normal_appbox_install_tested': False}
        (output / 'build.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
        print(json.dumps(record, indent=2, sort_keys=True), flush=True)
    finally:
        if qemu.poll() is None:
            qemu.terminate()  # Only the fresh guest process owned by this build.
            try:
                qemu.wait(timeout=30)
            except subprocess.TimeoutExpired:
                qemu.kill()
                qemu.wait()
        server.shutdown()
        key.unlink(missing_ok=True)
        key.with_suffix('.pub').unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--archive', required=True)
    parser.add_argument('--work-dir', required=True)
    os.umask(0o077)
    build(parser.parse_args())
