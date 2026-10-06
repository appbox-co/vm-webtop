#!/usr/bin/env python3
"""Verify Coolify's boot graph against the generic Appbox callback on Linux."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def verify(package, callback, storage=None):
    with tempfile.TemporaryDirectory(prefix='coolify-systemd-') as directory:
        root = Path(directory)
        units = root / 'etc/systemd/system'
        units.mkdir(parents=True)
        executable = root / 'usr/bin/true'
        executable.parent.mkdir(parents=True)
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o755)
        targets = {
            'default.target': 'Wants=multi-user.target cloud-init.target\n',
            'multi-user.target': 'Requires=basic.target\nAfter=basic.target\n',
            'cloud-init.target': 'DefaultDependencies=no\nWants=cloud-final.service\nAfter=cloud-final.service\n',
            'basic.target': 'Requires=sysinit.target\nWants=sockets.target\nAfter=sysinit.target sockets.target\n',
            'sockets.target': '',
            'sysinit.target': 'DefaultDependencies=no\n',
            'local-fs.target': 'DefaultDependencies=no\n',
            'network-online.target': '',
            'shutdown.target': 'DefaultDependencies=no\n',
        }
        for name, properties in targets.items():
            (units / name).write_text('[Unit]\nDescription=Isolated boot graph fixture\n' + properties)
        (units / 'cloud-final.service').write_text('[Unit]\nDescription=Cloud-init final fixture\nAfter=multi-user.target network-online.target\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n')
        (units / 'docker.service').write_text('[Unit]\nDescription=Docker fixture\nRequires=appbox-coolify-storage.service docker.socket\nAfter=appbox-coolify-storage.service docker.socket\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n')
        (units / 'docker.socket').write_text('[Unit]\nDescription=Docker socket fixture\nRequires=appbox-coolify-storage.service\nAfter=appbox-coolify-storage.service\n[Socket]\nListenStream=/run/docker.sock\n[Install]\nWantedBy=sockets.target\n')
        for name in ('appbox-coolify.service', 'appbox-coolify-storage.service'):
            # Preserve all package ordering; substitute only the executable.
            content = storage if name == 'appbox-coolify-storage.service' and storage is not None else (package / 'systemd' / name).read_text()
            (units / name).write_text(re.sub(r'^ExecStart=.*$', 'ExecStart=/usr/bin/true', content, flags=re.M))
        (units / 'cylo-callback.service').write_text('[Unit]\nDescription=Generic Appbox callback fixture\nAfter=network-online.target cloud-final.service\nWants=network-online.target\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n[Install]\nWantedBy=multi-user.target\n')
        dropin = units / 'cylo-callback.service.d'
        dropin.mkdir()
        (dropin / 'coolify.conf').write_text(callback)
        enable = subprocess.run(['systemctl', '--root=' + str(root), 'enable', 'appbox-coolify.service', 'cylo-callback.service', 'appbox-coolify-storage.service', 'docker.socket'], capture_output=True, text=True, timeout=15)
        if enable.returncode:
            raise RuntimeError('Fixture enable failed: ' + enable.stderr)
        return subprocess.run(['systemd-analyze', '--root=' + str(root), 'verify', '--man=no', 'default.target'], capture_output=True, text=True, timeout=20)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    args = parser.parse_args()
    for command in ('systemctl', 'systemd-analyze'):
        if not shutil.which(command):
            raise RuntimeError('Linux systemd is required; ordering coverage cannot be skipped.')
    previous = verify(args.package, '[Unit]\nRequires=appbox-coolify.service\nAfter=appbox-coolify.service\n')
    callback = (args.package / 'systemd/callback.conf').read_text()
    storage = (args.package / 'systemd/appbox-coolify-storage.service').read_text()
    old_storage = verify(args.package, callback, storage.replace('DefaultDependencies=no\n', ''))
    fixed = verify(args.package, callback)
    # systemd may return zero after deleting a job to break the cycle.
    reproduced = 'ordering cycle' in previous.stderr.lower()
    storage_reproduced = 'ordering cycle' in old_storage.stderr.lower()
    passed = fixed.returncode == 0 and 'ordering cycle' not in fixed.stderr.lower()
    print(json.dumps({'previous_cycle_reproduced': reproduced,
                      'previous_storage_socket_cycle_reproduced': storage_reproduced,
                      'corrected_boot_graph_passed': passed,
                      'previous_exit': previous.returncode,
                      'previous_storage_exit': old_storage.returncode,
                      'corrected_exit': fixed.returncode}))
    if not reproduced or not storage_reproduced or not passed:
        print(previous.stderr[-2000:])
        print(old_storage.stderr[-2000:])
        print(fixed.stderr[-2000:])
        raise SystemExit(1)


if __name__ == '__main__':
    main()
