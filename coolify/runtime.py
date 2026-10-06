#!/usr/bin/python3
"""First-boot setup for the Coolify VM image; no control-plane changes."""
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PACKAGE = Path('/usr/local/lib/appbox-coolify')
DATA = Path('/data/coolify')
CERTIFICATES = Path('/etc/ssl/domains')
ENVIRONMENT = Path('/etc/environment')
OPENSSL = 'openssl'
HASH = re.compile(r'\$2[aby]\$(?:1[0-9]|2[0-9]|3[01])\$[./A-Za-z0-9]{53}')
DOMAIN = re.compile(r'(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?')


class SetupError(Exception):
    pass


def run(arguments, *, input_data=None, timeout=300):
    try:
        result = subprocess.run(arguments, input=input_data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=True)
    except (OSError, subprocess.SubprocessError) as error:
        # Never copy Docker/SSH/PHP output into errors: it can contain credentials.
        raise SetupError(f'Required {Path(arguments[0]).name} command failed.') from error
    return result.stdout


def read_environment(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        name, separator, raw = line.partition('=')
        name = name.strip()
        if not separator or not re.fullmatch(r'[A-Z_][A-Z0-9_]*', name):
            raise SetupError('Invalid VM environment file.')
        try:
            parts = shlex.split(raw, comments=False)
        except ValueError as error:
            raise SetupError('Invalid VM environment quoting.') from error
        if len(parts) > 1 or name in values:
            raise SetupError('Ambiguous VM environment value.')
        values[name] = parts[0] if parts else ''
    return values


def valid_domain(value):
    value = value.lower()
    if not DOMAIN.fullmatch(value):
        raise SetupError('A valid dashboard domain is required.')
    return value


def initial_account(environment):
    domain = valid_domain(environment.get('VIRTUAL_HOST', ''))
    email = environment.get('COOLIFY_ADMIN_EMAIL', '')
    if len(email) > 255 or not re.fullmatch(r'[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', email):
        raise SetupError('COOLIFY_ADMIN_EMAIL must be a valid email address.')
    username, separator, password_hash = environment.get('BASIC_AUTH', '').partition(':')
    if username != 'appbox' or not separator or not HASH.fullmatch(password_hash):
        raise SetupError('The VM installation password hash is missing or invalid.')
    return domain, email, password_hash


def write_atomic(path, content, *, uid=None, gid=None, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_file() and not path.is_symlink() and path.read_bytes() == content:
        os.chmod(path, mode)
        os.chown(path, os.geteuid() if uid is None else uid,
                 os.getegid() if gid is None else gid)
        return False
    descriptor, temporary = tempfile.mkstemp(prefix='.appbox-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(content)
            os.fchmod(output.fileno(), mode)
            os.fchown(output.fileno(), os.geteuid() if uid is None else uid,
                      os.getegid() if gid is None else gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def new_environment(domain):
    return {
        'APP_ID': secrets.token_hex(16),
        'APP_NAME': 'Coolify',
        'APP_ENV': 'production',
        'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
        'APP_URL': 'https://' + domain,
        'DB_HOST': 'postgres',
        'DB_PORT': '5432',
        'DB_DATABASE': 'coolify',
        'DB_USERNAME': 'coolify',
        'DB_PASSWORD': secrets.token_hex(32),
        'REDIS_HOST': 'redis',
        'REDIS_PASSWORD': secrets.token_hex(32),
        'PUSHER_APP_ID': secrets.token_hex(32),
        'PUSHER_APP_KEY': secrets.token_hex(32),
        'PUSHER_APP_SECRET': secrets.token_hex(32),
        'PUSHER_BACKEND_HOST': 'coolify-realtime',
        'PUSHER_BACKEND_PORT': '6001',
        'PUSHER_SCHEME': 'http',
        'REGISTRY_URL': 'docker.io',
        'LATEST_IMAGE': '4.3.23',
    }


def proxy_gateway():
    routes = json.loads(run(['ip', '-j', '-4', 'route', 'show', 'default']))
    gateways = {route['gateway'] for route in routes if route.get('dst') == 'default' and 'gateway' in route}
    if len(gateways) != 1:
        raise SetupError('One Appbox bridge gateway is required for the proxy.')
    gateway = ipaddress.IPv4Address(gateways.pop())
    if gateway not in ipaddress.IPv4Network('172.20.0.0/16'):
        raise SetupError('The proxy gateway is outside the Appbox VM network.')
    return str(gateway)


def prepare_state(domain, email=None, *, data=DATA, package=PACKAGE):
    for relative in ('source', 'ssh/keys', 'ssh/mux', 'applications', 'databases',
                     'services', 'backups', 'images', 'proxy/dynamic', 'proxy/certs', 'sentinel'):
        directory = data / relative
        if not directory.exists():
            directory.mkdir(parents=True, mode=0o700)
            os.chown(directory, 9999, 0)
    # The upstream process must traverse both the root and ssh parent directory.
    for directory in (data, data / 'ssh'):
        os.chown(directory, 9999, 0)
        os.chmod(directory, 0o700)
    environment_file = data / 'source/.env'
    if not environment_file.exists():
        content = ''.join(f'{key}={value}\n' for key, value in new_environment(domain).items())
        write_atomic(environment_file, content.encode(), uid=9999)
    for source, destination in (('compose.yaml', 'source/compose.yaml'),
                                ('proxy.yaml', 'proxy/docker-compose.yml')):
        destination = data / destination
        if not destination.exists():
            content = (package / source).read_bytes()
            if source == 'proxy.yaml':
                if not email:
                    raise SetupError('An administrator email is required to create the proxy configuration.')
                # Email was validated before reaching here. Escape Compose's dollar
                # interpolation so addresses containing $ retain their literal value.
                content = content.replace(b'__APPBOX_ACME_EMAIL__', email.replace('$', '$$').encode())
                content = content.replace(b'__APPBOX_PROXY_GATEWAY__', proxy_gateway().encode())
            write_atomic(destination, content, uid=9999)


def valid_certificate(certificate, key, domain=None):
    arguments = [OPENSSL, 'x509', '-in', str(certificate), '-noout', '-checkend', '300']
    try:
        run(arguments, timeout=10)
        if domain is not None:
            # x509 -checkhost prints a mismatch but can still exit zero. Verify
            # returns a failure status. Trust here checks the supplied identity;
            # the final HTTPS probe separately verifies the public trust chain.
            run([OPENSSL, 'verify', '-trusted', str(certificate), '-partial_chain',
                 '-verify_hostname', domain, str(certificate)], timeout=10)
        certificate_public_key = run([OPENSSL, 'x509', '-in', str(certificate), '-pubkey', '-noout'], timeout=10)
        private_public_key = run([OPENSSL, 'pkey', '-in', str(key), '-pubout', '-passin', 'pass:'], timeout=10)
        return certificate_public_key == private_public_key
    except SetupError:
        return False


def sync_certificates(domain, *, data=DATA, certificates=CERTIFICATES):
    entries = []
    covers_dashboard = False
    root = certificates.resolve()
    if not certificates.is_dir():
        raise SetupError('Appbox certificate mounts are not available.')
    for directory in sorted(certificates.iterdir()):
        if not directory.is_dir():
            continue
        certificate = directory / 'fullchain.cer'
        if not certificate.is_file() or not certificate.resolve().is_relative_to(root):
            continue
        for key in sorted(directory.glob('*.key')):
            if not key.is_file() or not key.resolve().is_relative_to(root):
                continue
            if not valid_certificate(certificate, key):
                continue
            certificate_bytes, key_bytes = certificate.read_bytes(), key.read_bytes()
            digest = hashlib.sha256(certificate_bytes + key_bytes).hexdigest()
            prefix = 'appbox-' + digest
            write_atomic(data / f'proxy/certs/{prefix}.cer', certificate_bytes)
            write_atomic(data / f'proxy/certs/{prefix}.key', key_bytes)
            entries.append({'certFile': f'/traefik/certs/{prefix}.cer',
                            'keyFile': f'/traefik/certs/{prefix}.key'})
            covers_dashboard |= valid_certificate(certificate, key, domain)
            break
    if not covers_dashboard:
        raise SetupError('No mounted, valid certificate covers the dashboard domain.')
    # JSON is valid YAML. Changing the file causes Traefik to reload certificates.
    content = json.dumps({'tls': {'certificates': entries}}, sort_keys=True, indent=2).encode() + b'\n'
    write_atomic(data / 'proxy/dynamic/appbox-certificates.yaml', content)


def ensure_ssh():
    key = DATA / 'ssh/keys/id.root@host.docker.internal'
    if not key.exists():
        run(['ssh-keygen', '-t', 'ed25519', '-a', '100', '-q', '-N', '',
             '-C', 'appbox-coolify', '-f', str(key)])
        os.chown(key, 9999, 0)
        os.chmod(key, 0o600)
    public = run(['ssh-keygen', '-y', '-f', str(key)]).decode().strip()
    root_ssh = Path('/root/.ssh')
    root_ssh.mkdir(mode=0o700, exist_ok=True)
    authorized = root_ssh / 'authorized_keys'
    existing = authorized.read_text() if authorized.exists() else ''
    if not any(public in line for line in existing.splitlines()):
        write_atomic(authorized, (existing.rstrip() + '\n' + public + ' appbox-coolify\n').encode())
    # Validate a local connection using the VM's own public host key.
    host_key = Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text().split()
    known_hosts = DATA / 'ssh/appbox-known-hosts'
    write_atomic(known_hosts, f'127.0.0.1 {host_key[0]} {host_key[1]}\n'.encode())
    run(['ssh', '-i', str(key), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
         '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=yes',
         '-o', 'UserKnownHostsFile=' + str(known_hosts), 'root@127.0.0.1', 'true'], timeout=15)


def compose(*arguments):
    return run(['docker', 'compose', '--project-name', 'coolify', '--env-file',
                str(DATA / 'source/.env'), '-f', str(DATA / 'source/compose.yaml'), *arguments], timeout=600)


def wait_for_health():
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=5) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(2)
    raise SetupError('Coolify did not become ready within ten minutes.')


def provision(payload):
    return run(['docker', 'exec', '-i', 'coolify', 'php', '/appbox-provision.php'],
               input_data=json.dumps(payload).encode(), timeout=300)


def bootstrap():
    ready = DATA / 'source/.appbox-ready'
    initial = not ready.exists()
    if initial:
        domain, email, password_hash = initial_account(read_environment(ENVIRONMENT))
    else:
        domain = valid_domain(json.loads(ready.read_text())['domain'])
        email = password_hash = None
    prepare_state(domain, email)
    sync_certificates(domain)
    ensure_ssh()
    try:
        run(['docker', 'network', 'inspect', 'coolify'])
    except SetupError:
        run(['docker', 'network', 'create', '--attachable', 'coolify'])
    compose('up', '-d', '--wait', '--wait-timeout', '600')
    wait_for_health()
    print('Coolify initialization completed; provisioning the account and proxy.', flush=True)
    provision({'operation': 'provision', 'initial': initial, 'domain': domain,
               'email': email, 'password_hash': password_hash,
               'proxy_configuration': (DATA / 'proxy/docker-compose.yml').read_text()})
    # Verify TLS with normal trust and SNI; a self-signed fallback fails this gate.
    print('Coolify account and proxy prepared; verifying HTTPS.', flush=True)
    # The seeder queues proxy startup; init-script readiness does not imply
    # that queued action has finished or the file provider has loaded the route.
    run(['curl', '--fail', '--silent', '--show-error', '--max-time', '10',
         '--retry', '60', '--retry-all-errors', '--retry-delay', '2', '--retry-max-time', '180',
         '--resolve', f'{domain}:443:127.0.0.1', '-o', '/dev/null', f'https://{domain}/login'], timeout=195)
    write_atomic(ready, json.dumps({'domain': domain, 'version': '4.3.23'}).encode() + b'\n')
    print('Coolify administrator, HTTPS endpoint and proxy are ready.')


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('bootstrap', 'sync-certificates', 'reset-password'):
        raise SetupError('Usage: runtime.py bootstrap|sync-certificates|reset-password')
    if os.geteuid() != 0:
        raise SetupError('This command requires root inside the Coolify VM.')
    if sys.argv[1] == 'bootstrap':
        bootstrap()
    elif sys.argv[1] == 'sync-certificates':
        domain = valid_domain(json.loads((DATA / 'source/.appbox-ready').read_text())['domain'])
        sync_certificates(domain)
        print('Appbox certificate check completed.')
    else:
        password = sys.stdin.buffer.read(73)
        if not 12 <= len(password) <= 72:
            raise SetupError('The recovery password must contain 12–72 UTF-8 bytes.')
        value = password.decode('utf-8')
        if not all(re.search(pattern, value) for pattern in (r'[a-z]', r'[A-Z]', r'[0-9]', r'[^A-Za-z0-9]')):
            raise SetupError('Use upper and lower case letters, a number and a symbol.')
        provision({'operation': 'reset-password', 'password': value})
        print('Coolify administrator password updated.')


if __name__ == '__main__':
    try:
        main()
    except SetupError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError):
        # Keep errors useful without leaking file contents, values or subprocess output.
        print('Coolify setup failed. Check VM environment, certificate mounts and Docker service; the installed callback is blocked.', file=sys.stderr)
        sys.exit(1)
