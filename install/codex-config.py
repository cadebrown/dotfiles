# /// script
# requires-python = ">=3.11"
# dependencies = ["tomlkit==0.13.3"]
# ///
"""Merge Codex defaults while preserving runtime integrations in full-auto mode."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from collections.abc import MutableMapping
from copy import deepcopy
from pathlib import Path

import tomlkit
from tomlkit.items import Table

PREFERENCES = {
    ("model",),
    ("model_provider",),
    ("model_reasoning_effort",),
    ("plan_mode_reasoning_effort",),
    ("model_verbosity",),
    ("service_tier",),
    ("personality",),
}
RETIRED = {
    ("sandbox_mode",),
    ("profiles",),
    ("agents", "max_threads"),
    ("apps", "_default", "default_tools_enabled"),
}
RUNTIME = {"projects", "notice", "marketplaces", "plugins"}
PROFILE_HEADER = "# Managed MCP activation from packages/mcp-servers.txt.\n"
FULL_AUTO_APPROVAL_MODE = "approve"


def preapprove_tools(config):
    """Apply prompt-free defaults to managed and runtime-added tool configs."""
    for server in config.get("mcp_servers", {}).values():
        if isinstance(server, MutableMapping):
            server["default_tools_approval_mode"] = FULL_AUTO_APPROVAL_MODE

    for app in config.get("apps", {}).values():
        if not isinstance(app, MutableMapping):
            continue
        app["default_tools_approval_mode"] = FULL_AUTO_APPROVAL_MODE
        for tool in app.get("tools", {}).values():
            if isinstance(tool, MutableMapping):
                tool["approval_mode"] = FULL_AUTO_APPROVAL_MODE


def merge_config(managed, current, owned_servers):
    merged = deepcopy(managed)

    def copy_entry(target, key, value):
        copied = deepcopy(value)
        target[key] = copied
        if isinstance(copied, Table):
            # tomlkit may add a separator that reparses into the preceding table.
            # Restore the original indent so repeated merges cannot grow blanks.
            copied.trivia.indent = value.trivia.indent

    def preserve(target, source, path=()):
        for key, value in source.items():
            location = (*path, key)
            if location in RETIRED:
                continue
            if path == ("mcp_servers",) and key in owned_servers:
                continue
            if location in PREFERENCES or (not path and key in RUNTIME):
                copy_entry(target, key, value)
            elif key not in target:
                if location == ("mcp_servers",):
                    target[key] = tomlkit.table()
                    preserve(target[key], value, location)
                else:
                    copy_entry(target, key, value)
            elif isinstance(value, MutableMapping) and isinstance(
                target[key], MutableMapping
            ):
                preserve(target[key], value, location)

    preserve(merged, current)
    preapprove_tools(merged)
    return merged


def disable_skills(config, paths):
    if not paths:
        return
    skills = config.setdefault("skills", tomlkit.table())
    entries = skills.setdefault("config", tomlkit.aot())
    for path in paths:
        for target in dict.fromkeys((str(path), str(path.resolve()))):
            existing = next((row for row in entries if row.get("path") == target), None)
            if existing is None:
                existing = tomlkit.table()
                existing["path"] = target
                entries.append(existing)
            existing["enabled"] = False


def atomic_write(path, text):
    if path.exists() and path.read_text() == text:
        if path.stat().st_mode & 0o777 != 0o600:
            path.chmod(0o600)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def sync_profiles(directory, records, owned_servers):
    profiles = {}
    reserved = {"deep", "review", "fast", "context", "tools-all"}
    for record in records:
        name = record["profile"]
        if name == "core":
            continue
        if name in reserved or re.fullmatch(r"[a-z][a-z0-9-]*", name) is None:
            raise ValueError(f"MCP profile name is invalid or reserved: {name}")
        profiles.setdefault(name, []).append(record["name"])
    if records:
        profiles["tools-all"] = [record["name"] for record in records]
    ownership = directory / ".dotfiles-mcp-profile-ownership.json"
    if ownership.exists():
        previous = json.loads(ownership.read_text())
    else:
        previous = {}
        for path in directory.glob("*.config.toml"):
            content = path.read_text()
            if content.startswith(PROFILE_HEADER):
                servers = tomlkit.parse(content).get("mcp_servers", {})
                previous[path.name.removesuffix(".config.toml")] = sorted(
                    set(servers) & owned_servers
                )
    for name in previous:
        if re.fullmatch(r"[a-z][a-z0-9-]*", name) is None or name in reserved - {
            "tools-all"
        }:
            raise ValueError(f"Invalid managed profile ownership: {name}")
    for name, servers in profiles.items():
        path = directory / f"{name}.config.toml"
        managed = tomlkit.document()
        managed.add(tomlkit.comment(PROFILE_HEADER[2:].rstrip()))
        managed["mcp_servers"] = {server: {"enabled": True} for server in servers}
        current = (
            tomlkit.parse(path.read_text()) if path.exists() else tomlkit.document()
        )
        merged = merge_config(managed, current, owned_servers)
        atomic_write(path, tomlkit.dumps(merged))
    for name in previous.keys() - profiles.keys():
        path = directory / f"{name}.config.toml"
        if not path.exists():
            continue
        current = tomlkit.parse(path.read_text())
        servers = current.get("mcp_servers", {})
        for server in previous[name]:
            servers.pop(server, None)
        if not servers:
            current.pop("mcp_servers", None)
        if current:
            atomic_write(path, tomlkit.dumps(current))
        else:
            path.unlink()
    atomic_write(ownership, json.dumps(profiles, sort_keys=True) + "\n")


def render_agents(source_directory, scopes_file, config):
    """Resolve role tool scopes without copying server definitions into sources."""
    scopes = json.loads(scopes_file.read_text())
    if not isinstance(scopes, dict):
        raise ValueError("Codex agent tool scopes must be an object")
    servers = config.get("mcp_servers", {})
    rendered = {}
    for source in sorted(source_directory.glob("*.toml")):
        agent = tomlkit.parse(source.read_text())
        name = agent.get("name")
        if name != source.stem or re.fullmatch(r"[a-z][a-z0-9_]*", name) is None:
            raise ValueError(f"Agent name must match its source filename: {source}")
        if not all(isinstance(agent.get(key), str) and agent[key].strip()
                   for key in ("description", "developer_instructions")):
            raise ValueError(f"Agent is missing description or instructions: {source}")
        if name in scopes:
            allowed = scopes[name]
            if not isinstance(allowed, list) or not all(isinstance(item, str) for item in allowed):
                raise ValueError(f"Agent MCP scope must be a list of names: {name}")
            missing = set(allowed) - set(servers)
            if missing:
                raise ValueError(f"Unknown MCP servers for {name}: {sorted(missing)}")
            if any(key in agent for key in ("mcp_servers", "apps", "plugins")):
                raise ValueError(f"Scoped agent tool settings belong in the scope manifest: {name}")
            # Codex validates transport even on disabled MCP entries. Retain the
            # resolved transport/auth references, then control visibility per role.
            agent["mcp_servers"] = deepcopy(servers)
            for server_name, server in agent["mcp_servers"].items():
                server["enabled"] = server_name in allowed
                if server_name not in allowed:
                    server["required"] = False
            agent["apps"] = {key: {"enabled": False}
                             for key in sorted(set(config.get("apps", {})) | {"_default"})}
            # Plugin reconciliation runs after config sync. Disable discovery so
            # newly installed plugins cannot leak into this role on first sync.
            agent.setdefault("features", {})["plugins"] = False
        result = "# Managed from home/dot_codex/agents and packages/codex-agent-tools.json.\n"
        result += tomlkit.dumps(agent)
        tomlkit.parse(result)
        rendered[source.name] = result
    if not rendered:
        raise ValueError(f"No Codex agent sources found: {source_directory}")
    unknown = set(scopes) - {Path(filename).stem for filename in rendered}
    if unknown:
        raise ValueError(f"Tool scopes name missing agent sources: {sorted(unknown)}")
    return rendered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--managed", type=Path, required=True)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--ownership", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profiles-dir", type=Path)
    parser.add_argument("--agent-sources", type=Path)
    parser.add_argument("--agent-scopes", type=Path)
    parser.add_argument("--agents-dir", type=Path)
    parser.add_argument("--disable-skill", type=Path, action="append", default=[])
    args = parser.parse_args()
    agent_options = (args.agent_sources, args.agent_scopes, args.agents_dir)
    if any(agent_options) and not all(agent_options):
        parser.error("--agent-sources, --agent-scopes, and --agents-dir must be supplied together")

    original = args.current.read_text() if args.current.exists() else None
    current = tomlkit.parse(original or "")
    managed = tomlkit.parse(args.managed.read_text())
    records = [json.loads(line) for line in args.registry.read_text().splitlines()]
    registry = {record["name"] for record in records}
    previous = (
        set(json.loads(args.ownership.read_text()))
        if args.ownership.exists()
        else set()
    )
    merged = merge_config(managed, current, registry | previous)
    disable_skills(merged, args.disable_skill)
    rendered = tomlkit.dumps(merged)
    tomlkit.parse(rendered)
    agents = render_agents(args.agent_sources, args.agent_scopes, merged) if all(agent_options) else {}

    if args.output == args.current:
        latest = args.current.read_text() if args.current.exists() else None
        if latest != original:
            parser.error(
                "Codex config changed during sync; retry to preserve the new state"
            )
    atomic_write(args.output, rendered)
    if args.profiles_dir:
        sync_profiles(args.profiles_dir, records, registry | previous)
    for filename, content in agents.items():
        atomic_write(args.agents_dir / filename, content)
    if args.output == args.current:
        atomic_write(args.ownership, json.dumps(sorted(registry)) + "\n")


if __name__ == "__main__":
    main()
