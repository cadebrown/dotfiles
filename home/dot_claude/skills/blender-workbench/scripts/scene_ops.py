"""Executed by Blender's Python, not the host Python."""
import importlib.util
import hashlib
import json
from pathlib import Path
import sys

import bpy


def inventory():
    scene = bpy.context.scene
    missing = []
    for path in bpy.utils.blend_paths(absolute=True):
        if path and not Path(path).exists():
            missing.append(path)
    return {
        'blender': bpy.app.version_string, 'file': bpy.data.filepath,
        'scene': scene.name, 'engine': scene.render.engine,
        'resolution': [scene.render.resolution_x, scene.render.resolution_y],
        'camera': scene.camera.name if scene.camera else None,
        'frames': [scene.frame_start, scene.frame_end],
        'fps': scene.render.fps / scene.render.fps_base,
        'objects': [{'name': obj.name, 'type': obj.type,
                     'location': list(obj.location), 'dimensions': list(obj.dimensions),
                     'vertices': len(obj.data.vertices) if obj.type == 'MESH' else None,
                     'polygons': len(obj.data.polygons) if obj.type == 'MESH' else None,
                     'materials': [slot.material.name if slot.material else None for slot in obj.material_slots]}
                    for obj in scene.objects],
        'collections': [collection.name for collection in bpy.data.collections],
        'materials': sorted({slot.material.name for obj in scene.objects
                             for slot in obj.material_slots if slot.material}),
        'actions': [action.name for action in bpy.data.actions],
        'missing_dependencies': missing,
    }


def main():
    config = json.loads(sys.argv[sys.argv.index('--') + 1])
    action, output = config['action'], Path(config['output'])
    if action == 'demo':
        spec = importlib.util.spec_from_file_location('demo_scene', Path(__file__).with_name('demo_scene.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.build(samples=config['samples'])
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
    elif action in ('render', 'animation'):
        scene = bpy.context.scene
        if not scene.camera:
            raise ValueError('Scene has no render camera')
        scene.cycles.samples = config['samples']
        scene.render.resolution_percentage = config.get('scale', 100)
        scene.render.image_settings.file_format = 'PNG'
        if action == 'animation':
            start = config['start'] if config['start'] is not None else scene.frame_start
            end = config['end'] if config['end'] is not None else scene.frame_end
            if end < start:
                raise ValueError('Animation end must be at or after start')
            output.mkdir(parents=True, exist_ok=True)
            frames = range(start, end + 1, config['step'])
            with Path(bpy.data.filepath).open('rb') as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            dependencies = {}
            for dependency in sorted(set(bpy.utils.blend_paths(absolute=True))):
                with Path(dependency).open('rb') as source:
                    dependencies[dependency] = hashlib.file_digest(source, 'sha256').hexdigest()
            job = {'scene_sha256': digest, 'blender': bpy.app.version_string,
                   'dependencies': dependencies,
                   'engine': scene.render.engine, 'samples': config['samples'],
                   'resolution': [scene.render.resolution_x, scene.render.resolution_y,
                                  scene.render.resolution_percentage],
                   'frames': list(frames)}
            provenance = output / 'render-job.json'
            if config.get('resume') and provenance.exists() and json.loads(provenance.read_text()) != job:
                raise ValueError('Resume settings or source scene changed; use a new output directory or omit --resume')
            can_resume = config.get('resume') and provenance.exists()
            provenance.write_text(json.dumps(job, indent=2) + '\n')
        else:
            frames = [config['frame']]
        rendered, skipped = [], []
        for frame in frames:
            path = output / f'{frame:06d}.png' if action == 'animation' else output
            if action == 'animation' and can_resume and path.is_file():
                image = None
                try:
                    image = bpy.data.images.load(str(path), check_existing=False)
                    scale = scene.render.resolution_percentage / 100
                    expected = [int(scene.render.resolution_x * scale), int(scene.render.resolution_y * scale)]
                    if list(image.size) == expected:
                        skipped.append(frame)
                        continue
                except RuntimeError:
                    print(f'Rerendering unreadable frame: {path}')
                finally:
                    if image is not None:
                        bpy.data.images.remove(image)
            scene.frame_set(frame)
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            if not path.is_file():
                raise RuntimeError(f'Render did not create expected file {path}')
            rendered.append(frame)
        if action == 'animation':
            (output / 'frames.json').write_text(json.dumps({'rendered': rendered, 'skipped': skipped,
                'fps': scene.render.fps / scene.render.fps_base, 'step': config['step']}, indent=2) + '\n')
    elif action == 'export':
        collection = config.get('collection')
        if collection:
            if collection not in bpy.data.collections:
                raise ValueError(f'Collection not found: {collection}')
            bpy.ops.object.select_all(action='DESELECT')
            for obj in bpy.data.collections[collection].all_objects:
                obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB',
                                  use_selection=bool(collection), export_cameras=False,
                                  export_lights=False, export_apply=True,
                                  export_animations=True, export_frame_range=True)
    elif action in ('inspect', 'inspect_glb'):
        if action == 'inspect_glb':
            bpy.ops.object.select_all(action='SELECT')
            bpy.ops.object.delete(use_global=False)
            bpy.ops.import_scene.gltf(filepath=config['source'])
            if not any(obj.type == 'MESH' for obj in bpy.context.scene.objects):
                raise ValueError('Imported GLB has no meshes')
        report = inventory()
        output.write_text(json.dumps(report, indent=2) + '\n')
        if report['missing_dependencies']:
            raise ValueError(f'Missing dependencies: {report["missing_dependencies"]}')
    else:
        raise ValueError(f'Unknown action {action}')


if __name__ == '__main__':
    main()
