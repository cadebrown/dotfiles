# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Explicit, copy-only import of portable Codex history into a stopped runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile


def fingerprint(path: Path) -> tuple[int, int, int, int]:
    info = path.stat()
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def private_directory(path: Path, root: Path) -> None:
    """Do not follow destination links or traverse another user's directory."""
    current = root
    for part in path.relative_to(root).parts:
        current /= part
        if current.is_symlink():
            raise ValueError(f"destination contains a symlink: {current}")
        current.mkdir(mode=0o700, exist_ok=True)
        info = current.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError(f"destination directory is not owned by this user: {current}")


def copy_new(source: Path, destination: Path, root: Path) -> str:
    if source.is_symlink() or not source.is_file():
        raise ValueError(f"history input is not a regular file: {source}")
    if destination.is_symlink():
        raise ValueError(f"history destination is a symlink: {destination}")
    if destination.exists():
        if not destination.is_file():
            raise ValueError(f"history destination is not a file: {destination}")
        return "existing"
    private_directory(destination.parent, root)
    before = fingerprint(source)
    descriptor, temporary = tempfile.mkstemp(prefix='.history-import-', dir=destination.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output, source.open('rb') as input_file:
            shutil.copyfileobj(input_file, output)
            output.flush()
            os.fsync(output.fileno())
        if before != fingerprint(source):
            raise ValueError(f"source changed during copy; stop its writer and retry: {source}")
        # Verify stored bytes independently before publishing the destination.
        with source.open('rb') as original, open(temporary, 'rb') as copied:
            if hashlib.file_digest(original, 'sha256').digest() != hashlib.file_digest(copied, 'sha256').digest():
                raise ValueError(f"copy verification failed; source retained: {source}")
        if before != fingerprint(source):
            raise ValueError(f"source changed during verification; source retained: {source}")
        os.utime(temporary, ns=(source.stat().st_atime_ns, before[3]))
        try:
            os.link(temporary, destination)
        except FileExistsError:
            return "existing"
        return "copied"
    finally:
        os.unlink(temporary)


def _portable_boundary(source: Path, name: str) -> Path | None:
    """Resolve only an explicitly named legacy root, never an interior link."""
    boundary = source / name
    if not boundary.exists() and not boundary.is_symlink():
        return None
    try:
        resolved = boundary.resolve(strict=True)
    except OSError as error:
        raise ValueError(f'could not resolve portable {name} boundary: {boundary}') from error
    if not resolved.is_dir():
        raise ValueError(f'portable {name} boundary is not a directory: {boundary}')
    return resolved


def _regular_files(directory: Path, suffix: str | None = None) -> list[Path]:
    """Enumerate regular files while rejecting any interior symlink boundary."""
    files: list[Path] = []

    def visit(current: Path) -> None:
        for item in sorted(current.iterdir(), key=lambda path: path.name):
            if item.is_symlink():
                raise ValueError(f'interior symlink in portable history: {item}')
            if item.is_dir():
                visit(item)
            elif item.is_file():
                if suffix is None or item.name.endswith(suffix):
                    files.append(item)
            else:
                raise ValueError(f'non-regular path in portable history: {item}')

    visit(directory)
    return files


def import_history(source: Path, destination: Path) -> dict[str, int]:
    if destination.is_symlink() or not destination.is_dir():
        raise ValueError('destination must be a prepared real CODEX_HOME directory')
    destination = destination.resolve()
    source = source.resolve(strict=True)
    info = destination.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('destination must be private and owned by the current user')
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError('source and destination must be separate, non-nested trees')
    if (destination / 'app-server-control' / 'app-server-control.sock').exists():
        raise ValueError('stop the destination Codex app-server before importing history')
    results = {'copied': 0, 'existing': 0, 'bytes_copied': 0}
    candidates: list[tuple[Path, Path]] = []
    for name in ('sessions', 'archived_sessions'):
        directory = _portable_boundary(source, name)
        if directory is None:
            continue
        for item in _regular_files(directory, '.jsonl'):
            candidates.append((item, destination / name / item.relative_to(directory)))
    for name in ('attachments', 'generated_images', 'visualizations'):
        directory = _portable_boundary(source, name)
        if directory is None:
            continue
        for item in _regular_files(directory):
            candidates.append((item, destination / name / item.relative_to(directory)))
    for name in ('session_index.jsonl', 'history.jsonl'):
        item = source / name
        if item.is_symlink():
            raise ValueError(f'portable root file must not be a symlink: {item}')
        if item.is_file():
            candidates.append((item, destination / name))
    for original, copied in candidates:
        outcome = copy_new(original, copied, destination)
        results[outcome] += 1
        if outcome == 'copied':
            results['bytes_copied'] += copied.stat().st_size
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(import_history(args.source, args.destination)))
    except (OSError, ValueError) as error:
        parser.exit(1, f'History import failed: {error}\nExisting files and source history were not overwritten.\n')


if __name__ == '__main__':
    main()
