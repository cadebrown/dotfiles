"""Procedural orbital compute diorama. Run inside Blender; all assets are local."""
from math import cos, pi, sin

import bpy
from mathutils import Vector


def build(samples=48):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    asset = bpy.data.collections.new('Orbital Compute')
    bpy.context.scene.collection.children.link(asset)
    studio = bpy.data.collections.new('Studio')
    bpy.context.scene.collection.children.link(studio)

    def own(obj, collection=asset):
        for existing in list(obj.users_collection):
            existing.objects.unlink(obj)
        collection.objects.link(obj)
        return obj

    def material(name, color, metal=0, roughness=.4, emission=0):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = (*color, 1)
        bsdf.inputs['Metallic'].default_value = metal
        bsdf.inputs['Roughness'].default_value = roughness
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
        mat.diffuse_color = (*color, 1)
        return mat

    graphite = material('Ceramic • midnight', (.024, .045, .065), .5, .28)
    silver = material('Machined titanium', (.38, .49, .52), .8, .23)
    teal = material('Signal • arctic mint', (.08, .8, .67), .3, .28, .4)
    amber = material('Signal • tangerine', (1, .24, .045), .25, .25, .2)
    core = material('Photon core', (.17, .88, .8), .35, .2, 2)
    floor_mat = material('Backdrop', (.075, .105, .145), .1, .6)
    white = material('Lettering', (.67, .83, .85), .2, .4)

    def finish(obj, name, mat):
        own(obj)
        obj.name = name
        obj.data.materials.append(mat)
        return obj

    def bevel(obj, amount=.07):
        modifier = obj.modifiers.new('Soft machined edge', 'BEVEL')
        modifier.width, modifier.segments = amount, 3
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        return obj

    def cube(name, location, scale, mat):
        bpy.ops.mesh.primitive_cube_add(size=1, location=location)
        obj = finish(bpy.context.object, name, mat)
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        return bevel(obj)

    def cylinder(name, location, radius, depth, mat, vertices=96):
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
        return bevel(finish(bpy.context.object, name, mat), .04)

    def ring(name, location, radius, tube, mat, rotation=(0, 0, 0)):
        bpy.ops.mesh.primitive_torus_add(major_segments=128, minor_segments=16,
                                       location=location, major_radius=radius, minor_radius=tube,
                                       rotation=rotation)
        obj = finish(bpy.context.object, name, mat)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        return obj

    cylinder('Floating plinth', (0, 0, .13), 3.1, .36, graphite)
    cylinder('Titanium reveal', (0, 0, .33), 3.03, .08, silver)
    cylinder('Ceramic platform', (0, 0, .41), 2.99, .1, graphite)
    ring('Platform signal circuit', (0, 0, .475), 2.82, .018, teal)
    ring('Inner instrument circuit', (0, 0, .48), 1.12, .013, teal)
    for i in range(36):
        angle = 2 * pi * i / 36
        tick = cube(f'Calibration {i:02d}', (2.66 * cos(angle), 2.66 * sin(angle), .485),
                    (.055, .12 if i % 3 == 0 else .055, .012), white)
        tick.rotation_euler.z = angle - pi / 2

    cylinder('Core mount', (0, 0, .66), .68, .4, silver)
    cylinder('Core base', (0, 0, .91), .56, .12, graphite)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=.57, location=(0, 0, 1.91))
    finish(bpy.context.object, 'Faceted photon processor', core)
    for index, (radius, rotation, mat) in enumerate([
        (1.15, (pi / 2.5, .25, .25), teal),
        (1.38, (.55, pi / 2.1, .4), amber),
        (1.59, (.24, .38, .15), silver),
    ]):
        obj = ring(f'Orbital bus {index + 1}', (0, 0, 1.91), radius, .043, mat, rotation)
        obj.keyframe_insert(data_path='rotation_euler', frame=1)
        obj.rotation_euler.z += 2 * pi
        obj.keyframe_insert(data_path='rotation_euler', frame=121)

    for i, angle in enumerate([.25, 1.9, 3.25, 4.65]):
        x, y = 2.1 * cos(angle), 2.1 * sin(angle)
        tower = cube(f'Compute module {i + 1}', (x, y, .97), (.55, .65, .98), graphite)
        tower.rotation_euler.z = angle
        cap = cube(f'Module crown {i + 1}', (x, y, 1.48), (.57, .67, .07), silver)
        cap.rotation_euler.z = angle
        for j in range(6):
            ox = .295 * cos(angle)
            oy = .295 * sin(angle)
            fin = cube(f'Heatsink {i + 1}.{j}', (x + ox, y + oy, .65 + j * .125), (.018, .5, .035), silver)
            fin.rotation_euler.z = angle
        led = cube(f'Status beacon {i + 1}', (x, y, 1.54), (.09, .32, .025), teal if i != 2 else amber)
        led.rotation_euler.z = angle

    for i in range(3):
        a = 4.4 + i * .12
        cylinder(f'Control switch {i + 1}', (2.2 * cos(a), 2.2 * sin(a), .55), .06, .09, amber)

    bpy.ops.object.text_add(location=(-1.04, -2.45, .483))
    text = bpy.context.object
    finish(text, 'Platform inscription', white)
    text.data.body = 'O R B I T A L   /   0 1'
    text.data.size = .15
    text.data.extrude = .002
    bpy.ops.object.convert(target='MESH')

    plane = cube('Studio ground', (0, 0, -.22), (200, 200, .08), floor_mat)
    own(plane, studio)

    def aim(obj, target):
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

    for name, location, energy, color, size in [
        ('Large soft key', (1, -4, 8), 1500, (.73, .88, 1), 5),
        ('Arctic rim', (-4, 1, 5), 1800, (.3, 1, .85), 4),
        ('Warm rim', (4, 5, 6), 2200, (1, .58, .32), 3),
        ('Front fill', (1, -5, 3), 250, (.7, .82, 1), 3),
    ]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.color, data.shape, data.size = energy, color, 'DISK', size
        obj = bpy.data.objects.new(name, data)
        studio.objects.link(obj)
        obj.location = location
        aim(obj, (0, 0, 1))
    camera_data = bpy.data.cameras.new('Hero camera')
    camera = bpy.data.objects.new('Hero camera', camera_data)
    studio.objects.link(camera)
    camera.location = (7, -10, 8)
    aim(camera, (0, 0, 1.05))
    camera_data.type, camera_data.ortho_scale = 'ORTHO', 8.9
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.samples, scene.cycles.use_denoising = samples, True
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.world.color = (.12, .12, .12)
    scene.view_settings.view_transform = 'AgX'
    scene.frame_start, scene.frame_end, scene.render.fps = 1, 120, 24
    scene.frame_set(1)
    scene['description'] = 'Procedural orbital compute diorama; no external assets. Animated orbital buses.'
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = None
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_perspective = 'CAMERA'
                area.spaces.active.shading.type = 'MATERIAL'


if __name__ == '__main__':
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--samples', type=int, default=48)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    build(samples=args.samples)
    bpy.ops.wm.save_as_mainfile(filepath=args.output)
