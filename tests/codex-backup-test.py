import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest import mock


REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('codex_backup', REPO / 'install/codex-backup.py')
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class CodexBackupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.legacy = self.root / 'legacy-codex'
        self.scratch = self.root / 'scratch-codex'
        self.legacy.mkdir(mode=0o700)
        self.scratch.mkdir(mode=0o700)
        (self.scratch / 'sessions').mkdir()
        (self.scratch / 'sessions' / 'rollout.jsonl').write_bytes(b'{"history":"intact"}\n')
        (self.legacy / 'sessions').symlink_to(self.scratch / 'sessions', target_is_directory=True)
        # Deliberately invalid SQLite bytes must be preserved byte-for-byte.
        self.database = self.scratch / 'state_5.sqlite'
        self.database.write_bytes(b'not a sqlite database\x00\xff')
        (self.legacy / 'state_5.sqlite').symlink_to(self.database)
        (self.scratch / 'state_5.sqlite-wal').write_bytes(b'raw WAL bytes')
        (self.legacy / 'state_5.sqlite-wal').symlink_to(self.scratch / 'state_5.sqlite-wal')
        (self.legacy / 'session_index.jsonl').write_text('{"id":"one"}\n')

    def destination(self, name='backup'):
        return self.root / name

    def test_materializes_symlinked_history_and_raw_sqlite_with_topology(self):
        manifest = module.backup([('legacy', self.legacy)], self.destination())
        tree = self.destination() / 'sources/legacy/tree'
        self.assertEqual((tree / 'sessions/rollout.jsonl').read_bytes(), b'{"history":"intact"}\n')
        self.assertEqual((tree / 'state_5.sqlite').read_bytes(), self.database.read_bytes())
        self.assertEqual((tree / 'state_5.sqlite-wal').read_bytes(), b'raw WAL bytes')
        self.assertFalse((tree / 'sessions').is_symlink())
        topology = json.loads((self.destination() / 'sources/legacy/symlink-topology.json').read_text())
        self.assertEqual({entry['path'] for entry in topology['symlinks']},
                         {'sessions', 'state_5.sqlite', 'state_5.sqlite-wal'})
        self.assertTrue((self.destination() / 'manifest.json').is_file())
        self.assertFalse((self.destination() / 'INCOMPLETE.json').exists())
        self.assertEqual(manifest['status'], 'complete')
        self.assertEqual((tree / 'state_5.sqlite').stat().st_mode & 0o777, 0o600)
        self.assertEqual(tree.stat().st_mode & 0o777, 0o700)

    def test_existing_destination_is_never_overwritten(self):
        destination = self.destination()
        destination.mkdir()
        sentinel = destination / 'keep'
        sentinel.write_text('unchanged')
        with self.assertRaisesRegex(module.BackupError, 'already exists'):
            module.backup([('legacy', self.legacy)], destination)
        self.assertEqual(sentinel.read_text(), 'unchanged')

    def test_source_change_leaves_explicit_incomplete_backup_without_manifest(self):
        destination = self.destination()
        original = module.copy_regular
        changed = False

        def copy_then_change(entry, target):
            nonlocal changed
            result = original(entry, target)
            if not changed:
                changed = True
                (self.legacy / 'session_index.jsonl').write_text('{"id":"changed"}\n')
            return result

        with mock.patch.object(module, 'copy_regular', side_effect=copy_then_change):
            with self.assertRaisesRegex(module.BackupError, 'inventory changed'):
                module.backup([('legacy', self.legacy)], destination)
        self.assertFalse((destination / 'manifest.json').exists())
        incomplete = json.loads((destination / 'INCOMPLETE.json').read_text())
        self.assertEqual(incomplete['status'], 'incomplete')

    def test_special_paths_are_recorded_and_never_materialized(self):
        fifo = self.legacy / 'live.fifo'
        os.mkfifo(fifo)
        sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(sock.close)
        sock.bind(str(self.legacy / 'live.sock'))
        module.backup([('legacy', self.legacy)], self.destination())
        inventory = json.loads((self.destination() / 'manifest.json').read_text())['sources']['legacy']['inventory']
        self.assertEqual({item['path']: item['kind'] for item in inventory['special']},
                         {'live.fifo': 'fifo', 'live.sock': 'socket'})
        tree = self.destination() / 'sources/legacy/tree'
        self.assertFalse((tree / 'live.fifo').exists())
        self.assertFalse((tree / 'live.sock').exists())

    def test_symlink_cycle_fails_closed(self):
        (self.scratch / 'loop').symlink_to(self.scratch, target_is_directory=True)
        (self.legacy / 'loop').symlink_to(self.scratch / 'loop', target_is_directory=True)
        destination = self.destination()
        with self.assertRaisesRegex(module.BackupError, 'cycle'):
            module.backup([('legacy', self.legacy)], destination)
        self.assertFalse((destination / 'manifest.json').exists())

    def test_dangling_ephemeral_symlink_is_explicitly_recorded(self):
        (self.legacy / 'app-server.sock').symlink_to(self.legacy / 'gone.sock')
        module.backup([('legacy', self.legacy)], self.destination())
        topology = json.loads((self.destination() / 'sources/legacy/symlink-topology.json').read_text())
        dangling = [entry for entry in topology['symlinks'] if entry['path'] == 'app-server.sock']
        self.assertEqual(dangling[0]['status'], 'dangling')
        self.assertIsNone(dangling[0]['resolved'])
        self.assertEqual(topology['dangling_symlink_count'], 1)

    def test_direct_calls_reject_dot_labels_and_relative_roots(self):
        with self.assertRaisesRegex(module.BackupError, 'invalid source label'):
            module.backup([('.', self.legacy)], self.destination('dot-label'))
        with self.assertRaisesRegex(module.BackupError, 'absolute'):
            module.backup([('relative', Path('legacy-codex'))], self.destination('relative-root'))

    def test_inventory_preserves_restore_metadata(self):
        target = self.legacy / 'session_index.jsonl'
        os.chmod(target, 0o640)
        module.backup([('legacy', self.legacy)], self.destination())
        inventory = json.loads((self.destination() / 'manifest.json').read_text())['sources']['legacy']['inventory']
        entry = next(item for item in inventory['files'] if item['path'] == 'session_index.jsonl')
        metadata = entry['fingerprint']
        self.assertEqual(metadata['mode'], 0o640)
        self.assertEqual(metadata['uid'], os.getuid())
        self.assertEqual(metadata['gid'], os.getgid())
        self.assertIsInstance(metadata['ctime_ns'], int)
        copied = self.destination() / 'sources/legacy/tree/session_index.jsonl'
        self.assertEqual(copied.stat().st_mode & 0o777, 0o600)

    def test_destination_inside_dereferenced_directory_is_rejected_before_creation(self):
        external = self.legacy / 'all-scratch'
        external.symlink_to(self.scratch, target_is_directory=True)
        destination = self.scratch / 'backups' / 'must-not-create'
        (self.scratch / 'backups').mkdir()
        with self.assertRaisesRegex(module.BackupError, 'dereferenced source directory'):
            module.backup([('legacy', self.legacy)], destination)
        self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()
