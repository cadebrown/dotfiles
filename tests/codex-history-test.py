import importlib.util
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('codex_history', REPO / 'install/codex-history.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'legacy'
        self.target = self.root / 'local'
        self.source.mkdir(mode=0o700)
        self.target.mkdir(mode=0o700)
        self.scratch = self.root / 'shared-sessions'
        self.scratch.mkdir()
        (self.source / 'sessions').symlink_to(self.scratch, target_is_directory=True)
        (self.scratch / 'rollout.jsonl').write_text('{"type":"session_meta"}\n')
        (self.source / 'session_index.jsonl').write_text('{"id":"test"}\n')
        (self.source / 'history.jsonl').write_text('{"prompt":"preserve me"}\n')
        (self.scratch / 'attachments' / 'nested').mkdir(parents=True)
        (self.scratch / 'attachments' / 'nested' / 'input.bin').write_bytes(b'attachment bytes')
        (self.scratch / 'generated_images').mkdir()
        (self.scratch / 'generated_images' / 'image.png').write_bytes(b'not a decoded image')
        (self.scratch / 'visualizations').mkdir()
        (self.scratch / 'visualizations' / 'plot.json').write_text('{"plot":true}\n')
        for name in ('attachments', 'generated_images', 'visualizations'):
            (self.source / name).symlink_to(self.scratch / name, target_is_directory=True)
        (self.source / 'state_5.sqlite').write_bytes(b'not imported')

    def test_copy_preserves_source_and_omits_databases(self):
        result = module.import_history(self.source, self.target)
        self.assertEqual(result['copied'], 6)
        self.assertEqual((self.target / 'sessions/rollout.jsonl').read_bytes(),
                         (self.scratch / 'rollout.jsonl').read_bytes())
        self.assertEqual((self.target / 'history.jsonl').read_text(), '{"prompt":"preserve me"}\n')
        self.assertEqual((self.target / 'attachments/nested/input.bin').read_bytes(), b'attachment bytes')
        self.assertEqual((self.target / 'generated_images/image.png').read_bytes(), b'not a decoded image')
        self.assertEqual((self.target / 'visualizations/plot.json').read_text(), '{"plot":true}\n')
        self.assertFalse((self.target / 'state_5.sqlite').exists())
        self.assertTrue((self.source / 'sessions').is_symlink())
        self.assertEqual((self.target / 'sessions/rollout.jsonl').stat().st_mode & 0o777, 0o600)

    def test_rerun_never_overwrites_resumed_local_history(self):
        module.import_history(self.source, self.target)
        (self.target / 'sessions/rollout.jsonl').write_text('local continuation\n')
        (self.target / 'attachments/nested/input.bin').write_bytes(b'local artifact')
        result = module.import_history(self.source, self.target)
        self.assertEqual(result['copied'], 0)
        self.assertEqual(result['existing'], 6)
        self.assertEqual((self.target / 'sessions/rollout.jsonl').read_text(), 'local continuation\n')
        self.assertEqual((self.target / 'attachments/nested/input.bin').read_bytes(), b'local artifact')

    def test_rejects_destination_symlink_without_writing_through_it(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.target / 'sessions').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            module.import_history(self.source, self.target)
        self.assertEqual(list(outside.iterdir()), [])

    def test_rejects_identical_or_nested_trees(self):
        with self.assertRaisesRegex(ValueError, 'separate'):
            module.import_history(self.source, self.source)

    def test_rejects_interior_directory_symlink_before_copying_anything(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.scratch / 'attachments' / 'redirect').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'interior symlink'):
            module.import_history(self.source, self.target)
        self.assertEqual(list(self.target.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
