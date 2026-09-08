#!/usr/bin/env python3
"""Reconcile generated plugin hook gates after install/update; upstream stays intact.

Only hook command declarations are generated. The checked-in dispatcher and this
strict transform are authoritative; never hand-edit the plugin cache. Unknown
upstream gates retain full checks and report that optimization needs review.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import sys


HOOKIFY = {
    "PreToolUse": "pretooluse.py", "PostToolUse": "posttooluse.py",
    "Stop": "stop.py", "UserPromptSubmit": "userpromptsubmit.py",
}
LEAN = {
    "SessionStart": "bootstrap.sh", "UserPromptSubmit": "validate_user_prompt.py",
    "PreToolUse": "guardrails.sh",
}
# These source files define the negative gates. A new loader can add another
# rule location without changing hooks.json; require review before skipping it.
# Audited: Hookify 85cce0381e78; Lean4 4.8.5.
GATE_SOURCES = {
    "hookify": {
        "core/config_loader.py": "9f1d083cc43883323ddf00747e7696a4fd9d478ddd63f5b43038657da8516e56",
        "core/rule_engine.py": "6c70424f7eafdea4e803c7bcb93305e1e75bfd8c405834ebfcdf34bb79f66fb4",
        "hooks/pretooluse.py": "5d28948f576f93caefcb4089959db2066147334c61be3139a1c113593255a8c7",
        "hooks/posttooluse.py": "52f3b71247cc376fb4226ab44258e89b02f997840cadbfd0e1ebd06009b76f32",
        "hooks/stop.py": "6ebc614e48dd994a4fe2aa1a3f2b5ab413ffd2b3c22f81c66cacd23f9c92919e",
        "hooks/userpromptsubmit.py": "577824bc91e4510eb6f299b3485f35892eaf710108213e01f4c86eb350a813cb",
    },
    "lean4": {
        "hooks/validate_user_prompt.py": "14ea93c48cb9b6a147f066f0714e9f3ec9c40e6cd71d60fc6db8913a49c7721a",
        "hooks/guardrails.sh": "28e02b9ff78e3745d0c296d4d4730b2b8c10353b0994d7c3fdf3d91815735317",
    },
}


def transform(document, plugin):
    spec = HOOKIFY if plugin == "hookify" else LEAN
    hooks = document.get("hooks", {})
    if set(hooks) != set(spec):
        raise ValueError(f"{plugin}: upstream hook events changed")
    for event, script in spec.items():
        groups = hooks[event]
        if len(groups) != 1 or len(groups[0].get("hooks", [])) != 1:
            raise ValueError(f"{plugin}/{event}: upstream hook layout changed")
        group = groups[0]
        hook = group["hooks"][0]
        matcher = "startup" if event == "SessionStart" else "Bash" if plugin == "lean4" and event == "PreToolUse" else ""
        if group.get("matcher", "") != matcher or hook.get("type") != "command":
            raise ValueError(f"{plugin}/{event}: upstream hook matcher/type changed")
        root_path = '${CLAUDE_PLUGIN_ROOT}/hooks/' + script
        original = f'python3 "{root_path}"' if plugin == "hookify" else root_path
        if event == "SessionStart":
            # Environment setup is required even if Lean is first used later.
            if hook.get("command") != original:
                raise ValueError(f"{plugin}/{event}: upstream bootstrap command changed")
            continue
        mode = "hookify" if plugin == "hookify" else "lean-prompt" if event == "UserPromptSubmit" else "lean-guard"
        invocation = f'python3 "{root_path}"' if plugin == "hookify" else f'"{root_path}"'
        generated = f'"$HOME/.claude/hook-scope.sh" {mode} {invocation}'
        if hook.get("command") not in (original, generated):
            raise ValueError(f"{plugin}/{event}: upstream command changed: {hook.get('command')!r}")
        hook["command"] = generated
    return document


def unscoped(document, plugin):
    """Restore only our exact generated commands; leave new upstream hooks alone."""
    spec = HOOKIFY if plugin == "hookify" else LEAN
    known = {}
    for event, script in spec.items():
        if event == "SessionStart":
            continue
        root_path = '${CLAUDE_PLUGIN_ROOT}/hooks/' + script
        original = f'python3 "{root_path}"' if plugin == "hookify" else root_path
        mode = "hookify" if plugin == "hookify" else "lean-prompt" if event == "UserPromptSubmit" else "lean-guard"
        invocation = f'python3 "{root_path}"' if plugin == "hookify" else f'"{root_path}"'
        known[f'"$HOME/.claude/hook-scope.sh" {mode} {invocation}'] = original
    for groups in document.get("hooks", {}).values():
        for group in groups:
            for hook in group.get("hooks", []):
                command = hook.get("command")
                if command in known:
                    hook["command"] = known[command]
    return document


def write_json(target, rendered):
    if target.exists() and json.loads(target.read_text()) == json.loads(rendered):
        return
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
    with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as output:
        output.write(rendered)
        temporary = output.name
    os.chmod(temporary, mode)
    os.replace(temporary, target)


def reconcile(claude_dir):
    registry = claude_dir / "plugins/installed_plugins.json"
    plugins = json.loads(registry.read_text())["plugins"]
    pending = []
    receipt = []
    for plugin, key in (("hookify", "hookify@claude-plugins-official"), ("lean4", "lean4@lean4-skills")):
        entries = plugins.get(key, [])
        if not entries:
            raise ValueError(f"Missing installed plugin {key}")
        for entry in entries:
            install_root = Path(entry["installPath"])
            changed_sources = []
            for source, expected in GATE_SOURCES[plugin].items():
                source_path = install_root / source
                actual = hashlib.sha256(source_path.read_bytes()).hexdigest() if source_path.is_file() else "missing"
                if actual != expected:
                    changed_sources.append(source)
            target = install_root / "hooks/hooks.json"
            original = target.read_text()
            reason = ""
            try:
                if changed_sources:
                    raise ValueError("upstream gate source changed: " + ", ".join(changed_sources))
                document = transform(json.loads(original), plugin)
            except ValueError as error:
                reason = str(error)
                document = unscoped(json.loads(original), plugin)
                print(f"WARNING: {plugin} hook optimization needs review ({reason}); using full upstream hooks", file=sys.stderr)
            rendered = json.dumps(document, indent=2) + "\n"
            pending.append((target, original, rendered))
            receipt.append({"plugin": key, "installPath": str(install_root),
                            "status": "unscoped" if reason else "scoped", "reason": reason})
    # Validate every declaration before making the first change.
    for target, original, rendered in pending:
        if json.loads(original) == json.loads(rendered):
            continue
        write_json(target, rendered)
        print(f"Reconciled plugin hooks: {target}")
    write_json(claude_dir / "hook-scope-state.json", json.dumps({"plugins": receipt}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-dir", type=Path, default=Path.home() / ".claude")
    args = parser.parse_args()
    try:
        reconcile(args.claude_dir)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Claude hook scoping failed; review upstream declarations: {error}\n")
