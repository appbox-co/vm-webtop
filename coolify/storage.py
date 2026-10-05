#!/usr/bin/env python3
"""Initialize only this image's unused disk space, before Docker starts."""
import json
import os
from pathlib import Path
import subprocess
import uuid

DISK = '/dev/vda'
DEVICE = '/dev/vda2'
LABEL = 'COOLIFY_DATA'
STATE = Path('/var/lib/appbox-coolify/storage.json')
LINUX_TYPE = '0fc63daf-8483-4772-8e79-3d69d8477de4'
# Byte geometry of the checksum-verified, sealed 32 GiB Ubuntu template.
BASE = {1: (1190133760, 33169587712), 13: (1048576, 1072693760),
        14: (1074790400, 4194304), 15: (1078984704, 111149056)}
BEGIN = '# BEGIN Appbox Coolify storage\n'
END = '# END Appbox Coolify storage\n'


def run(args, *, accepted=(0,)):
    result = subprocess.run(args, text=True, capture_output=True, timeout=900)
    if result.returncode not in accepted:
        raise RuntimeError(f'{args[0]} failed ({result.returncode})')
    return result


def validate_layout(table, state=None):
    if table.get('label') != 'gpt' or table.get('unit') != 'sectors' or table.get('sectorsize') != 512:
        raise RuntimeError('Expected the sealed GPT disk with 512-byte sectors')
    parts = {}
    for part in table['partitions']:
        node = part['node']
        if not node.startswith(DISK) or not node[len(DISK):].isdigit():
            raise RuntimeError('Unexpected partition device')
        parts[int(node[len(DISK):])] = part
    if set(parts) - set(BASE) - {2}:
        raise RuntimeError('Unexpected partition: refusing to change storage')
    for number, geometry in BASE.items():
        part = parts.get(number, {})
        if (part.get('start', 0) * 512, part.get('size', 0) * 512) != geometry:
            raise RuntimeError('OS partition geometry changed')
    data = parts.get(2)
    if data and (not state or data.get('name') != LABEL
                 or data.get('type', '').lower() != LINUX_TYPE
                 or data.get('uuid', '').lower() != state['partition_uuid']
                 or data['start'] != 67108864):
        raise RuntimeError('Partition 2 is not this instance\'s data partition')
    if state and state['cache_ready'] and not data:
        raise RuntimeError('Initialized data partition is missing')
    return data


def validate_filesystem(properties, state):
    if properties and (properties.get('TYPE') != 'xfs'
                       or properties.get('LABEL') != LABEL
                       or properties.get('UUID', '').lower() != state['filesystem_uuid']):
        raise RuntimeError('Unexpected data filesystem; refusing to format or mount it')
    if not properties and state['cache_ready']:
        raise RuntimeError('Initialized data filesystem is missing')


def fstab_contents(original, filesystem_uuid):
    if original.count(BEGIN) != original.count(END) or original.count(BEGIN) > 1:
        raise RuntimeError('Invalid Coolify fstab block')
    if BEGIN in original:
        before, owned = original.split(BEGIN)
        _, after = owned.split(END)
        original = before + after
    for line in original.splitlines():
        fields = line.split()
        if line.lstrip().startswith('#') or len(fields) < 2:
            continue
        if fields[1] in ('/data', '/var/lib/docker', '/var/lib/containerd'):
            raise RuntimeError('A user-defined mount already owns a Coolify storage path')
    return original.rstrip() + '\n' + BEGIN + (
        f'UUID={filesystem_uuid} /data xfs defaults 0 0\n'
        '/data/docker /var/lib/docker none bind,x-systemd.requires-mounts-for=/data 0 0\n'
        '/data/containerd /var/lib/containerd none bind,x-systemd.requires-mounts-for=/data 0 0\n'
    ) + END


def save_state(state, *, new=False):
    STATE.parent.mkdir(mode=0o700, exist_ok=True)
    if new:
        with os.fdopen(os.open(STATE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as writer:
            json.dump(state, writer)
            writer.flush()
            os.fsync(writer.fileno())
    else:
        temporary = STATE.with_suffix('.tmp')
        with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as writer:
            json.dump(state, writer)
            writer.flush()
            os.fsync(writer.fileno())
        temporary.replace(STATE)
    run(['sync'])


def filesystem():
    result = run(['blkid', '-p', '-o', 'export', DEVICE], accepted=(0, 2))
    if result.returncode == 2 and result.stdout.strip():
        raise RuntimeError('Ambiguous partition signature')
    return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)


def mount_record(path):
    result = run(['findmnt', '-n', '-o', 'UUID,FSTYPE,FSROOT', '--mountpoint', path], accepted=(0, 1))
    return result.stdout.split() if result.returncode == 0 else None


def ensure_mount(source, target, filesystem_uuid, fsroot):
    Path(target).mkdir(parents=True, exist_ok=True)
    record = mount_record(target)
    if record is None:
        run(['mount', source, target] if target == '/data' else ['mount', '--bind', source, target])
        record = mount_record(target)
    if record != [filesystem_uuid, 'xfs', fsroot]:
        raise RuntimeError('Storage mount does not match this instance')


def main():
    if os.geteuid() != 0 or not Path('/etc/growroot-disabled').exists():
        raise RuntimeError('Expected the fixed-root Coolify image and root access')
    if run(['findmnt', '-n', '-o', 'SOURCE,FSTYPE', '/']).stdout.split() != ['/dev/vda1', 'ext4']:
        raise RuntimeError('Unexpected OS filesystem')
    for unit in ('docker.service', 'docker.socket', 'containerd.service'):
        if run(['systemctl', 'is-active', unit], accepted=(0, 3, 4)).returncode == 0:
            raise RuntimeError('Storage preparation must run before Docker and containerd')
    state = json.loads(STATE.read_text()) if STATE.exists() else None
    if state and (state.get('version') != 1 or not isinstance(state.get('cache_ready'), bool)
                  or any(str(uuid.UUID(state[key])) != state[key]
                         for key in ('partition_uuid', 'filesystem_uuid'))):
        raise RuntimeError('Invalid Coolify storage identity')
    table = json.loads(run(['sfdisk', '--json', DISK]).stdout)['partitiontable']
    data = validate_layout(table, state)
    # Validate mount ownership before any partition or filesystem changes.
    fstab = Path('/etc/fstab')
    fstab_contents(fstab.read_text(), state['filesystem_uuid'] if state else str(uuid.uuid4()))
    if not state:
        if mount_record('/data') or (Path('/data').exists() and any(Path('/data').iterdir())):
            raise RuntimeError('Existing data: use a fresh, uninitialized image')
        if int(run(['blockdev', '--getsize64', DISK]).stdout) < 34 * 1024**3:
            raise RuntimeError('Coolify requires at least 2 GiB beyond its 32 GiB OS disk')
        state = {'version': 1, 'partition_uuid': str(uuid.uuid4()),
                 'filesystem_uuid': str(uuid.uuid4()), 'cache_ready': False}
        save_state(state, new=True)
    if data is None:
        run(['sgdisk', '--move-second-header', '--new=2:67108864:0', '--typecode=2:8300',
             '--change-name=2:' + LABEL, '--partition-guid=2:' + state['partition_uuid'], DISK])
        if not Path(DEVICE).exists():
            run(['partx', '--add', '--nr', '2', DISK])
        run(['udevadm', 'settle', '--timeout=30'])
        table = json.loads(run(['sfdisk', '--json', DISK]).stdout)['partitiontable']
        validate_layout(table, state)
    properties = filesystem()
    validate_filesystem(properties, state)
    if not properties:
        # No force flag. -K avoids discarding the entire thin-provisioned data disk.
        run(['mkfs.xfs', '-K', '-L', LABEL, '-m', 'uuid=' + state['filesystem_uuid'], DEVICE])
        validate_filesystem(filesystem(), state)
    ensure_mount(DEVICE, '/data', state['filesystem_uuid'], '/')
    if not state['cache_ready']:
        if Path('/data/coolify').exists():
            raise RuntimeError('Existing Coolify state before cache initialization')
        for name in ('docker', 'containerd'):
            source = Path('/var/lib') / name
            if source.is_symlink() or mount_record(str(source)):
                raise RuntimeError('Unexpected container cache source')
            if name == 'docker':
                containers = source / 'containers'
                volumes = source / 'volumes'
                if containers.exists() and any(containers.iterdir()):
                    raise RuntimeError('Template contains containers')
                if volumes.exists() and any(p.is_dir() for p in volumes.iterdir()):
                    raise RuntimeError('Template contains Docker volumes')
            source.mkdir(exist_ok=True)
            target = Path('/data') / name
            target.mkdir(mode=0o700, exist_ok=True)
            run(['rsync', '-aHAX', '--numeric-ids', '--sparse', str(source) + '/', str(target) + '/'])
        # This marker prevents a later boot from overwriting customer Docker data.
        state['cache_ready'] = True
        save_state(state)
    for name in ('docker', 'containerd'):
        ensure_mount('/data/' + name, '/var/lib/' + name, state['filesystem_uuid'], '/' + name)
    content = fstab_contents(fstab.read_text(), state['filesystem_uuid'])
    if fstab.read_text() != content:
        temporary = fstab.with_name('fstab.coolify-tmp')
        temporary.write_text(content)
        temporary.chmod(0o644)
        temporary.replace(fstab)
        run(['systemctl', 'daemon-reload'])
    print('Coolify data filesystem and container storage are ready.', flush=True)


if __name__ == '__main__':
    main()
