#!/usr/bin/env python3
"""Rebuild a pristine, verified template with an exact pushed source archive."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


def run(arguments, timeout=900, input_data=None):
    result = subprocess.run(arguments, input=input_data, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        print((result.stdout + result.stderr)[-2000:], flush=True)
        raise RuntimeError(f'{arguments[0]} failed with status {result.returncode}')
    return result.stdout


def digest(path):
    with path.open('rb') as reader:
        return hashlib.file_digest(reader, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--commit', required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--base-receipt', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    arguments = parser.parse_args()
    if not re.fullmatch(r'[a-f0-9]{40}', arguments.commit):
        raise RuntimeError('Expected an exact source commit')
    work = arguments.work_dir.resolve()
    if not work.is_relative_to(Path('/home/appbox/builds')) or not work.name.startswith('coolify-vps-'):
        raise RuntimeError('Expected a dedicated Coolify build directory')
    base_record = json.loads(arguments.base_receipt.read_text())
    base = arguments.base_receipt.parent / base_record['image']
    if base_record['normal_appbox_install_tested'] or digest(base) != base_record['image_sha256']:
        raise RuntimeError('Expected the original, checksum-verified sealed template')
    archive = arguments.archive.resolve()
    package = Path(__file__).resolve().parent
    # The dispatcher verifies the archive, extracts it and runs this Git-delivered
    # script. Check each input against that same archive before writing the image.
    import tarfile
    with tarfile.open(archive) as source:
        for relative in ('runtime.py', 'provision.php', 'compose.yaml', 'proxy.yaml',
                         'template_mounts.py', 'storage.py', 'moduser.sh',
                         'systemd/storage.conf', 'systemd/appbox-coolify-storage.service'):
            if source.extractfile('coolify/' + relative).read() != (package / relative).read_bytes():
                raise RuntimeError('Build source differs from the supplied archive')
    output = work / 'artifacts'
    output.mkdir(mode=0o700)
    disk = work / 'prepared.qcow2'
    if disk.exists():
        raise RuntimeError('Build work directory already contains a disk')
    print('Creating a scratch overlay of the checksum-verified sealed template.', flush=True)
    run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'qcow2', '-b', str(base.resolve()), str(disk)])
    command = ['sudo', '-n', 'virt-customize', '--no-network', '-a', str(disk)]
    for relative in ('runtime.py', 'provision.php', 'compose.yaml', 'proxy.yaml', 'template_mounts.py', 'storage.py'):
        command += ['--upload', str(package / relative) + ':/usr/local/lib/appbox-coolify/' + relative,
                    '--chmod', '0644:/usr/local/lib/appbox-coolify/' + relative]
    command += ['--chmod', '0755:/usr/local/lib/appbox-coolify/runtime.py',
                '--chmod', '0755:/usr/local/lib/appbox-coolify/storage.py',
                '--upload', str(package / 'moduser.sh') + ':/moduser.sh', '--chmod', '0755:/moduser.sh',
                '--upload', str(package / 'systemd/appbox-coolify-storage.service') + ':/etc/systemd/system/appbox-coolify-storage.service',
                '--chmod', '0644:/etc/systemd/system/appbox-coolify-storage.service']
    for unit in ('docker.service', 'docker.socket', 'containerd.service'):
        destination = '/etc/systemd/system/' + unit + '.d'
        command += ['--mkdir', destination, '--upload', str(package / 'systemd/storage.conf') + ':' + destination + '/coolify-storage.conf',
                    '--chmod', '0644:' + destination + '/coolify-storage.conf']
    command += ['--run-command', 'test ! -e /data/coolify/source/.env && test ! -e /data/coolify/source/.appbox-ready && test ! -e /var/lib/appbox-coolify/storage.json && command -v sgdisk && command -v mkfs.xfs && command -v rsync && python3 /usr/local/lib/appbox-coolify/template_mounts.py && touch /etc/growroot-disabled && systemctl enable appbox-coolify-storage.service',
                '--delete', '/var/lib/systemd/random-seed', '--delete', '/builder.log']
    print('Applying the archived package to the uninitialized template.', flush=True)
    run(command)
    checks = work / 'checks'
    checks.mkdir(mode=0o700)
    files = ('runtime.py', 'provision.php', 'compose.yaml', 'proxy.yaml', 'template_mounts.py', 'storage.py')
    commands = ''.join(f'download /usr/local/lib/appbox-coolify/{relative} {checks / relative}\n' for relative in files)
    commands += f'download /etc/fstab {checks / "fstab"}\n'
    commands += f'download /etc/systemd/system/appbox-coolify-storage.service {checks / "storage.service"}\n'
    for unit in ('docker.service', 'docker.socket', 'containerd.service'):
        commands += f'download /etc/systemd/system/{unit}.d/coolify-storage.conf {checks / unit}\n'
    for path in ('/var/lib/systemd/random-seed', '/data/coolify/source/.env', '/data/coolify/source/.appbox-ready', '/var/lib/appbox-coolify/storage.json', '/etc/growroot-disabled'):
        commands += f'exists {path}\n'
    state = run(['sudo', '-n', 'guestfish', '--ro', '--format=qcow2', '-a', str(disk), '-i'], input_data=commands)
    if state.split() != ['false', 'false', 'false', 'false', 'true']:
        raise RuntimeError('Rebuilt template contains an identity seed or initialized state')
    for relative in files:
        if (checks / relative).read_bytes() != (package / relative).read_bytes():
            raise RuntimeError('Saved package file differs from the archive')
    if (checks / 'storage.service').read_bytes() != (package / 'systemd/appbox-coolify-storage.service').read_bytes():
        raise RuntimeError('Saved storage unit differs from the archive')
    for unit in ('docker.service', 'docker.socket', 'containerd.service'):
        if (checks / unit).read_bytes() != (package / 'systemd/storage.conf').read_bytes():
            raise RuntimeError('Saved storage dependency differs from the archive')
    fstab = (checks / 'fstab').read_text()
    root = [line.split() for line in fstab.splitlines() if line.strip() and not line.startswith('#') and line.split()[1] == '/']
    if len(root) != 1 or 'discard' in root[0][3].split(','):
        raise RuntimeError('Template root mount still enables synchronous discard')
    image = output / f'coolify-ubuntu-26.04-4.3.23-{arguments.commit[:12]}.qcow2'
    print('Compressing and checking the standalone image.', flush=True)
    run(['qemu-img', 'convert', '-f', 'qcow2', '-O', 'qcow2', '-c', '-S', '4k', str(disk), str(image)], timeout=5400)
    run(['qemu-img', 'check', str(image)])
    info = json.loads(run(['qemu-img', 'info', '--output=json', str(image)]))
    if 'backing-filename' in info:
        raise RuntimeError('Output has a backing file')
    record = dict(base_record, created_at=datetime.now(timezone.utc).isoformat(),
                  commit=arguments.commit, archive_sha256=digest(archive), image=image.name,
                  image_sha256=digest(image), image_bytes=image.stat().st_size,
                  virtual_bytes=info['virtual-size'], normal_appbox_install_tested=False,
                  parent_template={'commit':base_record['commit'], 'sha256':base_record['image_sha256']},
                  build_method='verified-sealed-template-rebuild')
    record['storage_layout'] = {'os_disk_bytes': 34359738368, 'data_filesystem': 'xfs',
                                'data_uses_remaining_disk': True}
    (output / 'build.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps(record, indent=2, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()
