import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import DEFAULT, patch

PACKAGE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('coolify_runtime', PACKAGE / 'runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class EnvironmentTests(unittest.TestCase):
    def test_vm_password_hash_is_consumed_without_shell_expansion(self):
        fixture_hash = '$2y$12$' + 'A' * 53
        with tempfile.TemporaryDirectory() as directory:
            environment = Path(directory) / 'environment'
            environment.write_text(f'VIRTUAL_HOST="coolify.example.test"\n'
                                   f'COOLIFY_ADMIN_EMAIL="admin@example.test"\n'
                                   f'BASIC_AUTH="appbox:{fixture_hash}"\n'
                                   'IGNORED="$(touch should-not-exist)"\n')
            values = runtime.read_environment(environment)
            self.assertEqual(runtime.initial_account(values),
                             ('coolify.example.test', 'admin@example.test', fixture_hash))
            self.assertEqual(values['IGNORED'], '$(touch should-not-exist)')

    def test_missing_or_invalid_install_inputs_fail(self):
        values = {'VIRTUAL_HOST': 'coolify.example.test',
                  'COOLIFY_ADMIN_EMAIL': 'admin@example.test',
                  'BASIC_AUTH': 'appbox:$2y$12$' + 'A' * 53}
        for name, replacement in [('VIRTUAL_HOST', 'example.test;whoami'),
                                  ('VIRTUAL_HOST', '*.example.test'),
                                  ('VIRTUAL_HOST', 'a.example.test,b.example.test'),
                                  ('COOLIFY_ADMIN_EMAIL', 'not-an-email'),
                                  ('BASIC_AUTH', 'appbox:plaintext'),
                                  ('BASIC_AUTH', 'root:$2y$12$' + 'A' * 53)]:
            with self.subTest(name=name, replacement=replacement):
                invalid = dict(values, **{name: replacement})
                with self.assertRaises(runtime.SetupError):
                    runtime.initial_account(invalid)

    def test_duplicate_and_malformed_environment_values_fail(self):
        for content in ('FOO=one\nFOO=two\n', 'FOO="unterminated\n', 'FOO=one two\n'):
            with tempfile.TemporaryDirectory() as directory:
                environment = Path(directory) / 'environment'
                environment.write_text(content)
                with self.assertRaises(runtime.SetupError):
                    runtime.read_environment(environment)


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        gateway = patch.object(runtime, 'proxy_gateway', return_value='172.20.35.1')
        gateway.start()
        self.addCleanup(gateway.stop)

    def test_restart_preserves_generated_keys_and_user_edited_compose(self):
        # Ownership syscalls need Linux root coverage in the VM release gate.
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime.os, 'chown'), patch.object(runtime.os, 'fchown'):
            data = Path(directory) / 'data'
            runtime.prepare_state('coolify.example.test', 'admin@example.test', data=data, package=PACKAGE)
            environment = (data / 'source/.env').read_bytes()
            self.assertNotIn(b'BASIC_AUTH', environment)
            self.assertNotIn(b'ROOT_USER_PASSWORD', environment)
            self.assertEqual((data / 'source/.env').stat().st_mode & 0o777, 0o600)
            proxy = (data / 'proxy/docker-compose.yml').read_text()
            self.assertIn('--certificatesresolvers.letsencrypt.acme.email=admin@example.test', proxy)
            self.assertNotIn('__APPBOX_ACME_EMAIL__', proxy)
            self.assertIn('--entrypoints.https.proxyprotocol.trustedips=172.20.35.1/32', proxy)
            self.assertNotIn('__APPBOX_PROXY_GATEWAY__', proxy)
            (data / 'source/compose.yaml').write_text('# user configuration\n')
            (data / 'proxy/docker-compose.yml').write_text('# user proxy configuration\n')
            runtime.prepare_state('different.example.test', data=data, package=PACKAGE)
            self.assertEqual(environment, (data / 'source/.env').read_bytes())
            self.assertEqual((data / 'source/compose.yaml').read_text(), '# user configuration\n')
            self.assertEqual((data / 'proxy/docker-compose.yml').read_text(), '# user proxy configuration\n')

    def test_acme_email_retains_literal_dollar_characters(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime.os, 'chown'), patch.object(runtime.os, 'fchown'):
            data = Path(directory) / 'data'
            runtime.prepare_state('coolify.example.test', 'admin$tag@example.test', data=data, package=PACKAGE)
            environment = dict(os.environ, tag='must-not-expand')
            completed = subprocess.run(['docker', 'compose', '-f', str(data / 'proxy/docker-compose.yml'),
                                        'config', '--format', 'json'], env=environment,
                                       capture_output=True, text=True, check=True)
            commands = json.loads(completed.stdout)['services']['traefik']['command']
            # Compose re-escapes dollars when rendering config for reuse as a
            # Compose file; its runtime model contains the literal single dollar.
            self.assertIn('--certificatesresolvers.letsencrypt.acme.email=admin$$tag@example.test', commands)
            self.assertNotIn('must-not-expand', completed.stdout)

    def test_subprocess_failure_does_not_expose_output_or_input(self):
        error = subprocess.CalledProcessError(1, ['docker'], output=b'private-output', stderr=b'private-error')
        with patch.object(runtime.subprocess, 'run', side_effect=error):
            with self.assertRaises(runtime.SetupError) as raised:
                runtime.run(['docker', 'exec'], input_data=b'private-input')
        self.assertEqual(str(raised.exception), 'Required docker command failed.')

    def test_unchanged_managed_key_permissions_are_restored(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.key'
            runtime.write_atomic(path, b'fixture')
            path.chmod(0o644)
            self.assertFalse(runtime.write_atomic(path, b'fixture'))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


class ProxyGatewayTests(unittest.TestCase):
    def test_only_the_actual_bridge_gateway_is_trusted(self):
        routes = [{'dst': 'default', 'gateway': '172.20.35.1', 'dev': name}
                  for name in ('ens3', 'enp0s4')]
        with patch.object(runtime, 'run', return_value=json.dumps(routes).encode()):
            self.assertEqual(runtime.proxy_gateway(), '172.20.35.1')
        for routes in ([], [{'dst':'default', 'gateway':'203.0.113.1'}],
                       [{'dst':'default', 'gateway':'172.20.35.1'},
                        {'dst':'default', 'gateway':'172.20.36.1'}]):
            with self.subTest(routes=routes), patch.object(runtime, 'run', return_value=json.dumps(routes).encode()):
                with self.assertRaises(runtime.SetupError):
                    runtime.proxy_gateway()


class TemplateMountTests(unittest.TestCase):
    def test_only_root_discard_changes_and_preparation_is_repeatable(self):
        spec = importlib.util.spec_from_file_location('template_mounts', PACKAGE / 'template_mounts.py')
        mounts = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mounts)
        with tempfile.TemporaryDirectory() as directory:
            fstab = Path(directory) / 'fstab'
            fstab.write_text('# Preserve this comment\nLABEL=cloudimg-rootfs / ext4 discard,commit=30,errors=remount-ro 0 1\nLABEL=BOOT /boot ext4 defaults 0 2\n')
            mounts.prepare_root_mount(fstab)
            expected = '# Preserve this comment\nLABEL=cloudimg-rootfs / ext4 commit=30,errors=remount-ro 0 1\nLABEL=BOOT /boot ext4 defaults 0 2\n'
            self.assertEqual(fstab.read_text(), expected)
            mounts.prepare_root_mount(fstab)
            self.assertEqual(fstab.read_text(), expected)


class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.openssl = shutil.which('openssl')
        homebrew = Path('/opt/homebrew/opt/openssl@3/bin/openssl')
        if homebrew.is_file():
            cls.openssl = str(homebrew)
        if not cls.openssl:
            raise RuntimeError('OpenSSL is required; certificate coverage cannot be skipped.')
        runtime.OPENSSL = cls.openssl

    def make_certificate(self, path, domain):
        path.mkdir(parents=True)
        subprocess.run([self.openssl, 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                        'ec_paramgen_curve:prime256v1', '-nodes', '-days', '2',
                        '-subj', '/CN=' + domain, '-addext', 'subjectAltName=DNS:' + domain,
                        '-keyout', str(path / 'fixture.key'), '-out', str(path / 'fullchain.cer')],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

    def test_real_certificate_matching_key_and_domain(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_certificate(root / 'first', 'coolify.example.test')
            self.make_certificate(root / 'second', 'other.example.test')
            certificate = root / 'first/fullchain.cer'
            key = root / 'first/fixture.key'
            self.assertTrue(runtime.valid_certificate(certificate, key, 'coolify.example.test'))
            self.assertFalse(runtime.valid_certificate(certificate, key, 'other.example.test'))
            self.assertFalse(runtime.valid_certificate(certificate, root / 'second/fixture.key'))

    def test_wildcard_selection_renewal_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            certificates, data = root / 'certificates', root / 'data'
            self.make_certificate(certificates / 'example.test', '*.example.test')
            runtime.sync_certificates('coolify.example.test', data=data, certificates=certificates)
            dynamic = data / 'proxy/dynamic/appbox-certificates.yaml'
            first = dynamic.read_bytes()
            entries = json.loads(first)['tls']['certificates']
            copied_key = data / 'proxy/certs' / Path(entries[0]['keyFile']).name
            self.assertEqual(copied_key.stat().st_mode & 0o777, 0o600)
            first_mtime = dynamic.stat().st_mtime_ns
            runtime.sync_certificates('coolify.example.test', data=data, certificates=certificates)
            self.assertEqual(dynamic.stat().st_mtime_ns, first_mtime)
            shutil.rmtree(certificates / 'example.test')
            self.make_certificate(certificates / 'example.test', '*.example.test')
            runtime.sync_certificates('coolify.example.test', data=data, certificates=certificates)
            self.assertNotEqual(dynamic.read_bytes(), first)

    def test_missing_mismatched_and_outside_mount_keys_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            certificates, data = root / 'certificates', root / 'data'
            self.make_certificate(certificates / 'example.test', 'other.example.test')
            with self.assertRaises(runtime.SetupError):
                runtime.sync_certificates('coolify.example.test', data=data, certificates=certificates)
            self.assertFalse((data / 'proxy/dynamic/appbox-certificates.yaml').exists())
            self.make_certificate(root / 'outside', 'coolify.example.test')
            (certificates / 'escape').symlink_to(root / 'outside', target_is_directory=True)
            with self.assertRaises(runtime.SetupError):
                runtime.sync_certificates('coolify.example.test', data=data, certificates=certificates)


class ComposeTests(unittest.TestCase):
    def compose_config(self, file):
        if not shutil.which('docker'):
            raise RuntimeError('Docker Compose is required; configuration coverage cannot be skipped.')
        environment = dict(os.environ, DB_USERNAME='fixture', DB_PASSWORD='fixture',
                           REDIS_PASSWORD='fixture', PUSHER_APP_ID='fixture',
                           PUSHER_APP_KEY='fixture', PUSHER_APP_SECRET='fixture')
        with tempfile.TemporaryDirectory() as directory:
            # Only substitute the guest env-file path for the local parser.
            fixture = Path(directory) / 'fixture.env'
            fixture.write_text('')
            override = Path(directory) / 'override.yaml'
            override.write_text('services:\n  coolify:\n    env_file: !override\n      - '
                                + str(fixture) + '\n')
            arguments = ['docker', 'compose', '-f', str(PACKAGE / file)]
            if file == 'compose.yaml':
                arguments += ['-f', str(override)]
            completed = subprocess.run(arguments + ['config', '--format', 'json', '--no-env-resolution'],
                                       env=environment, capture_output=True, text=True, check=True)
        return json.loads(completed.stdout)

    def test_dashboard_is_loopback_only_and_dependencies_are_private(self):
        services = self.compose_config('compose.yaml')['services']
        self.assertEqual(set(services), {'coolify', 'postgres', 'redis', 'soketi'})
        self.assertEqual(services['coolify']['ports'][0]['host_ip'], '127.0.0.1')
        self.assertEqual(len(services['coolify']['ports']), 1)
        for service in ('postgres', 'redis', 'soketi'):
            self.assertNotIn('ports', services[service])

    def test_proxy_preserves_tcp_tls_and_avoids_http_validation(self):
        proxy = self.compose_config('proxy.yaml')['services']['traefik']
        commands = proxy['command']
        self.assertIn('--certificatesresolvers.letsencrypt.acme.tlschallenge=true', commands)
        self.assertFalse(any('httpchallenge' in command or 'http3' in command for command in commands))
        self.assertEqual({port['published'] for port in proxy['ports']}, {'80', '443'})
        self.assertTrue(all(port['protocol'] == 'tcp' for port in proxy['ports']))


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.data = Path(self.directory.name) / 'data'
        (self.data / 'proxy').mkdir(parents=True)
        (self.data / 'source').mkdir()
        (self.data / 'proxy/docker-compose.yml').write_text('# proxy fixture\n')
        self.ready = self.data / 'source/.appbox-ready'
        self.fixture_hash = '$2y$12$' + 'A' * 53
        environment = Path(self.directory.name) / 'environment'
        environment.write_text('VIRTUAL_HOST="coolify.example.test"\n'
                               'COOLIFY_ADMIN_EMAIL="admin@example.test"\n'
                               f'BASIC_AUTH="appbox:{self.fixture_hash}"\n')
        paths = patch.multiple(runtime, DATA=self.data, ENVIRONMENT=environment)
        paths.start()
        self.addCleanup(paths.stop)
        dependencies = patch.multiple(runtime, prepare_state=DEFAULT, sync_certificates=DEFAULT,
                                      ensure_ssh=DEFAULT, compose=DEFAULT, wait_for_health=DEFAULT,
                                      provision=DEFAULT, run=DEFAULT)
        self.dependencies = dependencies.start()
        self.addCleanup(dependencies.stop)
        self.output = io.StringIO()
        stdout = patch('sys.stdout', self.output)
        stdout.start()
        self.addCleanup(stdout.stop)

    def test_first_boot_uses_install_hash_and_records_readiness_after_tls(self):
        runtime.bootstrap()
        payload = self.dependencies['provision'].call_args.args[0]
        self.assertTrue(payload['initial'])
        self.assertEqual(payload['password_hash'], self.fixture_hash)
        self.assertEqual(payload['email'], 'admin@example.test')
        self.dependencies['prepare_state'].assert_called_once_with('coolify.example.test', 'admin@example.test')
        self.assertEqual(json.loads(self.ready.read_text()),
                         {'domain': 'coolify.example.test', 'version': '4.3.23'})
        self.assertNotIn(self.fixture_hash, self.output.getvalue())
        probe = self.dependencies['run'].call_args.args[0]
        self.assertEqual(probe[0], 'curl')
        self.assertNotIn('--insecure', probe)

    def test_failed_https_probe_does_not_record_ready_state(self):
        def run(arguments, **kwargs):
            if arguments[0] == 'curl':
                raise runtime.SetupError('Required curl command failed.')
            return b''
        self.dependencies['run'].side_effect = run
        with self.assertRaises(runtime.SetupError):
            runtime.bootstrap()
        self.assertFalse(self.ready.exists())

    def test_missing_certificate_blocks_container_start_and_account_setup(self):
        self.dependencies['sync_certificates'].side_effect = runtime.SetupError('Certificate missing.')
        with self.assertRaises(runtime.SetupError):
            runtime.bootstrap()
        self.dependencies['compose'].assert_not_called()
        self.dependencies['provision'].assert_not_called()
        self.assertFalse(self.ready.exists())

    def test_restart_does_not_resubmit_install_account_credentials(self):
        self.ready.write_text(json.dumps({'domain': 'coolify.example.test', 'version': '4.3.23'}))
        runtime.ENVIRONMENT.write_text('BASIC_AUTH=invalid\n')
        runtime.bootstrap()
        payload = self.dependencies['provision'].call_args.args[0]
        self.assertFalse(payload['initial'])
        self.assertIsNone(payload['email'])
        self.assertIsNone(payload['password_hash'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
