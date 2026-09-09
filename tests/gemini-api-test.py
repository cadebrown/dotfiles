"""Offline behavior tests for the locked Gemini API probe."""

import asyncio
import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("gemini_api", ROOT / "install/gemini-api.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


def event(parts=(), complete=False, transcript=None):
    return SimpleNamespace(server_content=SimpleNamespace(
        model_turn=SimpleNamespace(parts=parts), turn_complete=complete,
        output_transcription=SimpleNamespace(text=transcript) if transcript else None,
    ))


def audio(data, mime_type="audio/pcm;rate=24000"):
    return SimpleNamespace(inline_data=SimpleNamespace(data=data, mime_type=mime_type))


class FakeSession:
    def __init__(self, events):
        self.events = events
        self.sent = []

    async def send_realtime_input(self, **kwargs):
        self.sent.append(kwargs)

    async def receive(self):
        for item in self.events:
            yield item


class ProbeTests(unittest.IsolatedAsyncioTestCase):
    def test_developer_key_precedence_and_missing_key_prevents_sdk_construction(self):
        self.assertEqual(probe.developer_api_key({"GOOGLE_API_KEY": "preferred", "GEMINI_API_KEY": "fallback"}), "preferred")
        with patch.object(probe.genai, "Client") as client:
            with self.assertRaises(probe.ProbeError):
                probe.make_client("developer", environment={})
            client.assert_not_called()

    def test_explicit_backends_ignore_ambient_vertex_mode(self):
        with patch.object(probe.genai, "Client", return_value="developer") as client:
            self.assertEqual(probe.make_client("developer", environment={"GOOGLE_API_KEY": "secret", "GOOGLE_GENAI_USE_VERTEXAI": "true"}), "developer")
            self.assertFalse(client.call_args.kwargs["vertexai"])
            self.assertEqual(client.call_args.kwargs["api_key"], "secret")
        with patch.object(probe.genai, "Client", return_value="vertex") as client:
            self.assertEqual(probe.make_client("vertex", project="p", location="us-central1", environment={"GOOGLE_API_KEY": "secret"}), "vertex")
            self.assertTrue(client.call_args.kwargs["vertexai"])
            self.assertEqual(client.call_args.kwargs["project"], "p")
            self.assertEqual(client.call_args.kwargs["location"], "us-central1")
            self.assertNotIn("api_key", client.call_args.kwargs)
        with self.assertRaises(probe.ProbeError):
            probe.make_client("vertex", project="p", environment={})

    async def test_collects_every_inline_audio_part_and_transcript(self):
        session = FakeSession([event((audio(b"ab"), audio(b"cd")), transcript="one"), event((audio(b"ef"),), complete=True, transcript=" two")])
        audio_bytes, transcript = await probe.receive_live_turn(session, 1)
        self.assertEqual(audio_bytes, b"abcdef")
        self.assertEqual(transcript, "one two")

    async def test_rejects_missing_audio_and_incomplete_turn(self):
        with self.assertRaisesRegex(probe.ProbeError, "without audio"):
            await probe.receive_live_turn(FakeSession([event(complete=True)]), 1)
        with self.assertRaisesRegex(probe.ProbeError, "before completing"):
            await probe.receive_live_turn(FakeSession([event((audio(b"xx"),))]), 1)

    async def test_skips_non_pcm_and_rejects_odd_pcm(self):
        audio_bytes, _ = await probe.receive_live_turn(
            FakeSession([event((audio(b"jpeg", "image/jpeg"), audio(b"ok")), complete=True)]), 1)
        self.assertEqual(audio_bytes, b"ok")
        with self.assertRaisesRegex(probe.ProbeError, "16-bit PCM"):
            await probe.receive_live_turn(FakeSession([event((audio(b"x"),), complete=True)]), 1)

    async def test_timeout_is_bounded(self):
        class HangingSession(FakeSession):
            async def receive(self):
                await asyncio.sleep(0.05)
                if False:
                    yield None
        with self.assertRaisesRegex(probe.ProbeError, "timed out"):
            await probe.receive_live_turn(HangingSession([]), 0.01)

    def test_refuses_existing_output_and_error_summary_redacts_transport_details(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "audio.wav"
            target.write_bytes(b"existing")
            with self.assertRaisesRegex(probe.ProbeError, "refusing to overwrite"):
                probe.write_wav(target, b"new")
        error = RuntimeError("wss://api.example.test/?key=private-key")
        summary = probe.error_summary(error)
        self.assertNotIn("private-key", summary)
        self.assertNotIn("api.example", summary)
        self.assertIn("RuntimeError", summary)

    def test_model_listing_is_bounded_and_reports_actions(self):
        models = [SimpleNamespace(name=f"models/fake-{index}", supported_actions=["generateContent"])
                  for index in range(3)]
        result = probe.run_models(SimpleNamespace(backend="developer", limit=2),
                                  SimpleNamespace(models=SimpleNamespace(list=lambda: models)))
        self.assertEqual(result["models"], [
            {"name": "models/fake-0", "supported_actions": ["generateContent"]},
            {"name": "models/fake-1", "supported_actions": ["generateContent"]},
        ])

    def test_generation_limits_output_and_rejects_empty_text(self):
        calls = []

        def generate_content(**kwargs):
            calls.append(kwargs)
            return SimpleNamespace(text="short response")

        client = SimpleNamespace(models=SimpleNamespace(
            generate_content=generate_content))
        result = probe.run_generate(SimpleNamespace(backend="developer", model="fake", prompt="test"), client)
        self.assertEqual(result["text"], "short response")
        config = calls[0]["config"]
        self.assertEqual(config.max_output_tokens, 128)
        self.assertTrue(config.automatic_function_calling.disable)
        with self.assertRaisesRegex(probe.ProbeError, "empty generation"):
            probe.run_generate(SimpleNamespace(backend="developer", model="fake", prompt="test"),
                               SimpleNamespace(models=SimpleNamespace(generate_content=lambda **kwargs: SimpleNamespace(text=""))))


if __name__ == "__main__":
    unittest.main()
