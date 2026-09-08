"""Behavior tests for incremental statusline transcript accounting."""
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "home/dot_claude/statusline_stats.py"
SPEC = importlib.util.spec_from_file_location("statusline_stats", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def assistant(tokens=10, timestamp="2026-09-07T10:00:00.123Z"):
    return {"type": "assistant", "timestamp": timestamp, "message": {
        "usage": {"input_tokens": tokens, "output_tokens": 5,
                  "cache_read_input_tokens": 20, "cache_creation_input_tokens": 9,
                  "cache_creation": {"ephemeral_5m_input_tokens": 6, "ephemeral_1h_input_tokens": 3}},
        "content": [{"type": "text", "text": "hello"}, {"type": "tool_use"}]}}


class StatuslineStatsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.transcript = self.root / "session.jsonl"
        self.cache = self.root / "cache"

    def write(self, records):
        self.transcript.write_text("".join(json.dumps(row) + "\n" for row in records))

    def stats(self):
        return MODULE.reduce(self.transcript, self.cache)

    def test_totals_last_context_tools_and_timestamp(self):
        self.write([{"type": "user"}, assistant(), assistant(15, "2026-09-07T10:01:02Z")])
        self.assertEqual(self.stats(), [2, 49, 25, 10, 40, 12, 6, 62, 2, 15, 5, 20, 6, 3])
        cache = MODULE.cache_path(self.transcript, self.cache)
        before = cache.stat().st_mtime_ns
        self.assertEqual(self.stats(), [2, 49, 25, 10, 40, 12, 6, 62, 2, 15, 5, 20, 6, 3])
        self.assertEqual(cache.stat().st_mtime_ns, before, "unchanged refresh must not rewrite cache")

    def test_append_counts_once(self):
        self.write([assistant()])
        self.stats()
        with self.transcript.open("a") as out:
            out.write(json.dumps(assistant(100)) + "\n")
        self.assertEqual(self.stats()[0:4], [2, 134, 110, 10])
        self.assertEqual(self.stats()[0:4], [2, 134, 110, 10])

    def test_partial_and_complete_unterminated_record(self):
        self.write([assistant()])
        self.stats()
        row = json.dumps(assistant(100))
        with self.transcript.open("a") as out:
            out.write(row[:30])
        self.assertEqual(self.stats()[0], 1)
        with self.transcript.open("a") as out:
            out.write(row[30:])
        self.assertEqual(self.stats()[0:4], [2, 134, 110, 10])
        self.assertEqual(self.stats()[0], 2)
        with self.transcript.open("a") as out:
            out.write("\n" + json.dumps(assistant()) + "\n")
        self.assertEqual(self.stats()[0], 3)

    def test_replacement_truncation_and_regrowth(self):
        self.write([assistant()] * 4)
        self.stats()
        self.write([assistant(99)])
        self.assertEqual(self.stats()[0:4], [1, 133, 99, 5])
        replacement = self.root / "new.jsonl"
        replacement.write_text(json.dumps(assistant(11)) + "\n")
        os.replace(replacement, self.transcript)
        self.assertEqual(self.stats()[2], 11)
        self.write([assistant(99)] * 5)
        self.assertEqual(self.stats()[0:4], [5, 133, 495, 25])

    def test_same_size_rewrite_and_corrupt_cache(self):
        self.write([assistant(10)])
        self.stats()
        self.write([assistant(99)])
        self.assertEqual(self.stats()[2], 99)
        cache = MODULE.cache_path(self.transcript, self.cache)
        for invalid in ("{broken", "{}", '{"version":1,"offset":"oops","stats":{}}'):
            cache.write_text(invalid)
            self.assertEqual(self.stats()[2], 99)

    def test_unwritable_cache_does_not_hide_stats(self):
        self.write([assistant()])
        self.cache.write_text("a file cannot be a cache directory")
        self.assertEqual(self.stats()[0], 1)

    def test_empty_and_null_fields(self):
        self.write([])
        self.assertEqual(self.stats(), [0] * 14)
        self.write([{"type": "assistant", "timestamp": "invalid", "message": None}])
        self.assertEqual(self.stats(), [1] + [0] * 13)

    def test_concurrent_refresh_and_subsequent_append(self):
        self.write([assistant()] * 100)
        def run(_):
            return subprocess.run([sys.executable, str(HELPER), str(self.transcript)],
                                  env={**os.environ, "STATUSLINE_STATS_CACHE_DIR": str(self.cache)},
                                  text=True, capture_output=True, check=True).stdout
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(executor.map(run, range(12)))
        self.assertEqual(len(set(results)), 1)
        with self.transcript.open("a") as out:
            out.write(json.dumps(assistant()) + "\n")
        self.assertEqual(self.stats()[0], 101)
        self.assertEqual(list(self.cache.glob("tmp*")), [])

    def test_invalid_complete_json_does_not_publish_incorrect_cache(self):
        self.write([assistant()])
        self.stats()
        with self.transcript.open("a") as out:
            out.write("{broken}\n")
        with self.assertRaises(ValueError):
            self.stats()
        self.write([assistant()] * 2)
        self.assertEqual(self.stats()[0], 2)

    def test_shell_render_uses_cache_and_preserves_segments(self):
        self.write([assistant(), assistant(15, "2026-09-07T10:01:02Z")])
        payload = json.dumps({"workspace": {"current_dir": str(self.root)},
                              "model": {"id": "claude-opus-4-8", "effort": {"level": "max"}},
                              "context_window": {"used_percentage": 12.5},
                              "transcript_path": str(self.transcript)})
        result = subprocess.run(["bash", str(ROOT / "home/dot_claude/executable_statusline.sh")],
                                input=payload, text=True, capture_output=True,
                                env={**os.environ, "STATUSLINE_STATS_CACHE_DIR": str(self.cache)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2t/2c (1m)", result.stdout)
        self.assertIn("12.5%", result.stdout)
        self.assertIn("Opus 4.8", result.stdout)
        self.assertTrue(MODULE.cache_path(self.transcript, self.cache).exists())


    def test_cached_and_jq_fallback_render_identically(self):
        self.write([assistant(), assistant(15, "2026-09-07T10:01:02Z")])
        source = ROOT / "home/dot_claude/executable_statusline.sh"
        fallback = self.root / "statusline.sh"
        fallback.write_text(source.read_text())  # No sibling helper: jq compatibility path.
        for model in ({}, {"id": "claude-opus-4-8", "effort": {"level": "max"}}):
            payload = json.dumps({"workspace": {"current_dir": str(self.root)},
                                  "model": model, "context_window": {"used_percentage": 0},
                                  "transcript_path": str(self.transcript),
                                  "is_subagent": True, "cost": {"total_cost_usd": 1.25}})
            outputs = []
            for script in (source, fallback):
                result = subprocess.run(["bash", str(script)], input=payload,
                                        text=True, capture_output=True, check=True,
                                        env={**os.environ, "STATUSLINE_STATS_CACHE_DIR": str(self.cache)})
                self.assertEqual(result.stderr, "")
                outputs.append(result.stdout)
            self.assertEqual(*outputs)


if __name__ == "__main__":
    unittest.main()
