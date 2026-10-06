#!/usr/bin/env python3
"""Validate two disposable, isolated clones of a sealed Coolify image."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import threading
import time


def run(args, *, data=None, timeout=120):
    result = subprocess.run(args, input=data, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        # Guest output can contain generated secrets; never print it.
        raise RuntimeError(f'{Path(args[0]).name} exited {result.returncode}')
    return result.stdout


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


ROOT_CHECK = r"""import hashlib,json,os,socket,subprocess
from pathlib import Path
assert os.geteuid()==0
assert socket.gethostname() in ('coolify-clone-1','coolify-clone-2')
units={name:dict(line.split('=',1) for line in subprocess.check_output(['systemctl','show',name,'-p','ActiveState','-p','Result','-p','ExecMainStatus'],text=True).splitlines()) for name in ('appbox-coolify.service','docker.service','appbox-coolify-storage.service','cylo-callback.service')}
boot_log=subprocess.check_output(['journalctl','-b','--no-pager','-o','cat'],text=True).splitlines()
cycle_lines=[line for line in boot_log if 'ordering cycle' in line or ('Job ' in line and 'deleted' in line)]
if cycle_lines:
 print(json.dumps({'terminal_failure':True,'boot_ordering_cycle':True,'units':units}));raise SystemExit(0)
if any(state['ActiveState']=='failed' for state in units.values()):
 allowed={'Coolify initialization completed; provisioning the account and proxy.','Coolify account and proxy prepared; verifying HTTPS.','Coolify administrator, HTTPS endpoint and proxy are ready.','Required docker command failed.','Required curl command failed.'}
 lines=subprocess.check_output(['journalctl','-b','--no-pager','-u','appbox-coolify.service','-o','cat'],text=True).splitlines()
 print(json.dumps({'terminal_failure':True,'units':units,'safe_setup_phases':[line for line in lines if line in allowed]}));raise SystemExit(0)
env={}
for line in Path('/data/coolify/source/.env').read_text().splitlines():
 k,v=line.split('=',1);env[k]=v
unit=lambda name:dict(line.split('=',1) for line in subprocess.check_output(['systemctl','show',name,'-p','Result','-p','ExecMainStatus','-p','ExecMainStartTimestampMonotonic'],text=True).splitlines())
callback=unit('cylo-callback.service')
assert callback['Result']=='success' and callback['ExecMainStatus']=='0' and int(callback['ExecMainStartTimestampMonotonic'])>0
assert Path('/data/coolify/source/.appbox-ready').is_file()
assert unit('appbox-coolify.service')['Result']=='success'
assert Path('/data/coolify/source/.env').stat().st_uid==9999
assert Path('/data/coolify/source/.env').stat().st_mode&0o777==0o600
states=dict(line.split(':',1) for line in subprocess.check_output(['docker','ps','--format','{{.Names}}:{{.State}}'],text=True).splitlines())
assert all(states.get(name)=='running' for name in ('coolify','coolify-db','coolify-redis','coolify-realtime','coolify-proxy'))
php=r'''require '/var/www/html/vendor/autoload.php';$app=require '/var/www/html/bootstrap/app.php';$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();$u=App\Models\User::findOrFail(0);$s=App\Models\InstanceSettings::findOrFail(0);echo json_encode(['owner'=>$u->teams()->where('teams.id',0)->wherePivot('role','owner')->exists(),'registration_disabled'=>!$s->is_registration_enabled,'automatic_updates_disabled'=>!$s->is_auto_update_enabled,'name'=>$u->name]);'''
account=json.loads(subprocess.check_output(['docker','exec','coolify','php','-r',php],text=True))
assert account['owner'] and account['registration_disabled'] and account['automatic_updates_disabled']
fingerprints={k:hashlib.sha256(env[k].encode()).hexdigest() for k in ('APP_ID','APP_KEY','DB_PASSWORD','REDIS_PASSWORD','PUSHER_APP_ID','PUSHER_APP_KEY','PUSHER_APP_SECRET')}
for k,path in {'localhost_ssh_key':'/data/coolify/ssh/keys/id.root@host.docker.internal','ssh_host_key':'/etc/ssh/ssh_host_ed25519_key.pub','machine_id':'/etc/machine-id','storage_identity':'/var/lib/appbox-coolify/storage.json'}.items():fingerprints[k]=hashlib.sha256(Path(path).read_bytes()).hexdigest()
print(json.dumps({'fingerprints':fingerprints,'account_name':account['name'],'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'root_checks_passed':True}))
"""


def clone(receipt, work, number, ca, ca_key, fixture_hash):
    scratch = work / f'clone-{number}'
    scratch.mkdir(mode=0o700)
    disk = scratch / 'clone.qcow2'
    image = (receipt.parent / json.loads(receipt.read_text())['image']).resolve()
    run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'qcow2', '-b', str(image), str(disk), '64G'])
    key = scratch / 'access-key'
    run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'disposable-coolify-clone-check', '-f', str(key)])
    domain = f'coolify-clone-{number}.example.test'
    leaf = scratch / 'leaf.pem'
    leaf_key = scratch / 'leaf.key'
    request = scratch / 'leaf.csr'
    run(['openssl', 'req', '-new', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
         '-nodes', '-subj', '/CN=' + domain, '-keyout', str(leaf_key), '-out', str(request)])
    extensions = scratch / 'extensions'
    extensions.write_text('subjectAltName=DNS:' + domain + '\nextendedKeyUsage=serverAuth\n')
    run(['openssl', 'x509', '-req', '-in', str(request), '-CA', str(ca), '-CAkey', str(ca_key),
         '-set_serial', str(number), '-days', '2', '-extfile', str(extensions), '-out', str(leaf)])
    seed = scratch / 'seed'
    seed.mkdir(mode=0o700)
    environment = f'VIRTUAL_HOST="{domain}"\nCOOLIFY_ADMIN_EMAIL="owner@example.test"\nBASIC_AUTH="appbox:{fixture_hash}"\nINSTANCE_ID="{9000000 + number}"\n'
    callback = '[Unit]\nDescription=Isolated callback fixture\nAfter=network-online.target cloud-final.service\nWants=network-online.target\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n[Install]\nWantedBy=multi-user.target\n'
    files = [(f'/etc/ssl/domains/{domain}/fullchain.cer', leaf.read_text(), '0644'),
             (f'/etc/ssl/domains/{domain}/{domain}.key', leaf_key.read_text(), '0600'),
             ('/usr/local/share/ca-certificates/coolify-fixture.crt', ca.read_text(), '0644'),
             ('/etc/environment', environment, '0600'),
             ('/etc/systemd/system/cylo-callback.service', callback, '0644')]
    config = {
        'users': [{'name': 'appbox', 'uid': 1000, 'shell': '/bin/bash', 'lock_passwd': True,
                   'sudo': ['ALL=(ALL) NOPASSWD:ALL'], 'groups': ['sudo'],
                   'ssh_authorized_keys': [key.with_suffix('.pub').read_text().strip()]}],
        'ssh_pwauth': False, 'ssh_deletekeys': False,
        # Generate and pin a fresh key before late cloud-final setup can stall.
        # A single write keeps the marker and public key together on the console.
        'bootcmd': [['bash', '-c', 'ssh-keygen -A && python3 -c ' + shlex.quote(
            "import os;from pathlib import Path;fd=os.open('/dev/ttyS0',os.O_WRONLY);"
            "os.write(fd,b'APPBOX_CLONE_HOST_KEY '+Path('/etc/ssh/ssh_host_ed25519_key.pub').read_bytes());os.close(fd)")]],
        'resize_rootfs': False, 'growpart': {'mode': 'off'},
        'write_files': [{'path': path, 'content': content, 'permissions': mode, 'owner': 'root:root'}
                        for path, content, mode in files],
        'runcmd': [['update-ca-certificates'], ['systemctl', 'daemon-reload'],
                   ['systemctl', 'enable', 'cylo-callback.service'],
                   ['systemctl', 'start', '--no-block', 'cylo-callback.service']],
    }
    (seed / 'user-data').write_text('#cloud-config\n' + json.dumps(config) + '\n')
    (seed / 'meta-data').write_text(json.dumps({'instance-id': scratch.name + '-' + work.name,
                                              'local-hostname': f'coolify-clone-{number}'}) + '\n')
    (seed / 'vendor-data').write_text('#cloud-config\n{}\n')
    (seed / 'network-config').write_text(json.dumps({'version': 2, 'ethernets': {
        'fixture': {'match': {'name': 'en*'}, 'dhcp4': True}}}) + '\n')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
                                             functools.partial(QuietHandler, directory=str(seed)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    accelerator = 'kvm' if os.access('/dev/kvm', os.R_OK | os.W_OK) else 'tcg,thread=multi'
    qemu = None

    def boot(index):
        return subprocess.Popen([
            'qemu-system-x86_64', '-machine', 'q35', '-accel', accelerator,
            '-cpu', 'host' if accelerator == 'kvm' else 'max', '-smp', '4', '-m', '8192',
            '-drive', f'file={disk},if=virtio,format=qcow2,discard=unmap',
            '-netdev', f'user,id=fixture,net=172.20.35.0/24,host=172.20.35.1,dhcpstart=172.20.35.15,hostfwd=tcp:127.0.0.1:{port}-:22',
            '-device', 'virtio-net-pci,netdev=fixture',
            '-smbios', f'type=1,serial=ds=nocloud;s=http://172.20.35.1:{server.server_port}/',
            '-display', 'none', '-monitor', 'none',
            '-serial', f'file:{scratch / ("console-" + str(index) + ".log")}', '-no-reboot',
        ], stdout=subprocess.DEVNULL, stderr=(scratch / f'qemu-{index}.log').open('wb'))

    def wait(test, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if qemu.poll() is not None:
                raise RuntimeError('Isolated guest stopped before validation')
            try:
                result = test()
                if result:
                    return result
            except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError):
                pass
            time.sleep(3)
        raise RuntimeError('Timed out waiting for isolated clone readiness')

    try:
        qemu = boot(1)
        print(f'Clone {number}: booting sealed image.', flush=True)

        def public_key():
            text = (scratch / 'console-1.log').read_text(errors='replace')
            found = re.search(r'APPBOX_CLONE_HOST_KEY (ssh-ed25519 [A-Za-z0-9+/=]+)', text)
            return found.group(1) if found else None

        host_key = wait(public_key, 1200)
        known = scratch / 'known-hosts'
        known.write_text(f'[127.0.0.1]:{port} {host_key}\n')
        ssh = ['ssh', '-p', str(port), '-i', str(key), '-oIdentitiesOnly=yes', '-oBatchMode=yes',
               '-oStrictHostKeyChecking=yes', '-oUserKnownHostsFile=' + str(known),
               '-oConnectTimeout=5', 'appbox@127.0.0.1']
        def ssh_ready():
            run(ssh + ['sudo -n true'], timeout=15)
            return True
        wait(ssh_ready, 1200)
        run(ssh + ['sudo -n cloud-init status --wait'], timeout=1200)
        command = 'sudo -n python3 -c ' + shlex.quote(ROOT_CHECK)
        def check():
            result = json.loads(run(ssh + [command], timeout=45))
            if result.get('terminal_failure'):
                raise AssertionError('Isolated clone failed: ' + json.dumps(result))
            return result
        first = wait(check, 1200)
        print(f'Clone {number}: cold bootstrap, owner and HTTPS readiness passed.', flush=True)
        run(ssh + ['sudo -n systemctl start fstrim.service'], timeout=180)
        trim_check = "import subprocess; s=dict(line.split('=',1) for line in subprocess.check_output(['systemctl','show','fstrim.service','-p','ConditionResult','-p','Result','-p','ExecMainStatus','-p','ExecMainStartTimestampMonotonic'],text=True).splitlines());assert s['ConditionResult']=='yes' and s['Result']=='success' and s['ExecMainStatus']=='0' and int(s['ExecMainStartTimestampMonotonic'])>0"
        run(ssh + ['sudo -n python3 -c ' + shlex.quote(trim_check)])
        print(f'Clone {number}: actual 64 GiB discard test passed.', flush=True)
        mutation = r"""require '/var/www/html/vendor/autoload.php';$app=require '/var/www/html/bootstrap/app.php';$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();$u=App\Models\User::findOrFail(0);$u->name='Clone persistence fixture';$u->save();"""
        run(ssh + ['sudo -n docker exec coolify php -r ' + shlex.quote(mutation)])
        run(ssh + ['sudo -n systemd-run --quiet --on-active=2 --unit=coolify-fixture-poweroff systemctl poweroff'])
        qemu.wait(timeout=120)
        assert qemu.returncode == 0
        qemu = boot(2)
        print(f'Clone {number}: checking reboot persistence.', flush=True)
        second = wait(check, 1200)
        assert first['boot_id'] != second['boot_id']
        assert first['fingerprints'] == second['fingerprints']
        assert second['account_name'] == 'Clone persistence fixture'
        print(f'Clone {number}: post-trim reboot persistence passed.', flush=True)
        run(ssh + ['sudo -n systemd-run --quiet --on-active=2 --unit=coolify-fixture-poweroff systemctl poweroff'])
        qemu.wait(timeout=120)
        assert qemu.returncode == 0
        return {'fingerprints': first['fingerprints'], 'cold_boot': True, 'reboot': True,
                'trim_64gib': True, 'root_checks': True}
    finally:
        server.shutdown()
        server.server_close()
        if qemu and qemu.poll() is None:
            qemu.terminate()
            try:
                qemu.wait(timeout=30)
            except subprocess.TimeoutExpired:
                qemu.kill()
                qemu.wait(timeout=10)
        # Only access material generated under this newly created clone directory.
        for path in (key, key.with_suffix('.pub'), leaf_key, seed / 'user-data'):
            path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    # A synthetic test hash, never an operator or customer credential.
    parser.add_argument('--fixture-hash', required=True)
    args = parser.parse_args()
    args.receipt = args.receipt.resolve()
    assert socket.getfqdn() == 'builder.grant.appboxes.co' and os.geteuid() != 0
    assert re.fullmatch(r'\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}', args.fixture_hash)
    work = args.work_dir.resolve()
    assert work.parent == Path('/home/appbox/builds') and work.name.startswith('coolify-clones-')
    work.mkdir(mode=0o700)
    receipt = json.loads(args.receipt.read_text())
    image = args.receipt.parent / receipt['image']
    with image.open('rb') as source:
        assert hashlib.file_digest(source, 'sha256').hexdigest() == receipt['image_sha256']
    assert receipt['normal_appbox_install_tested'] is False
    ca = work / 'ca.pem'
    ca_key = work / 'ca.key'
    run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
         '-nodes', '-days', '2', '-subj', '/CN=Disposable Coolify fixture CA',
         '-keyout', str(ca_key), '-out', str(ca)])
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda n: clone(args.receipt, work, n, ca, ca_key,
                                                    args.fixture_hash), [1, 2]))
        independence = {key: results[0]['fingerprints'][key] != results[1]['fingerprints'][key]
                        for key in results[0]['fingerprints']}
        assert all(independence.values())
        output = {
            'created_at': datetime.now(timezone.utc).isoformat(),
            'image_commit': receipt['commit'], 'image_sha256': receipt['image_sha256'],
            'clones': [{k: v for k, v in result.items() if k != 'fingerprints'} for result in results],
            'independent_generated_state': independence, 'normal_appbox_callback_tested': False,
            'public_stream_tls_tested': False, 'grant_18000gib_trim_tested': False,
        }
        (work / 'validation.json').write_text(json.dumps(output, indent=2) + '\n')
        print(json.dumps(output), flush=True)
    finally:
        ca_key.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
