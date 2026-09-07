#!/usr/bin/env python3
"""Isolated bpy authoring, rendering, inspection, and GLB export."""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent


def glb_summary(path):
    data = Path(path).read_bytes()
    if len(data) < 20:
        raise ValueError('Truncated GLB header')
    magic, version, size = struct.unpack_from('<4sII', data)
    if magic != b'glTF' or version != 2 or size != len(data):
        raise ValueError('Invalid GLB v2 header or length')
    length, kind = struct.unpack_from('<II', data, 12)
    if kind != 0x4E4F534A or 20 + length > len(data):
        raise ValueError('Missing or truncated GLB JSON chunk')
    doc = json.loads(data[20:20 + length])
    if doc.get('asset', {}).get('version') != '2.0' or not doc.get('meshes'):
        raise ValueError('GLB has no glTF 2.0 mesh data')
    return {'bytes': size, 'meshes': len(doc['meshes']), 'nodes': len(doc.get('nodes', [])),
            'materials': len(doc.get('materials', [])), 'animations': len(doc.get('animations', []))}


def blender_path(explicit):
    candidate = explicit or os.environ.get('BLENDER_BIN') or shutil.which('blender')
    if not candidate and sys.platform == 'darwin':
        candidate = '/Applications/Blender.app/Contents/MacOS/Blender'
    if not candidate or not Path(candidate).is_file():
        raise ValueError('Blender not found; set BLENDER_BIN or --blender')
    return str(Path(candidate).resolve())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blender')
    parser.add_argument('--log-dir', type=Path)
    sub = parser.add_subparsers(dest='command', required=True)
    demo = sub.add_parser('demo', help='Create, render, export, and reopen a procedural diorama')
    demo.add_argument('directory', type=Path)
    demo.add_argument('--samples', type=int, default=48)
    for name in ('inspect', 'render', 'animation', 'export'):
        p = sub.add_parser(name)
        p.add_argument('blend', type=Path)
        p.add_argument('--output', required=True, type=Path)
        if name == 'render':
            p.add_argument('--frame', type=int, default=1)
        if name in ('render', 'animation'):
            p.add_argument('--samples', type=int, default=64)
            p.add_argument('--scale', type=int, default=100, help='Resolution percentage (1–100)')
        if name == 'animation':
            p.add_argument('--start', type=int)
            p.add_argument('--end', type=int)
            p.add_argument('--step', type=int, default=1)
            p.add_argument('--resume', action='store_true', help='Keep complete frames with matching dimensions')
        if name == 'export':
            p.add_argument('--collection')
    run = sub.add_parser('run', help='Execute a project bpy script')
    run.add_argument('script', type=Path)
    run.add_argument('--blend', type=Path)
    argv = sys.argv[1:]
    extra = []
    if '--' in argv:
        index = argv.index('--')
        argv, extra = argv[:index], argv[index + 1:]
    args = parser.parse_args(argv)
    if hasattr(args, 'samples') and args.samples < 1:
        parser.error('--samples must be positive')
    if hasattr(args, 'scale') and not 1 <= args.scale <= 100:
        parser.error('--scale must be in 1–100')
    if hasattr(args, 'step') and args.step < 1:
        parser.error('--step must be positive')
    binary = blender_path(args.blender)
    if extra and args.command != 'run':
        parser.error('Arguments after -- are supported only by run')
    if args.command == 'demo':
        directory = args.directory.resolve()
        if directory.exists() and any(directory.iterdir()):
            parser.error('Demo directory must be empty; use a new output directory')
        directory.mkdir(parents=True, exist_ok=True)
        logs = args.log_dir or directory / 'logs'
    else:
        logs = args.log_dir or Path(tempfile.mkdtemp(prefix='blender-workbench-'))
    logs = logs.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    sequence = 0

    def invoke(action, *, blend=None, script=None, output=None, **options):
        nonlocal sequence
        sequence += 1
        command = [binary, '--background', '--factory-startup', '--disable-autoexec']
        if blend:
            if not Path(blend).is_file():
                raise ValueError(f'Input scene does not exist: {blend}')
            command.append(str(Path(blend).resolve()))
        command += ['--python-exit-code', '1', '--python', str(script or HERE / 'scene_ops.py'), '--']
        if script:
            command += extra
        else:
            command += [json.dumps({'action': action, 'output': str(Path(output).resolve()) if output else None, **options})]
        log = logs / f'{sequence:02d}-{action}.log'
        while log.exists():
            sequence += 1
            log = logs / f'{sequence:02d}-{action}.log'
        with log.open('w') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                    env={**os.environ, 'DISABLE_TELEMETRY': 'true'}, check=False)
        if result.returncode:
            tail = '\n'.join(log.read_text().splitlines()[-24:])
            raise RuntimeError(f'Blender failed ({result.returncode}); {log}\n{tail}')
        return log

    if args.command == 'demo':
        blend, png, glb = [directory / name for name in ('orbital-compute.blend', 'hero.png', 'orbital-compute.glb')]
        invoke('demo', output=blend, samples=args.samples)
        invoke('render', blend=blend, output=png, frame=1, samples=args.samples)
        invoke('export', blend=blend, output=glb, collection='Orbital Compute')
        invoke('inspect', blend=blend, output=directory / 'scene.json')
        invoke('inspect_glb', output=directory / 'glb-import.json', source=str(glb))
        report = {'blend': str(blend), 'render': str(png), 'glb': str(glb),
                  'glb_structure': glb_summary(glb), 'logs': str(logs), 'reopened_blend': True,
                  'imported_glb': True, 'source_script': str(HERE / 'demo_scene.py')}
        shutil.copy2(HERE / 'demo_scene.py', directory / 'demo_scene.py')
        (directory / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    elif args.command == 'run':
        if not args.script.is_file():
            raise ValueError(f'Script not found: {args.script}')
        invoke('run', blend=args.blend, script=args.script.resolve())
        report = {'logs': str(logs)}
    else:
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        if output == args.blend.resolve():
            raise ValueError('Output must differ from input scene')
        options = {key: getattr(args, key) for key in ('frame', 'samples', 'scale', 'collection', 'start', 'end', 'step', 'resume') if hasattr(args, key)}
        invoke(args.command, blend=args.blend, output=output, **options)
        report = {'output': str(output), 'logs': str(logs)}
        if args.command == 'export':
            report['glb_structure'] = glb_summary(output)
            invoke('inspect_glb', source=str(output), output=logs / 'glb-import.json')
            report['imported_glb'] = True
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
