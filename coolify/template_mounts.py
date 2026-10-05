#!/usr/bin/env python3
"""Prepare root mount options in an uninitialized Coolify template."""
from pathlib import Path


def prepare_root_mount(fstab):
    lines = fstab.read_text().splitlines(keepends=True)
    matches = 0
    for index, line in enumerate(lines):
        parts = line.split()
        if not line.lstrip().startswith('#') and len(parts) >= 4 and parts[1:3] == ['/', 'ext4']:
            matches += 1
            options = [option for option in parts[3].split(',') if option != 'discard']
            if not options:
                options = ['defaults']
            replacement = ','.join(options)
            if replacement != parts[3]:
                lines[index] = line.replace(parts[3], replacement, 1)
    if matches != 1:
        raise RuntimeError('Expected one ext4 root mount in the template')
    fstab.write_text(''.join(lines))


if __name__ == '__main__':
    if Path('/data/coolify/source/.env').exists():
        raise SystemExit('Use an uninitialized template')
    prepare_root_mount(Path('/etc/fstab'))
