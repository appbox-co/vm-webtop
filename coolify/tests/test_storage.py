import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('coolify_storage', Path(__file__).resolve().parents[1] / 'storage.py')
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageSafetyTest(unittest.TestCase):
    def setUp(self):
        self.state = {'version': 1, 'cache_ready': False,
                      'partition_uuid': '9317523f-38ed-4105-a869-a92521b2de7d',
                      'filesystem_uuid': '476e2825-6cba-4664-91ee-df998f2bd1d7'}
        self.table = {'label': 'gpt', 'unit': 'sectors', 'sectorsize': 512,
                      'partitions': [{'node': '/dev/vda' + str(n), 'start': start // 512,
                                      'size': size // 512} for n, (start, size) in storage.BASE.items()]}
        self.data = {'node': '/dev/vda2', 'start': 67108864, 'size': 10000000,
                     'name': storage.LABEL, 'type': storage.LINUX_TYPE,
                     'uuid': self.state['partition_uuid']}

    def test_pristine_layout_has_unused_partition_two(self):
        self.assertIsNone(storage.validate_layout(self.table))

    def test_foreign_partition_is_refused_even_if_label_matches(self):
        self.table['partitions'].append(self.data)
        with self.assertRaises(RuntimeError):
            storage.validate_layout(self.table)
        wrong = dict(self.state, partition_uuid='bbbbbbbb-38ed-4105-a869-a92521b2de7d')
        with self.assertRaises(RuntimeError):
            storage.validate_layout(self.table, wrong)
        self.assertEqual(storage.validate_layout(self.table, self.state), self.data)

    def test_changed_os_and_extra_partition_are_refused(self):
        changed = copy.deepcopy(self.table)
        changed['partitions'][0]['size'] += 1
        with self.assertRaises(RuntimeError):
            storage.validate_layout(changed)
        self.table['partitions'].append(dict(self.data, node='/dev/vda3'))
        with self.assertRaises(RuntimeError):
            storage.validate_layout(self.table)

    def test_initialized_missing_disk_never_becomes_a_format_candidate(self):
        self.state['cache_ready'] = True
        with self.assertRaises(RuntimeError):
            storage.validate_layout(self.table, self.state)
        with self.assertRaises(RuntimeError):
            storage.validate_filesystem({}, self.state)

    def test_filesystem_identity_is_required_for_reuse(self):
        expected = {'TYPE': 'xfs', 'LABEL': storage.LABEL, 'UUID': self.state['filesystem_uuid']}
        storage.validate_filesystem(expected, self.state)
        for key, value in [('TYPE', 'ext4'), ('LABEL', 'other'), ('UUID', self.state['partition_uuid'])]:
            with self.assertRaises(RuntimeError):
                storage.validate_filesystem(dict(expected, **{key: value}), self.state)

    def test_fstab_preserves_user_mounts_and_updates_only_owned_block(self):
        original = 'LABEL=cloudimg-rootfs / ext4 defaults 0 1\n/dev/vdb1 /projects xfs defaults 0 0\n'
        result = storage.fstab_contents(original, self.state['filesystem_uuid'])
        self.assertTrue(result.startswith(original))
        self.assertEqual(storage.fstab_contents(result, self.state['filesystem_uuid']), result)
        with self.assertRaises(RuntimeError):
            storage.fstab_contents(original + '/dev/vdb2 /data xfs defaults 0 0\n', self.state['filesystem_uuid'])


if __name__ == '__main__':
    unittest.main()
