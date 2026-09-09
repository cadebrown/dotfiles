# /// script
# requires-python = ">=3.11"
# dependencies = ["google-genai==2.22.0"]
# ///
"""Small, reproducible Gemini API and Live API probe.

Developer API is the default.  Set GOOGLE_API_KEY (preferred) or GEMINI_API_KEY
for it; Vertex AI is an explicit opt-in and requires --project and --location.
See https://ai.google.dev/gemini-api/docs/live-api/get-started-sdk .
"""

import argparse
import asyncio
import base64
import json
import os
import sys
import wave
from pathlib import Path

from google import genai
from google.genai import types


DOCS_URL = "https://ai.google.dev/gemini-api/docs/live-api/get-started-sdk"
DEFAULT_GENERATE_MODEL = "gemini-3.8-flash"
DEFAULT_LIVE_MODEL = "gemini-3.1-flash-live-preview"
DEFAULT_PROMPT = "Reply with exactly: Gemini API probe ready."
DEFAULT_LIVE_PROMPT = "Say exactly: Gemini Live API probe ready."
DEFAULT_TIMEOUT = 30
MAX_AUDIO_BYTES = 10 * 1024 * 1024
HTTP_TIMEOUT_MS = 30_000


class ProbeError(RuntimeError):
    """A safe, user-facing probe error."""


def developer_api_key(environment=os.environ):
    """Return the documented Developer API key precedence without logging it."""
    return environment.get("GOOGLE_API_KEY") or environment.get("GEMINI_API_KEY")


def make_client(backend, project=None, location=None, environment=os.environ):
    """Create an SDK client with an explicit backend, ignoring ambient SDK mode."""
    if backend == "developer":
        api_key = developer_api_key(environment)
        if not api_key:
            raise ProbeError("Developer API requires GOOGLE_API_KEY or GEMINI_API_KEY; see " + DOCS_URL)
        return genai.Client(
            vertexai=False, api_key=api_key, http_options=types.HttpOptions(timeout=HTTP_TIMEOUT_MS),
        )
    if not project or not location:
        raise ProbeError("Vertex AI requires both --project and --location; see " + DOCS_URL)
    # The SDK gives explicitly supplied project/location precedence over API
    # keys inherited from the environment, so omit api_key deliberately here.
    return genai.Client(
        vertexai=True, project=project, location=location,
        http_options=types.HttpOptions(timeout=HTTP_TIMEOUT_MS),
    )


def error_summary(error):
    """Preserve useful classification while never exposing SDK request details."""
    status = getattr(error, "status_code", None) or getattr(error, "code", None)
    suffix = f" status={status}" if isinstance(status, int) else ""
    return f"Gemini request failed ({type(error).__name__}{suffix}); see {DOCS_URL}"


def inline_bytes(part):
    inline_data = getattr(part, "inline_data", None)
    data = getattr(inline_data, "data", None) if inline_data else None
    mime_type = getattr(inline_data, "mime_type", "") if inline_data else ""
    if not is_pcm_24khz(mime_type) or data is None:
        return b""
    if isinstance(data, bytes):
        return data
    if isinstance(data, str):
        try:
            return base64.b64decode(data, validate=True)
        except ValueError as error:
            raise ProbeError("Gemini returned invalid inline audio data; see " + DOCS_URL) from error
    raise ProbeError("Gemini returned unsupported inline audio data; see " + DOCS_URL)


def is_pcm_24khz(mime_type):
    """Only label the documented Live output encoding as 24 kHz PCM."""
    fields = [field.strip().lower() for field in (mime_type or "").split(";")]
    if not fields or fields[0] != "audio/pcm":
        return False
    parameters = {key.strip(): value.strip() for key, _, value in
                  (field.partition("=") for field in fields[1:]) if key and value}
    return parameters.get("rate") == "24000"


async def receive_live_turn(session, timeout):
    """Collect every audio part until the server declares the turn complete."""
    audio = bytearray()
    transcript = []
    completed = False
    try:
        async with asyncio.timeout(timeout):
            async for event in session.receive():
                content = getattr(event, "server_content", None)
                if content is None:
                    continue
                output = getattr(content, "output_transcription", None)
                text = getattr(output, "text", None) if output else None
                if text:
                    transcript.append(text)
                turn = getattr(content, "model_turn", None)
                for part in getattr(turn, "parts", ()) if turn else ():
                    chunk = inline_bytes(part)
                    if len(chunk) % 2:
                        raise ProbeError("Gemini returned odd-length 16-bit PCM audio; see " + DOCS_URL)
                    if len(audio) + len(chunk) > MAX_AUDIO_BYTES:
                        raise ProbeError("Gemini audio exceeded the probe size limit")
                    audio.extend(chunk)
                if getattr(content, "turn_complete", False):
                    completed = True
                    break
    except TimeoutError as error:
        raise ProbeError(f"Gemini Live turn timed out after {timeout} seconds; see {DOCS_URL}") from error
    if not completed:
        raise ProbeError("Gemini Live ended before completing a turn; see " + DOCS_URL)
    if not audio:
        raise ProbeError("Gemini Live completed without audio; see " + DOCS_URL)
    return bytes(audio), "".join(transcript)


def write_wav(output, audio):
    path = Path(output)
    try:
        # Exclusive creation closes the check/create race and never overwrites.
        with path.open("xb") as file, wave.open(file, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(24000)
            wav.writeframes(audio)
    except FileExistsError as error:
        raise ProbeError(f"refusing to overwrite existing output: {path}") from error
    except OSError as error:
        raise ProbeError("cannot write WAV output") from error


def model_metadata(model):
    actions = getattr(model, "supported_actions", None) or ()
    return {"name": getattr(model, "name", ""), "supported_actions": list(actions)}


def run_models(args, client):
    models = []
    for model in client.models.list():
        name = getattr(model, "name", "")
        if name:
            models.append(model_metadata(model))
        if len(models) >= args.limit:
            break
    return {"command": "models", "backend": args.backend, "models": models}


def run_generate(args, client):
    response = client.models.generate_content(
        model=args.model, contents=args.prompt,
        config=types.GenerateContentConfig(
            max_output_tokens=128,
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
        ),
    )
    text = getattr(response, "text", "") or ""
    if not text.strip():
        raise ProbeError("Gemini returned an empty generation; see " + DOCS_URL)
    return {
        "command": "generate", "backend": args.backend, "model": args.model,
        "text": text,
    }


async def run_live(args, client):
    output = Path(args.output)
    if output.exists():
        raise ProbeError(f"refusing to overwrite existing output: {output}")
    config = types.LiveConnectConfig(
        response_modalities=[types.Modality.AUDIO], output_audio_transcription={},
    )
    try:
        # This scope includes WebSocket connect, send, receive, and close.
        async with asyncio.timeout(args.timeout):
            async with client.aio.live.connect(model=args.model, config=config) as session:
                await session.send_realtime_input(text=args.prompt)
                audio, transcript = await receive_live_turn(session, args.timeout)
    except TimeoutError as error:
        raise ProbeError(f"Gemini Live operation timed out after {args.timeout} seconds; see {DOCS_URL}") from error
    write_wav(output, audio)
    return {
        "command": "live", "backend": args.backend, "model": args.model,
        "output": str(output), "audio_bytes": len(audio), "transcript": transcript,
    }


def parser():
    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument("--check-runtime", action="store_true", help="check the locked SDK without credentials or network")
    command.add_argument("--backend", choices=("developer", "vertex"), default="developer")
    command.add_argument("--project")
    command.add_argument("--location")
    subcommands = command.add_subparsers(dest="command")
    models = subcommands.add_parser("models", help="list a bounded set of model names and supported actions")
    backend_options(models)
    models.add_argument("--limit", type=int, default=20)
    generate = subcommands.add_parser("generate", help="run a small text generation probe")
    backend_options(generate)
    generate.add_argument("--model", default=DEFAULT_GENERATE_MODEL)
    generate.add_argument("--prompt", default=DEFAULT_PROMPT)
    live = subcommands.add_parser("live", help="write a Live API audio response as a 24 kHz WAV")
    backend_options(live)
    live.add_argument("--model", default=DEFAULT_LIVE_MODEL)
    live.add_argument("--prompt", default=DEFAULT_LIVE_PROMPT)
    live.add_argument("--output", required=True)
    live.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    return command


def backend_options(command):
    """Allow backend arguments after a subcommand, as shown in the handbook."""
    command.add_argument("--backend", choices=("developer", "vertex"), default=argparse.SUPPRESS)
    command.add_argument("--project", default=argparse.SUPPRESS)
    command.add_argument("--location", default=argparse.SUPPRESS)


def main(argv=None):
    args = parser().parse_args(argv)
    if args.check_runtime:
        print(json.dumps({"runtime": "ready", "google_genai": getattr(genai, "__version__", "unknown")}))
        return 0
    if not args.command:
        parser().error("choose models, generate, or live (or use --check-runtime)")
    if not 1 <= getattr(args, "limit", 1) <= 100:
        parser().error("--limit must be between 1 and 100")
    if getattr(args, "timeout", 1) < 1:
        parser().error("--timeout must be positive")
    try:
        client = make_client(args.backend, args.project, args.location)
        result = asyncio.run(run_live(args, client)) if args.command == "live" else (
            run_models(args, client) if args.command == "models" else run_generate(args, client)
        )
        print(json.dumps(result, sort_keys=True))
        return 0
    except ProbeError as error:
        print(f"df-gemini-api: {error}", file=sys.stderr)
    except Exception as error:
        print(f"df-gemini-api: {error_summary(error)}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
