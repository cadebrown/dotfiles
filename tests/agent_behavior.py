#!/usr/bin/env python3
"""Prepare and run small, paired Codex instruction experiments. No aggregate score."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


FIXTURES = Path(__file__).parent / "fixtures" / "agent-behavior"
CASES = ("coding", "research", "browser", "resume", "execution", "delegation")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def inventory(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob("*"))
            if p.is_file() and not any(x in p.parts for x in ("node_modules", "__pycache__", ".git"))}


def environment(root):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("CODEX_", "OPENAI_", "XDG_"))}
    env.update(HOME=str(root / "home"), CODEX_HOME=str(root / "home" / ".codex"),
               XDG_CONFIG_HOME=str(root / "home" / ".config"),
               XDG_DATA_HOME=str(root / "home" / ".local" / "share"),
               XDG_CACHE_HOME=str(root / "home" / ".cache"), TMPDIR=str(root / "tmp"),
               UV_CACHE_DIR=str(root / "tmp" / "uv-cache"))
    return env


def reject_ancestor_instructions(workspace):
    for parent in workspace.parents:
        for name in ("AGENTS.md", "AGENTS.override.md", ".codex/config.toml"):
            if (parent / name).exists():
                raise ValueError(f"Isolation root has an instruction/config ancestor: {parent / name}")


def prepare(args):
    agent_dir = getattr(args, "agent_dir", None)
    agent_files = sorted(agent_dir.glob("*.toml")) if agent_dir else []
    if agent_dir and not agent_files:
        raise ValueError(f"No custom agent TOML files found in {agent_dir}")
    output = args.output.resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    if (output / "experiment.json").exists():
        raise ValueError("An experiment already exists here; choose a new output directory")
    if agent_files:
        (output / "agents").mkdir()
        for source in agent_files:
            target = output / "agents" / source.name
            with open(target, "wb", opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
                stream.write(source.read_bytes())
            target.chmod(0o600)
    for case in args.cases:
        shutil.copytree(FIXTURES / case, output / "fixtures" / case)
    root = Path(tempfile.mkdtemp(prefix="codex-instruction-eval-")).resolve()
    manifest = {"model": args.model, "effort": args.effort, "sandbox": args.sandbox, "runtime_root": str(root),
                "codex_version": subprocess.check_output([args.codex, "--version"], text=True).strip(),
                "codex": str(Path(shutil.which(args.codex) or args.codex).resolve()),
                "cases": args.cases, "variants": {}, "runs": {}}
    for variant in ("baseline", "candidate"):
        source = getattr(args, variant).resolve()
        instruction = output / f"{variant}-AGENTS.md"
        if source != instruction:
            shutil.copyfile(source, instruction)
        manifest["variants"][variant] = {"path": str(instruction), "sha256": digest(instruction)}
        for case in args.cases:
            fixture = output / "fixtures" / case
            run_root = root / variant / case
            workspace = run_root / "workspace"
            reject_ancestor_instructions(workspace)
            shutil.copytree(fixture / "input", workspace)
            home = run_root / "home" / ".codex"
            home.mkdir(parents=True)
            (run_root / "tmp").mkdir()
            shutil.copyfile(instruction, home / "AGENTS.md")
            if agent_files:
                shutil.copytree(output / "agents", home / "agents")
            for skill in args.skill:
                shutil.copytree(skill, home / "skills" / skill.name)
            config = (f'model = {json.dumps(args.model)}\n'
                      f'model_reasoning_effort = {json.dumps(args.effort)}\n'
                      f'approval_policy = "never"\nsandbox_mode = {json.dumps(args.sandbox)}\n'
                      'web_search = "disabled"\nproject_doc_max_bytes = 65536\n'
                      '[sandbox_workspace_write]\nnetwork_access = true\n')
            if agent_files:
                config += ('[features]\nmulti_agent_v2 = true\n'
                           '[agents]\nmax_concurrent_threads_per_session = 2\n')
            (home / "config.toml").write_text(config)
            artifacts = output / variant / case
            artifacts.mkdir(parents=True)
            if args.browser_modules and case == "browser":
                (workspace / "node_modules").symlink_to(args.browser_modules.resolve(), target_is_directory=True)
            task = (fixture / "task.txt").read_text()
            prompts = [task]
            if (fixture / "resume.txt").exists():
                prompts.append((fixture / "resume.txt").read_text())
            command = [manifest["codex"], "-C", str(workspace), "debug", "prompt-input", task]
            prompt = subprocess.run(command, cwd=workspace, env=environment(run_root),
                                    text=True, capture_output=True)
            (artifacts / "prompt-input.json").write_text(prompt.stdout)
            (artifacts / "prompt-input.stderr").write_text(prompt.stderr)
            if prompt.returncode:
                raise RuntimeError(f"Prompt inspection failed: {prompt.stderr}")
            text_parts = [item.get("text", "") for message in json.loads(prompt.stdout)
                          for item in message.get("content", [])]
            if not any(instruction.read_text().strip() in part for part in text_parts):
                raise ValueError(f"{variant}/{case}: selected global instructions absent or truncated")
            extra = [p for p in workspace.rglob("*") if p.name in ("AGENTS.md", "AGENTS.override.md")
                     and "node_modules" not in p.parts]
            if extra:
                raise ValueError(f"Fixture contains unexpected project instructions: {extra}")
            manifest["runs"][f"{variant}/{case}"] = {
                "root": str(run_root), "artifacts": str(artifacts), "prompts": prompts,
                "inputs": inventory(workspace), "control": inventory(home),
                "fixture": str(fixture.resolve()), "prompt_input_sha256": digest(artifacts / "prompt-input.json"),
                "config_sha256": digest(home / "config.toml"), "instructions_verified": True}
    save(output / "experiment.json", manifest)
    print(output / "experiment.json")


def load_run(args):
    experiment = json.loads(args.experiment.read_text())
    return experiment, experiment["runs"][f"{args.variant}/{args.case}"]


def check_controls(run):
    home = Path(run["root"]) / "home" / ".codex"
    for relative, expected in run["control"].items():
        path = home / relative
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f"Control changed after preparation: {path}")


def native_usage(home):
    """Read per-session counters without exporting prompts or tool arguments."""
    sessions = []
    warnings = []
    for path in sorted((home / "sessions").rglob("*.jsonl")):
        metadata, context, usage = None, {}, None
        try:
            lines = path.read_text(errors="replace").splitlines()
        except OSError as error:
            warnings.append(f"Could not read {path.name}: {error.strerror}")
            continue
        for raw in lines:
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue
            payload = event.get("payload", {})
            if not isinstance(payload, dict):
                continue
            if event.get("type") == "session_meta" and metadata is None:
                # Forked rollouts can also contain copied parent metadata.
                metadata = payload
            elif event.get("type") == "turn_context":
                context = payload
            elif event.get("type") == "event_msg" and payload.get("type") == "token_count":
                info = payload.get("info") or {}
                if not isinstance(info, dict):
                    continue
                if isinstance(info.get("total_token_usage"), dict):
                    usage = {key: value for key, value in info["total_token_usage"].items()
                             if key in ("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
                                        "output_tokens", "reasoning_output_tokens", "total_tokens")}
        if not metadata:
            continue
        source = metadata.get("source")
        subagent = source.get("subagent") if isinstance(source, dict) else None
        spawn = subagent.get("thread_spawn") if isinstance(subagent, dict) else None
        spawn = spawn if isinstance(spawn, dict) else {}
        sessions.append({"thread_id": metadata.get("id"), "parent_thread_id": spawn.get("parent_thread_id"),
                         "role": spawn.get("agent_role"), "model": context.get("model"),
                         "effort": context.get("effort"), "reported_usage": usage})
    return {"sessions": sessions, "warnings": warnings,
            "note": "Native per-session cumulative counters; do not sum snapshots across turns. "
                    "Cached input and reasoning output are subsets, not additional tokens. "
                    "Missing counters are unavailable, not zero. This is not billing data."}


def run(args):
    experiment, selected = load_run(args)
    root, artifacts = Path(selected["root"]), Path(selected["artifacts"])
    workspace = root / "workspace"
    if list(artifacts.glob("turn-*.jsonl")):
        raise ValueError("This run already started; prepare a fresh experiment for a repeat")
    check_controls(selected)
    if inventory(workspace) != selected["inputs"]:
        raise ValueError("Workspace changed after preparation")
    auth = root / "home" / ".codex" / "auth.json"
    if not args.auth_file.is_file():
        raise ValueError(f"Auth file missing: {args.auth_file}")
    shutil.copyfile(args.auth_file, auth)
    auth.chmod(0o600)
    thread = None
    results = []
    save(artifacts / "tool-environment.json", {k: os.environ[k] for k in
         ("PLAYWRIGHT_BROWSERS_PATH",) if k in os.environ})
    try:
        for number, prompt in enumerate(selected["prompts"], 1):
            started_at = time.monotonic()
            command = [experiment["codex"], "exec", "--cd", str(workspace)]
            if thread:
                command += ["resume", thread]
            command += ["--strict-config", "--ignore-rules", "--skip-git-repo-check", "--json",
                        "--output-last-message", str(artifacts / f"turn-{number}-final.md"), "-"]
            save(artifacts / f"turn-{number}-command.json", command)
            with (artifacts / f"turn-{number}.jsonl").open("w") as stdout, \
                    (artifacts / f"turn-{number}.stderr").open("w") as stderr:
                completed = subprocess.Popen(command, stdin=subprocess.PIPE, text=True, cwd=workspace,
                                             env=environment(root), stdout=stdout, stderr=stderr,
                                             start_new_session=True)
                try:
                    completed.communicate(prompt, timeout=args.timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(completed.pid, signal.SIGTERM)
                    try:
                        completed.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(completed.pid, signal.SIGKILL)
                        completed.wait()
                    raise
            events = []
            for line in (artifacts / f"turn-{number}.jsonl").read_text().splitlines():
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
            started = next((e for e in events if e.get("type") == "thread.started"), None)
            if started:
                thread = started["thread_id"]
            results.append({"turn": number, "exit_code": completed.returncode, "thread_id": thread,
                            "elapsed_seconds": round(time.monotonic() - started_at, 3),
                            "usage": [e.get("usage") for e in events if e.get("type") == "turn.completed"],
                            "workspace": inventory(workspace)})
            save(artifacts / "run.json", results)
            snapshot = artifacts / f"turn-{number}-workspace"
            shutil.copytree(workspace, snapshot, ignore=shutil.ignore_patterns("node_modules", ".git", "__pycache__"))
            if completed.returncode or not any(e.get("type") == "turn.completed" for e in events):
                raise RuntimeError(f"Turn {number} did not complete; inspect raw events and stderr")
            if number < len(selected["prompts"]) and not thread:
                raise RuntimeError("Native thread id missing; cannot perform a real resume")
    finally:
        auth.unlink(missing_ok=True)
        save(artifacts / "native-usage.json", native_usage(root / "home" / ".codex"))
    verify(args)


def verify(args):
    _, selected = load_run(args)
    workspace = Path(selected["root"]) / "workspace"
    artifacts = Path(selected["artifacts"])
    verifier = Path(selected["fixture"]) / "verify.py"
    result = subprocess.run(["uv", "run", "--no-project", "--offline", str(verifier), str(workspace)],
                            text=True, capture_output=True)
    (artifacts / "verification.stdout").write_text(result.stdout)
    (artifacts / "verification.stderr").write_text(result.stderr)
    print(result.stdout.strip())
    if result.returncode:
        raise RuntimeError(f"Verifier failed ({result.returncode}); inspect {artifacts}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("prepare", help="No inference: isolate inputs and verify actual prompt loading")
    p.add_argument("--baseline", type=Path, required=True)
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--cases", nargs="+", choices=CASES,
                   default=["coding", "research", "browser", "resume"])
    p.add_argument("--model", default="gpt-6-astra")
    p.add_argument("--effort", choices=("low", "medium", "high", "xhigh", "max", "ultra"), default="xhigh")
    p.add_argument("--sandbox", choices=("read-only", "workspace-write", "danger-full-access"),
                   default="workspace-write", help="Use the same explicit tool permissions for both variants")
    p.add_argument("--codex", default="codex")
    p.add_argument("--skill", type=Path, action="append", default=[])
    p.add_argument("--agent-dir", type=Path,
                   help="Copy identical custom *.toml agent roles into both isolated homes")
    p.add_argument("--browser-modules", type=Path)
    p.set_defaults(func=prepare)
    for name, function in (("run", run), ("verify", verify)):
        p = commands.add_parser(name)
        p.add_argument("experiment", type=Path)
        p.add_argument("variant", choices=("baseline", "candidate"))
        p.add_argument("case", choices=CASES)
        if name == "run":
            p.add_argument("--auth-file", type=Path,
                           default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "auth.json")
            p.add_argument("--timeout", type=int, default=1800)
        p.set_defaults(func=function)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
