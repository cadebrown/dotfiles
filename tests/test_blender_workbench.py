"""Format and process-boundary checks for the Blender batch capability."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'home/dot_claude/skills/blender-workbench/scripts/blender_workbench.py'
spec = importlib.util.spec_from_file_location('blender_workbench', SCRIPT)
workbench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workbench)


class BlenderWorkbenchTests(unittest.TestCase):
    def test_inspects_exported_glb_metadata(self):
        doc = {'asset': {'version': '2.0'}, 'meshes': [{}], 'materials': [{}], 'animations': [{}]}
        chunk = json.dumps(doc).encode()
        chunk += b' ' * (-len(chunk) % 4)
        data = struct.pack('<4sIIII', b'glTF', 2, 20 + len(chunk), len(chunk), 0x4E4F534A) + chunk
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'asset.glb'
            path.write_bytes(data)
            report = workbench.glb_summary(path)
            self.assertEqual((report['meshes'], report['materials'], report['animations']), (1, 1, 1))
            path.write_bytes(data[:-2])
            with self.assertRaises(ValueError):
                workbench.glb_summary(path)

    def test_rejects_header_only_glb(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'empty.glb'
            path.write_bytes(b'glTF')
            with self.assertRaises(ValueError):
                workbench.glb_summary(path)

    def test_demo_preserves_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / 'user.blend'
            sentinel.write_bytes(b'existing user scene')
            result = subprocess.run([sys.executable, str(SCRIPT), '--blender', sys.executable,
                                     'demo', directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(sentinel.read_bytes(), b'existing user scene')
            self.assertEqual(list(Path(directory).iterdir()), [sentinel])

    def test_blender_failure_is_reported_and_log_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'scene.py'
            script.write_text('raise RuntimeError("intentional")\n')
            logs = root / 'logs'
            result = subprocess.run([sys.executable, str(SCRIPT), '--blender', sys.executable,
                                     '--log-dir', str(logs), 'run', str(script)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Blender failed', result.stderr)
            self.assertTrue((logs / '01-run.log').is_file())


if __name__ == '__main__':
    unittest.main()
