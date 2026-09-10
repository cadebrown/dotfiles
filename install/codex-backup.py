# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Create a verified, non-destructive backup of one or more Codex state roots.

The sources should be quiesced first.  This program detects changes while it
runs, but it neither establishes a point-in-time snapshot nor repairs SQLite.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
from typing import Iterable


class BackupError(ValueError):
    """The backup is intentionally left incomplete."""


@dataclass(frozen=True)
class Fingerprint:
    device: int
    inode: int
    size: int
    mtime_ns: int
    ctime_ns: int
    mode: int
    uid: int
    gid: int


@dataclass(frozen=True)
class FileEntry:
    path: str
    source: str
    fingerprint: Fingerprint


@dataclass(frozen=True)
class DirectoryEntry:
    path: str
    source: str
    fingerprint: Fingerprint


@dataclass(frozen=True)
class SymlinkEntry:
    path: str
    target: str
    resolved: str | None
    status: str
    fingerprint: Fingerprint


@dataclass(frozen=True)
class SpecialEntry:
    path: str
    kind: str
    fingerprint: Fingerprint


@dataclass
class Inventory:
    files: list[FileEntry]
    directories: list[DirectoryEntry]
    symlinks: list[SymlinkEntry]
    special: list[SpecialEntry]

    def normalized(self) -> dict[str, object]:
        return {
            'files': [asdict(item) for item in sorted(self.files, key=lambda item: item.path)],
            'directories': [asdict(item) for item in sorted(self.directories, key=lambda item: item.path)],
            'symlinks': [asdict(item) for item in sorted(self.symlinks, key=lambda item: item.path)],
            'special': [asdict(item) for item in sorted(self.special, key=lambda item: item.path)],
        }


def _fingerprint(info: os.stat_result) -> Fingerprint:
    return Fingerprint(
        info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns,
        stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid,
    )


def _relative(path: Path) -> str:
    value = str(path)
    return '.' if value == '.' else value


def _kind(mode: int) -> str:
    if stat.S_ISFIFO(mode):
        return 'fifo'
    if stat.S_ISSOCK(mode):
        return 'socket'
    if stat.S_ISCHR(mode):
        return 'character-device'
    if stat.S_ISBLK(mode):
        return 'block-device'
    return 'unknown-special'


def inventory_root(root: Path) -> Inventory:
    """Walk ``root`` without opening special files or silently losing links."""
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise BackupError(f'source root is not a directory: {root}')
    inventory = Inventory([], [], [], [])

    def visit(physical: Path, logical: Path, ancestors: set[tuple[int, int]]) -> None:
        try:
            info = physical.lstat()
        except OSError as error:
            raise BackupError(f'cannot inspect source path {physical}: {error}') from error
        logical_name = _relative(logical)
        if stat.S_ISLNK(info.st_mode):
            try:
                target = os.readlink(physical)
                resolved = physical.resolve(strict=True)
            except FileNotFoundError:
                # Agent sockets can disappear between a directory scan and
                # backup. Preserve the topology, explicitly report it, and do
                # not manufacture a misleading empty file in the backup.
                inventory.symlinks.append(
                    SymlinkEntry(logical_name, os.readlink(physical), None, 'dangling', _fingerprint(info))
                )
                return
            except (OSError, RuntimeError) as error:
                raise BackupError(f'cannot resolve symlink {physical}: {error}') from error
            inventory.symlinks.append(
                SymlinkEntry(logical_name, target, str(resolved), 'materialized', _fingerprint(info))
            )
            visit(resolved, logical, ancestors)
            return
        if stat.S_ISREG(info.st_mode):
            inventory.files.append(FileEntry(logical_name, str(physical), _fingerprint(info)))
            return
        if stat.S_ISDIR(info.st_mode):
            identity = (info.st_dev, info.st_ino)
            if identity in ancestors:
                raise BackupError(f'symlink directory cycle at {physical}')
            inventory.directories.append(DirectoryEntry(logical_name, str(physical), _fingerprint(info)))
            next_ancestors = ancestors | {identity}
            try:
                children = sorted(os.scandir(physical), key=lambda entry: entry.name)
            except OSError as error:
                raise BackupError(f'cannot list source directory {physical}: {error}') from error
            for child in children:
                visit(Path(child.path), logical / child.name, next_ancestors)
            return
        inventory.special.append(SpecialEntry(logical_name, _kind(info.st_mode), _fingerprint(info)))

    visit(root, Path('.'), set())
    return inventory


def _private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise BackupError(f'backup directory is unsafe: {path}')
    os.chmod(path, 0o700)


def _atomic_json(path: Path, payload: object) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix='.codex-backup-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='') as output:
            json.dump(payload, output, indent=2, sort_keys=True, ensure_ascii=False)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def _same_fingerprint(actual: os.stat_result, expected: Fingerprint) -> bool:
    return _fingerprint(actual) == expected


def _sha256(handle) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def copy_regular(entry: FileEntry, destination: Path) -> dict[str, object]:
    """Copy one immutable-in-practice source and independently verify bytes."""
    _private_directory(destination.parent)
    descriptor, temporary = tempfile.mkstemp(prefix='.codex-backup-', dir=destination.parent)
    source = Path(entry.source)
    try:
        with os.fdopen(descriptor, 'wb') as output, source.open('rb') as input_file:
            before = os.fstat(input_file.fileno())
            if not _same_fingerprint(before, entry.fingerprint):
                raise BackupError(f'source changed before copy: {source}')
            digest = hashlib.sha256()
            for chunk in iter(lambda: input_file.read(1024 * 1024), b''):
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
            if not _same_fingerprint(os.fstat(input_file.fileno()), entry.fingerprint):
                raise BackupError(f'source changed during copy: {source}')
        if not _same_fingerprint(source.stat(), entry.fingerprint):
            raise BackupError(f'source changed after copy: {source}')
        with open(temporary, 'rb') as copied:
            copied_digest = _sha256(copied)
        if digest.hexdigest() != copied_digest:
            raise BackupError(f'copy verification failed: {source}')
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
        return {'path': entry.path, 'sha256': copied_digest, 'bytes': entry.fingerprint.size}
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def _parse_source(value: str) -> tuple[str, Path]:
    label, separator, raw_root = value.partition('=')
    if not separator or not label or not raw_root:
        raise argparse.ArgumentTypeError('--source must be LABEL=/absolute/root')
    try:
        _validate_label(label)
    except BackupError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    root = Path(raw_root)
    if not root.is_absolute():
        raise argparse.ArgumentTypeError(f'source root must be absolute: {raw_root!r}')
    return label, root


def _validate_label(label: str) -> None:
    if label in {'.', '..'} or not label:
        raise BackupError(f'invalid source label: {label!r}')
    if any(character not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for character in label):
        raise BackupError(f'invalid source label: {label!r}')


def _assert_safe_destination_ancestors(parent: Path) -> None:
    """Reject writable ancestor hazards; never alter pre-existing directories."""
    current = parent
    while True:
        info = current.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise BackupError(f'destination ancestor is not a real directory: {current}')
        unsafe_writable = stat.S_IMODE(info.st_mode) & 0o022
        trusted_sticky_boundary = info.st_uid == 0 and info.st_mode & stat.S_ISVTX
        if unsafe_writable and not trusted_sticky_boundary:
            raise BackupError(f'destination ancestor is writable by non-owners: {current}')
        if current.parent == current:
            return
        current = current.parent


def _ensure_new_destination(destination: Path, directories: Iterable[DirectoryEntry]) -> Path:
    if not destination.is_absolute():
        raise BackupError('destination must be an absolute path')
    if os.path.lexists(destination):
        raise BackupError(f'destination already exists and will not be overwritten: {destination}')
    parent = destination.parent.resolve(strict=True)
    if not parent.is_dir():
        raise BackupError(f'destination parent is not a directory: {parent}')
    actual_destination = parent / destination.name
    _assert_safe_destination_ancestors(parent)
    for directory in directories:
        source_directory = Path(directory.source)
        if actual_destination == source_directory or actual_destination.is_relative_to(source_directory):
            raise BackupError(
                f'destination must not be inside a dereferenced source directory: {actual_destination} ({source_directory})'
            )
    os.mkdir(actual_destination, 0o700)
    _private_directory(actual_destination)
    return actual_destination


def backup(sources: list[tuple[str, Path]], destination: Path) -> dict[str, object]:
    for label, root in sources:
        _validate_label(label)
        if not root.is_absolute():
            raise BackupError(f'source root must be absolute: {root}')
    if len({label for label, _ in sources}) != len(sources):
        raise BackupError('source labels must be unique')
    resolved_sources = [(label, root.resolve(strict=True)) for label, root in sources]
    for _, root in resolved_sources:
        if not root.is_dir():
            raise BackupError(f'source root is not a directory: {root}')
    # Do this before creating the destination: an external symlinked directory
    # could otherwise contain that new destination and make the walk ingest its
    # own partial backup.
    initial = {label: inventory_root(root) for label, root in resolved_sources}
    destination = _ensure_new_destination(
        destination,
        (directory for inventory in initial.values() for directory in inventory.directories),
    )
    _atomic_json(destination / 'INCOMPLETE.json', {
        'status': 'incomplete',
        'reason': 'copying; a completion manifest is written only after verification',
    })
    try:
        files: list[dict[str, object]] = []
        source_manifests: dict[str, object] = {}
        for label, root in resolved_sources:
            tree = destination / 'sources' / label / 'tree'
            _private_directory(tree)
            for directory in initial[label].directories:
                _private_directory(tree / directory.path)
            source_files = []
            for entry in initial[label].files:
                copied = copy_regular(entry, tree / entry.path)
                source_files.append(copied)
                files.append({'source': label, **copied})
            source_manifests[label] = {
                'root': str(root),
                'inventory': initial[label].normalized(),
                'files': source_files,
            }
            _atomic_json(destination / 'sources' / label / 'symlink-topology.json', {
                'source_root': str(root),
                'symlinks': [asdict(item) for item in initial[label].symlinks],
                'dangling_symlink_count': sum(item.status == 'dangling' for item in initial[label].symlinks),
                'materialization': 'tree paths contain copied referent bytes, not symlink stubs',
            })
        rescanned = {label: inventory_root(root) for label, root in resolved_sources}
        changed = [label for label in initial if initial[label].normalized() != rescanned[label].normalized()]
        if changed:
            raise BackupError('source inventory changed during backup; incomplete backup retained: ' + ', '.join(changed))
        manifest = {
            'format': 1,
            'status': 'complete',
            'consistency': 'verified stable inventory only; not a point-in-time snapshot',
            'sqlite': 'raw bytes copied without parsing, recovery, or repair',
            'sources': source_manifests,
            'files': files,
        }
        _atomic_json(destination / 'manifest.json', manifest)
        os.unlink(destination / 'INCOMPLETE.json')
        return manifest
    except Exception as error:
        _atomic_json(destination / 'INCOMPLETE.json', {
            'status': 'incomplete',
            'reason': str(error),
        })
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='append', required=True, type=_parse_source,
                        help='repeatable LABEL=/absolute/root')
    parser.add_argument('--destination', required=True, type=Path,
                        help='absolute, new backup directory')
    args = parser.parse_args()
    try:
        manifest = backup(args.source, args.destination)
    except (OSError, BackupError) as error:
        parser.exit(1, f'Codex backup failed: {error}\nNo completion manifest was written. Source data was not modified.\n')
    print(json.dumps({'destination': str(args.destination), 'files': len(manifest['files']), 'status': 'complete'}))


if __name__ == '__main__':
    main()
