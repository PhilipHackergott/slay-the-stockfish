"""Preview scene: imports the shipped glbs, swaps in mood stand-in materials, renders review shots.

Usage: run.sh preview.py 900 -- [game|orbit|close|all] [--fast]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402

GLB_BOARD = os.path.join(C.MODELS, "board", "board.glb")
GLB_CANDLE = os.path.join(C.MODELS, "props", "candelabra.glb")
GLB_ENV = os.path.join(C.MODELS, "env", "environment.glb")


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.type == 'MESH' and o.data.color_attributes:
            o.data.color_attributes[0].name = "ao"
    return new


# ----------------------------------------------------------------------------------------------- materials

def _nodes(m):
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return nt, bsdf


def _ao_mul(nt, color_socket_or_value, target, strength=1.0):
    """target <- color * mix(1, ao, strength)."""
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "ao"
    mix_ao = nt.nodes.new("ShaderNodeMix")
    mix_ao.data_type = 'RGBA'
    mix_ao.inputs[0].default_value = strength
    mix_ao.inputs[6].default_value = (1, 1, 1, 1)
    nt.links.new(attr.outputs["Color"], mix_ao.inputs[7])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = 'RGBA'
    mul.blend_type = 'MULTIPLY'
    mul.inputs[0].default_value = 1.0
    if isinstance(color_socket_or_value, tuple):
        mul.inputs[6].default_value = color_socket_or_value
    else:
        nt.links.new(color_socket_or_value, mul.inputs[6])
    nt.links.new(mix_ao.outputs[2], mul.inputs[7])
    nt.links.new(mul.outputs[2], target)


def _noise_color(nt, c0, c1, scale=4.0, detail=6.0, distortion=0.0, lo=0.35, hi=0.65, coord="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nz.inputs["Distortion"].default_value = distortion
    nt.links.new(tc.outputs[coord], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = lo
    ramp.color_ramp.elements[0].color = c0
    ramp.color_ramp.elements[1].position = hi
    ramp.color_ramp.elements[1].color = c1
    nt.links.new(nz.outputs["Fac"], ramp.inputs[0])
    return ramp.outputs[0]


def _marble(nt, base, vein, scale=1.3):
    """Veined marble: thin dark lines where distorted noise crosses 0.5."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale * 1.6
    nz.inputs["Detail"].default_value = 7.0
    nz.inputs["Roughness"].default_value = 0.55
    nz.inputs["Distortion"].default_value = 1.8
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    sub = nt.nodes.new("ShaderNodeMath")
    sub.operation = 'SUBTRACT'
    sub.inputs[1].default_value = 0.5
    nt.links.new(nz.outputs["Fac"], sub.inputs[0])
    ab = nt.nodes.new("ShaderNodeMath")
    ab.operation = 'ABSOLUTE'
    nt.links.new(sub.outputs[0], ab.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = vein
    ramp.color_ramp.elements[1].position = 0.03
    ramp.color_ramp.elements[1].color = base
    nt.links.new(ab.outputs[0], ramp.inputs[0])
    var = _noise_color(nt, tuple(c * 0.9 for c in base[:3]) + (1,), base, scale=2.0, detail=3)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    nt.links.new(ramp.outputs[0], mix.inputs[6])
    nt.links.new(var, mix.inputs[7])
    return mix.outputs[2]


def build_materials():
    defs = {}

    def mk(name, fn):
        defs[name] = fn

    def stone(c0, c1, rough=0.88, scale=3.0, ao=1.0):
        def f(nt, b):
            _ao_mul(nt, _noise_color(nt, c0, c1, scale=scale, detail=8, distortion=0.4), b.inputs["Base Color"], ao)
            b.inputs["Roughness"].default_value = rough
        return f

    def marble_light(nt, b):
        _ao_mul(nt, _marble(nt, (0.58, 0.565, 0.54, 1), (0.30, 0.30, 0.32, 1)), b.inputs["Base Color"], 0.8)
        b.inputs["Roughness"].default_value = 0.45

    def marble_dark(nt, b):
        _ao_mul(nt, _marble(nt, (0.028, 0.028, 0.034, 1), (0.11, 0.105, 0.12, 1), scale=1.1), b.inputs["Base Color"], 0.8)
        b.inputs["Roughness"].default_value = 0.38

    def emissive(col, strength, base=None):
        def f(nt, b):
            b.inputs["Base Color"].default_value = base or col
            b.inputs["Emission Color"].default_value = col
            b.inputs["Emission Strength"].default_value = strength
        return f

    def iron(nt, b):
        _ao_mul(nt, _noise_color(nt, (0.03, 0.03, 0.033, 1), (0.07, 0.065, 0.065, 1), scale=12), b.inputs["Base Color"])
        b.inputs["Metallic"].default_value = 0.85
        b.inputs["Roughness"].default_value = 0.5

    def wax(nt, b):
        b.inputs["Base Color"].default_value = (0.85, 0.78, 0.62, 1)
        b.inputs["Roughness"].default_value = 0.5
        b.inputs["Subsurface Weight"].default_value = 0.4
        b.inputs["Subsurface Radius"].default_value = (0.05, 0.03, 0.02)
        b.inputs["Emission Color"].default_value = (1.0, 0.6, 0.3, 1)
        b.inputs["Emission Strength"].default_value = 0.15

    def simple(col, rough=0.8, ao=1.0):
        def f(nt, b):
            _ao_mul(nt, col, b.inputs["Base Color"], ao)
            b.inputs["Roughness"].default_value = rough
        return f

    mk("board_light", marble_light)
    mk("board_dark", marble_dark)
    mk("board_rune", emissive((0.35, 0.55, 1.0, 1), 1.6, base=(0.1, 0.15, 0.3, 1)))
    mk("board_rim", stone((0.22, 0.215, 0.23, 1), (0.36, 0.35, 0.37, 1), rough=0.85, scale=5))
    mk("board_trim", stone((0.035, 0.035, 0.042, 1), (0.07, 0.07, 0.08, 1), rough=0.6, scale=6))
    mk("stone", stone((0.17, 0.17, 0.195, 1), (0.30, 0.30, 0.33, 1), scale=2.0))
    mk("stone_dark", stone((0.055, 0.055, 0.07, 1), (0.12, 0.12, 0.14, 1), scale=1.5))
    mk("floor_tiles", stone((0.10, 0.10, 0.12, 1), (0.22, 0.22, 0.25, 1), scale=1.2))
    mk("iron", iron)
    mk("candle_wax", wax)
    mk("candle_flame", emissive((1.0, 0.55, 0.16, 1), 25.0))
    mk("wood_dead", stone((0.06, 0.05, 0.045, 1), (0.14, 0.12, 0.10, 1), scale=8))
    mk("crow", simple((0.012, 0.012, 0.018, 1), rough=0.45))
    mk("moss", stone((0.035, 0.06, 0.025, 1), (0.09, 0.13, 0.05, 1), scale=6, rough=0.95))
    mk("bone", simple((0.55, 0.52, 0.43, 1), rough=0.7))
    for m in list(bpy.data.materials):
        base = m.name.split(".")[0]
        if base in defs:
            nt, b = _nodes(m)
            defs[base](nt, b)


# ----------------------------------------------------------------------------------------------- scene

def world_setup(fast=False):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("night")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.035, 0.035, 0.085, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.006, 0.006, 0.02, 1)
    el = ramp.color_ramp.elements.new(0.5)
    el.color = (0.06, 0.055, 0.13, 1)
    nt.links.new(ramp.outputs[0], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    if fast:
        return
    # EEVEE treats a world volume as infinite (it blocks the sun), so the haze is a bounded cube instead
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 20, 12))
    cube = bpy.context.active_object
    cube.name = "_haze"
    cube.scale = (220, 220, 70)
    m = bpy.data.materials.new("_haze")
    m.use_nodes = True
    mt = m.node_tree
    for n in list(mt.nodes):
        mt.nodes.remove(n)
    mo = mt.nodes.new("ShaderNodeOutputMaterial")
    vol = mt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.55, 0.58, 0.95, 1)
    vol.inputs["Density"].default_value = 0.0045
    vol.inputs["Anisotropy"].default_value = 0.35
    mt.links.new(vol.outputs[0], mo.inputs["Volume"])
    cube.data.materials.append(m)


def mist_layer():
    """Dense low fog sea under the island, thinning upward."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -16))
    cube = bpy.context.active_object
    cube.name = "_mist"
    cube.scale = (240, 240, 26)
    m = bpy.data.materials.new("_mist")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.04
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    ramp.color_ramp.elements[0].position = 0.2
    ramp.color_ramp.elements[0].color = (0.06, 0.06, 0.06, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1)
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    nt.links.new(ramp.outputs[0], mul.inputs[0])
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], mul.inputs[1])
    nt.links.new(mul.outputs[0], vol.inputs["Density"])
    vol.inputs["Color"].default_value = (0.45, 0.48, 0.85, 1)
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    cube.data.materials.append(m)


def moon_and_lights(objs, candle_objs):
    sc = bpy.context.scene
    md = next((o for o in objs if o.name.startswith("moon_dir")), None)
    if md is not None:
        q = md.matrix_world.to_quaternion()
    else:
        q = Vector((-0.45, 0.8, 0.4)).normalized().to_track_quat('Z', 'Y')
    sun_d = bpy.data.lights.new("moon", 'SUN')
    sun_d.color = (0.62, 0.66, 1.0)
    sun_d.energy = 1.6
    sun_d.angle = math.radians(1.5)
    sun = bpy.data.objects.new("moon", sun_d)
    sun.rotation_mode = 'QUATERNION'
    sun.rotation_quaternion = q
    sc.collection.objects.link(sun)
    # moon disc far away along +Z of the moon empty
    d = q @ Vector((0, 0, 1))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=26, location=d * 420, segments=32, ring_count=16)
    disc = bpy.context.active_object
    disc.name = "_moon_disc"
    m = bpy.data.materials.new("_moon")
    nt, b = _nodes(m)
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (0.75, 0.78, 1.0, 1)
    b.inputs["Emission Strength"].default_value = 6.0
    disc.data.materials.append(m)
    disc.visible_shadow = False
    # cool fill from the camera side (keeps the front of the altar readable)
    fill_d = bpy.data.lights.new("fill", 'SUN')
    fill_d.color = (0.45, 0.5, 0.95)
    fill_d.energy = 0.25
    fill_d.use_shadow = False
    fill = bpy.data.objects.new("fill", fill_d)
    fill.rotation_euler = (math.radians(55), 0, math.radians(10))
    sc.collection.objects.link(fill)
    # warm point light per flame
    for e in candle_objs:
        ld = bpy.data.lights.new("candle", 'POINT')
        ld.color = (1.0, 0.55, 0.22)
        ld.energy = 38.0
        ld.shadow_soft_size = 0.04
        lo = bpy.data.objects.new("candle_light", ld)
        lo.location = e.matrix_world.translation + Vector((0, 0, 0.03))
        sc.collection.objects.link(lo)


def place_candelabras(board_objs):
    flames = []
    spots = [o for o in board_objs if o.name.startswith("candelabra_") and o.type == 'EMPTY']
    if not os.path.exists(GLB_CANDLE):
        return flames
    for spot in sorted(spots, key=lambda o: o.name):
        new = import_glb(GLB_CANDLE)
        roots = [o for o in new if o.parent is None]
        for r in roots:
            r.matrix_world = spot.matrix_world @ r.matrix_world
        bpy.context.view_layer.update()
        flames += [o for o in new if o.name.startswith("flame_")]
    return flames


def camera(name, loc, target, fov_v_deg, lens_shift=(0, 0)):
    cd = bpy.data.cameras.new(name)
    cd.sensor_fit = 'VERTICAL'
    cd.angle_y = math.radians(fov_v_deg)
    cd.clip_start = 0.1
    cd.clip_end = 1000
    cd.shift_x, cd.shift_y = lens_shift
    cam = bpy.data.objects.new(name, cd)
    cam.location = loc
    direction = Vector(target) - Vector(loc)
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = direction.to_track_quat('-Z', 'Y')
    bpy.context.scene.collection.objects.link(cam)
    return cam


SHOTS = {
    "game": dict(loc=(0, -11, 9.5), target=(0, -0.5, 0), fov=45, res=(1600, 900), file="game_cam.png"),
    "orbit": dict(loc=(9.0, -10.7, 7.0), target=(-0.5, 2.0, 1.2), fov=50, res=(1600, 900), file="orbit_cam.png"),
    "close": dict(loc=(-2.0, -8.6, 1.6), target=(-4.6, -4.6, -0.1), fov=42, res=(1600, 900), file="board_close.png"),
    "back": dict(loc=(-9.0, 10.7, 7.0), target=(0.5, -2.0, 0.5), fov=50, res=(1600, 900), file="orbit_back.png"),
    "side": dict(loc=(14.0, 0.0, 7.0), target=(0, 0, 0), fov=50, res=(1600, 900), file="orbit_side.png"),
    "under": dict(loc=(10, -26, -8), target=(0, 0, -3), fov=50, res=(1600, 900), file="orbit_under.png"),
}


def render_settings(fast):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    ee = sc.eevee
    for attr, val in (("taa_render_samples", 16 if fast else 48), ("use_shadows", True),
                      ("volumetric_end", 160.0), ("volumetric_tile_size", '8' if fast else '4'),
                      ("volumetric_samples", 32 if fast else 64), ("use_volumetric_shadows", True),
                      ("shadow_ray_count", 1), ("shadow_step_count", 6), ("use_raytracing", not fast),
                      ("fast_gi_method", 'GLOBAL_ILLUMINATION')):
        try:
            setattr(ee, attr, val)
        except Exception:
            pass
    sc.view_settings.view_transform = 'AgX'
    try:
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception:
        pass
    sc.view_settings.exposure = 0.6
    sc.render.image_settings.file_format = 'PNG'
    sc.render.film_transparent = False


def main():
    args = C.script_args()
    fast = "--fast" in args
    shots = [a for a in args if not a.startswith("--")] or ["all"]
    if "all" in shots:
        shots = ["game", "orbit", "close"]
    C.reset()
    board = import_glb(GLB_BOARD)
    env = import_glb(GLB_ENV) if os.path.exists(GLB_ENV) else []
    flames = place_candelabras(board)
    flames += [o for o in env if o.name.startswith("candle_")]
    build_materials()
    world_setup(fast or "--novol" in args)
    if not fast and env and "--nomist" not in args:
        mist_layer()
    moon_and_lights(env, flames)
    render_settings(fast)
    sc = bpy.context.scene
    if "--noray" in args:
        sc.eevee.use_raytracing = False
    for s in shots:
        d = SHOTS[s]
        cam = camera(s, d["loc"], d["target"], d["fov"])
        sc.camera = cam
        sc.render.resolution_x, sc.render.resolution_y = d["res"]
        sc.render.resolution_percentage = 50 if fast else 100
        sc.render.filepath = os.path.join(C.BUILD, d["file"])
        bpy.ops.render.render(write_still=True)
        C.log("rendered", sc.render.filepath)


if __name__ == "__main__":
    main()
