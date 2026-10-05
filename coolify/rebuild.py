#!/usr/bin/env python3
"""Rebuild a pristine, verified template with an exact pushed source archive."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


def run(arguments, timeout=900):
    return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT, timeout=timeout)


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
                         'template_mounts.py', 'moduser.sh'):
            if source.extractfile('coolify/' + relative).read() != (package / relative).read_bytes():
                raise RuntimeError('Build source differs from the supplied archive')
    output = work / 'artifacts'
    output.mkdir(mode=0o700)
    disk = work / 'prepared.qcow2'
    if disk.exists():
        raise RuntimeError('Build work directory already contains a disk')
    print('Copying the checksum-verified sealed template.', flush=True)
    run(['qemu-img', 'convert', '-f', 'qcow2', '-O', 'qcow2', str(base), str(disk)])
    command = ['virt-customize', '--no-network', '-a', str(disk)]
    for relative in ('runtime.py', 'provision.php', 'compose.yaml', 'proxy.yaml', 'template_mounts.py'):
        command += ['--upload', str(package / relative) + ':/usr/local/lib/appbox-coolify/' + relative,
                    '--chmod', '0644:/usr/local/lib/appbox-coolify/' + relative]
    command += ['--chmod', '0755:/usr/local/lib/appbox-coolify/runtime.py',
                '--upload', str(package / 'moduser.sh') + ':/moduser.sh', '--chmod', '0755:/moduser.sh',
                '--run-command', 'test ! -e /data/coolify/source/.env && test ! -e /data/coolify/source/.appbox-ready && python3 /usr/local/lib/appbox-coolify/template_mounts.py']
    print('Applying the archived package to the uninitialized template.', flush=True)
    run(command)
    for relative in ('runtime.py', 'provision.php', 'compose.yaml', 'proxy.yaml', 'template_mounts.py'):
        saved = run(['virt-cat', '--format=qcow2', '-a', str(disk), '/usr/local/lib/appbox-coolify/' + relative])
        if saved != (package / relative).read_text():
            raise RuntimeError('Saved package file differs from the archive')
    fstab = run(['virt-cat', '--format=qcow2', '-a', str(disk), '/etc/fstab'])
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
    (output / 'build.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps(record, indent=2, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()
