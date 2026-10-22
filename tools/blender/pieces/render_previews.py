"""Review renders from the exported glbs: line-ups, animation film strips, UI portraits.

Blender --background --factory-startup --python render_previews.py -- [--what lineup,anim,portraits] [--samples 96]
Materials are swapped by slot name, like the game does, so this also checks the export.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402

D = math.radians
LINEUP = ("king", "queen", "bishop", "knight", "rook", "pawn")
TURN = {"knight": D(58), "bishop": D(22)}
DEFAULT_TURN = D(28)


# ---------------------------------------------------------------- node helpers

class Graph:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.node("ShaderNodeOutputMaterial")
        self.bsdf = self.node("ShaderNodeBsdfPrincipled")
        self.link(self.bsdf.outputs[0], self.out.inputs["Surface"])
        self.coord = self.node("ShaderNodeTexCoord").outputs["Object"]
        self.ao = self.node("ShaderNodeVertexColor").outputs["Color"]

    def node(self, kind, **props):
        n = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def _in(self, n, idx, v):
        if hasattr(v, "is_linked") or hasattr(v, "node"):
            self.link(v, n.inputs[idx])
        else:
            n.inputs[idx].default_value = v

    def noise(self, vec, scale, detail=4.0, rough=0.55, out="Fac"):
        n = self.node("ShaderNodeTexNoise")
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n.outputs[out]

    def voronoi(self, vec, scale, feature, out="Distance", randomness=1.0):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = randomness
        return n.outputs[out]

    def maprange(self, v, a, b, c=0.0, d=1.0):
        n = self.node("ShaderNodeMapRange", clamp=True)
        self._in(n, "Value", v)
        n.inputs["From Min"].default_value = a
        n.inputs["From Max"].default_value = b
        n.inputs["To Min"].default_value = c
        n.inputs["To Max"].default_value = d
        return n.outputs["Result"]

    def math(self, op, a, b=0.0):
        n = self.node("ShaderNodeMath", operation=op)
        self._in(n, 0, a)
        self._in(n, 1, b)
        return n.outputs[0]

    def vmath(self, op, a, b=(0.0, 0.0, 0.0), scale=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self._in(n, 0, a)
        self._in(n, 1, b)
        if scale is not None:
            n.inputs["Scale"].default_value = scale
        return n.outputs["Vector"]

    def mix(self, fac, a, b, blend='MIX'):
        n = self.node("ShaderNodeMix", data_type='RGBA', blend_type=blend, clamp_result=True)
        self._in(n, "Factor", fac)
        self._in(n, 6, a)
        self._in(n, 7, b)
        return n.outputs[2]

    def bump(self, height, strength, distance=0.02, normal=None):
        n = self.node("ShaderNodeBump")
        self._in(n, "Height", height)
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = distance
        if normal is not None:
            self._in(n, "Normal", normal)
        return n.outputs["Normal"]

    def set(self, name, v):
        self._in(self.bsdf, name, v)


def warp(g, scale, amount):
    offs = g.vmath('SUBTRACT', g.noise(g.coord, scale, 3.0, out="Color"), (0.5, 0.5, 0.5))
    return g.vmath('ADD', g.coord, g.vmath('SCALE', offs, scale=amount))


def cracks(g, scale, width, coverage, stretch=1.0):
    co = warp(g, 2.5, 0.22)
    if stretch != 1.0:
        co = g.vmath('MULTIPLY', co, (1.0, 1.0, stretch))
    d = g.voronoi(co, scale, 'DISTANCE_TO_EDGE')
    line = g.maprange(d, 0.0, width, 1.0, 0.0)
    mask = g.maprange(g.noise(g.coord, 2.2, 3.0), 0.5 - coverage, 0.5 - coverage + 0.12)
    return g.math('MULTIPLY', line, mask)


def mat_bone():
    m = bpy.data.materials.new("player_body")
    g = Graph(m)
    big = g.noise(g.coord, 2.4, 5.0)
    tone = g.mix(g.maprange(big, 0.35, 0.65), (0.50, 0.44, 0.33, 1), (0.36, 0.31, 0.23, 1))
    stain = g.maprange(g.noise(g.coord, 1.3, 3.0), 0.52, 0.72, 0.0, 0.5)
    tone = g.mix(stain, tone, (0.27, 0.20, 0.12, 1))
    crack = cracks(g, 5.5, 0.022, 0.08)
    tone = g.mix(g.math('MULTIPLY', crack, 0.85), tone, (0.10, 0.07, 0.045, 1))
    tone = g.mix(1.0, tone, g.ao, 'MULTIPLY')
    g.set("Base Color", tone)
    fine = g.noise(g.coord, 22.0, 8.0)
    g.set("Roughness", g.maprange(fine, 0.3, 0.7, 0.48, 0.64))
    g.set("Subsurface Weight", 0.06)
    g.set("Subsurface Radius", (0.02, 0.012, 0.008))
    h = g.math('SUBTRACT', g.math('MULTIPLY', fine, 0.25), crack)
    g.set("Normal", g.bump(h, 0.35, 0.01))
    return m


def mat_silver():
    m = bpy.data.materials.new("player_trim")
    g = Graph(m)
    n = g.noise(g.coord, 9.0, 6.0)
    ao_v = g.node("ShaderNodeRGBToBW")
    g.link(g.ao, ao_v.inputs[0])
    tarnish = g.math('ADD', g.maprange(ao_v.outputs[0], 0.95, 0.45), g.maprange(n, 0.5, 0.8, 0.0, 0.35))
    tarnish = g.math('MINIMUM', tarnish, 1.0)
    g.set("Base Color", g.mix(g.math('MINIMUM', g.math('ADD', tarnish, 0.15), 1.0), (0.74, 0.73, 0.70, 1),
                              (0.22, 0.20, 0.17, 1)))
    g.set("Metallic", 1.0)
    g.set("Roughness", g.maprange(tarnish, 0.0, 1.0, 0.26, 0.62))
    g.set("Normal", g.bump(g.noise(g.coord, 40.0, 4.0), 0.08, 0.005))
    return m


def mat_glow(name, color, strength):
    m = bpy.data.materials.new(name)
    g = Graph(m)
    g.set("Base Color", (*color, 1.0))
    g.set("Emission Color", (*color, 1.0))
    g.set("Emission Strength", strength)
    g.set("Roughness", 0.25)
    return m


def mat_obsidian():
    m = bpy.data.materials.new("engine_body")
    g = Graph(m)
    cell = g.voronoi(g.coord, 17.0, 'F1', out="Color")
    geo = g.node("ShaderNodeNewGeometry").outputs["Normal"]
    tilt = g.vmath('SCALE', g.vmath('SUBTRACT', cell, (0.5, 0.5, 0.5)), scale=0.5)
    facet = g.vmath('NORMALIZE', g.vmath('ADD', geo, tilt))
    cell_v = g.node("ShaderNodeRGBToBW")
    g.link(cell, cell_v.inputs[0])
    major = cracks(g, 2.6, 0.016, 0.10, stretch=0.45)
    minor = g.math('MULTIPLY', cracks(g, 7.0, 0.010, 0.0), 0.5)
    crack = g.math('MAXIMUM', major, minor)
    hot = g.maprange(crack, 0.1, 0.85)
    rock = g.mix(cell_v.outputs[0], (0.008, 0.007, 0.009, 1), (0.026, 0.023, 0.025, 1))
    g.set("Base Color", g.mix(1.0, g.mix(hot, rock, (0.35, 0.06, 0.01, 1)), g.ao, 'MULTIPLY'))
    g.set("Roughness", g.math('ADD', g.maprange(cell_v.outputs[0], 0.0, 1.0, 0.16, 0.30),
                              g.math('MULTIPLY', hot, 0.4)))
    g.set("Specular IOR Level", 0.5)
    g.set("Coat Weight", 0.12)
    g.set("Coat Roughness", 0.15)
    g.set("Emission Color", (1.0, 0.30, 0.05, 1.0))
    g.set("Emission Strength", g.math('MULTIPLY', hot, 9.0))
    g.set("Normal", g.bump(crack, -0.6, 0.01, normal=facet))
    return m


def mat_iron():
    m = bpy.data.materials.new("engine_trim")
    g = Graph(m)
    n = g.noise(g.coord, 12.0, 6.0)
    g.set("Base Color", g.mix(g.maprange(n, 0.4, 0.7), (0.13, 0.12, 0.12, 1), (0.06, 0.055, 0.055, 1)))
    g.set("Metallic", 1.0)
    g.set("Roughness", g.maprange(n, 0.3, 0.7, 0.35, 0.6))
    g.set("Normal", g.bump(g.noise(g.coord, 35.0, 5.0), 0.15, 0.006))
    return m


THEMES = {}


def theme(name):
    if name not in THEMES:
        if name == "player":
            THEMES[name] = {"piece_body": mat_bone(), "piece_trim": mat_silver(),
                            "piece_glow": mat_glow("player_glow", (0.02, 0.24, 1.0), 4.0)}
        else:
            THEMES[name] = {"piece_body": mat_obsidian(), "piece_trim": mat_iron(),
                            "piece_glow": mat_glow("engine_glow", (1.0, 0.20, 0.02), 4.5)}
    return THEMES[name]


def apply_theme(ob, name):
    mats = theme(name)
    if "fb_slots" not in ob:
        ob["fb_slots"] = [s.material.name.split(".")[0] if s.material else "" for s in ob.material_slots]
    for slot, key in zip(ob.material_slots, ob["fb_slots"]):
        if key in mats:
            slot.material = mats[key]


# ---------------------------------------------------------------- scene

def import_piece(name, keep_anim=False):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(C.MODELS, name + ".glb"))
    ob = [o for o in bpy.data.objects if o not in before and o.type == 'MESH'][0]
    if not keep_anim:
        ob.animation_data_clear()
        ob.matrix_world = Matrix.Identity(4)
    return ob


def setup(res, samples, transparent=False):
    scene = C.reset_scene()
    scene.render.engine = 'CYCLES'
    C.use_gpu(scene)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA' if transparent else 'RGB'
    world = bpy.data.worlds.new("w")
    world.color = (0.03, 0.034, 0.045)
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.028, 0.032, 0.044, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    return scene


def bloom(scene, strength=0.5):
    tree = bpy.data.node_groups.new("comp", "CompositorNodeTree")
    tree.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    scene.compositing_node_group = tree
    rl = tree.nodes.new("CompositorNodeRLayers")
    gl = tree.nodes.new("CompositorNodeGlare")
    gl.inputs["Type"].default_value = 'Bloom'
    gl.inputs["Quality"].default_value = 'High'
    gl.inputs["Threshold"].default_value = 1.2
    gl.inputs["Strength"].default_value = strength
    gl.inputs["Size"].default_value = 0.55
    out = tree.nodes.new("NodeGroupOutput")
    tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
    tree.links.new(gl.outputs["Image"], out.inputs[0])


def aim(ob, target):
    d = Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def area(name, loc, target, energy, size, color):
    lt = bpy.data.lights.new(name, 'AREA')
    lt.energy = energy
    lt.size = size
    lt.color = color
    ob = bpy.data.objects.new(name, lt)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    aim(ob, target)
    return ob


def rig(centre=(0, 0, 0.7), scale=1.0, gain=1.0):
    cx, cy, cz = centre
    scale_e = gain * scale ** 2
    area("key", (cx - 3.2 * scale, cy - 4.2 * scale, cz + 3.6 * scale), centre, 900 * scale_e, 3.0 * scale,
         (1.0, 0.94, 0.86))
    area("rim", (cx + 3.4 * scale, cy + 3.8 * scale, cz + 2.6 * scale), centre, 1300 * scale_e, 2.2 * scale,
         (0.55, 0.72, 1.0))
    area("rim2", (cx - 3.6 * scale, cy + 3.2 * scale, cz + 1.8 * scale), centre, 500 * scale_e, 2.0 * scale,
         (0.6, 0.75, 1.0))
    area("fill", (cx + 4.5 * scale, cy - 3.5 * scale, cz + 0.6 * scale), centre, 140 * scale_e, 4.0 * scale,
         (0.8, 0.85, 1.0))


def camera(loc, target, lens):
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    ob = bpy.data.objects.new("cam", cam)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    aim(ob, target)
    bpy.context.scene.camera = ob
    return ob


def cyclorama(color=(0.006, 0.007, 0.009), flat=7.0, radius=3.0):
    """Floor that curves up into a back wall, so the background reads as a soft studio gradient."""
    import bmesh
    bm = bmesh.new()
    prof = [(-14.0, 0.0), (flat, 0.0)]
    for i in range(1, 9):
        a = D(90) * i / 8
        prof.append((flat + radius * math.sin(a), radius - radius * math.cos(a)))
    prof.append((flat + radius, 14.0))
    rows = [[bm.verts.new((x, y, z)) for (y, z) in prof] for x in (-24.0, 24.0)]
    for i in range(len(prof) - 1):
        bm.faces.new((rows[0][i], rows[1][i], rows[1][i + 1], rows[0][i + 1]))
    me = bpy.data.meshes.new("cyc")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new("cyc")
    b = C.principled(mat)
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Specular IOR Level"].default_value = 0.08
    me.materials.append(mat)
    ob = bpy.data.objects.new("cyc", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


# ---------------------------------------------------------------- jobs

def lineup(theme_name, samples):
    scene = setup((1280, 720), samples)
    bloom(scene, 0.45)
    cyclorama()
    rig((0, 0, 0.7), 1.6)
    for i, name in enumerate(LINEUP):
        ob = import_piece(name)
        apply_theme(ob, theme_name)
        ob.matrix_world = Matrix.Translation((-2.55 + i * 1.02, 0, 0)) @ \
            Matrix.Rotation(TURN.get(name, DEFAULT_TURN), 4, 'Z')
    camera((0.0, -8.4, 2.35), (0.0, 0.0, 0.66), 44)
    render(os.path.join(C.BUILD, "lineup_%s.png" % theme_name))


def label(text, loc, size=0.13):
    cu = bpy.data.curves.new("lbl", 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    ob = bpy.data.objects.new("lbl", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (D(90), 0, 0)
    mat = bpy.data.materials.new("lbl")
    b = C.principled(mat)
    b.inputs["Base Color"].default_value = (0.6, 0.65, 0.75, 1)
    b.inputs["Emission Color"].default_value = (0.6, 0.65, 0.75, 1)
    b.inputs["Emission Strength"].default_value = 0.6
    cu.materials.append(mat)


STRIPS = {
    "move": ("pawn", (0.0, 0.08, 0.17, 0.27, 0.40, 0.48)),
    "capture": ("pawn", (0.0, 0.15, 0.30, 0.45, 0.62, 0.78)),
    "leap": ("knight", (0.0, 0.10, 0.22, 0.36, 0.55, 0.65)),
    "drop": ("pawn", (0.0, 0.15, 0.30, 0.36, 0.40, 0.50)),
    "spawn": ("pawn", (0.0, 0.10, 0.20, 0.30, 0.40, 0.50)),
}


def strip(clip, samples, theme_name="player"):
    piece, times = STRIPS[clip]
    scene = setup((1920, 640), samples)
    bloom(scene, 0.35)
    cyclorama()
    src = import_piece(piece, keep_anim=True)
    ad = src.animation_data
    track = next(t for t in ad.nla_tracks if t.name == clip)
    act = track.strips[0].action
    for t in ad.nla_tracks:
        t.mute = True
    ad.action = act
    if act.slots:
        ad.action_slot = act.slots[0]
    f0 = act.frame_range[0]
    spacing = 1.3
    x0 = -spacing * (len(times) - 1) / 2
    for i, t in enumerate(times):
        scene.frame_set(int(round(f0 + t * C.FPS)))
        pose = src.matrix_world.copy()
        dup = bpy.data.objects.new("%s_%d" % (piece, i), src.data)
        scene.collection.objects.link(dup)
        dup.matrix_world = Matrix.Translation((x0 + i * spacing, 0, 0)) @ Matrix.Rotation(D(90), 4, 'Z') @ pose
        apply_theme(dup, theme_name)
        label("%.2f s" % t, (x0 + i * spacing, -0.75, 0.01))
    src.hide_render = True
    top = {"leap": 2.3, "drop": 3.15}.get(clip, 1.35)
    dist = max(10.5, top * 4.6)
    rig((0, 0, top / 2), 2.0 * dist / 10.5)
    camera((0.0, -dist, top * 0.55 + 0.9), (0.0, 0.0, top * 0.44), 50)
    render(os.path.join(C.BUILD, "anim_%s.png" % clip))


def turnaround(piece, theme_name, samples, elev=38.0):
    """Review sheet: the piece at 0/45/90/180 deg under a game-like elevated camera."""
    scene = setup((1600, 560), samples)
    bloom(scene, 0.35)
    cyclorama()
    rig((0, 0, 0.7), 1.6)
    src = import_piece(piece)
    apply_theme(src, theme_name)
    for i, turn in enumerate((0, 45, 90, 180)):
        ob = src if i == 0 else bpy.data.objects.new("%s_%d" % (piece, i), src.data)
        if i:
            scene.collection.objects.link(ob)
        ob.matrix_world = Matrix.Translation((-1.65 + i * 1.1, 0, 0)) @ Matrix.Rotation(D(turn), 4, 'Z')
    h = C.HEIGHTS[piece]
    e = D(elev)
    target = Vector((0, 0, h * 0.45))
    camera(target + Vector((0, -math.cos(e), math.sin(e))) * 7.0, target, 50)
    render(os.path.join(C.BUILD, "turn_%s_%s.png" % (piece, theme_name)))


def portraits(samples):
    scene = setup((512, 512), samples, transparent=True)
    rig((0, 0, 0.7), 1.3, gain=0.62)
    cam = camera((0, 0, 0), (0, 0, 0), 85)
    dist = 5.1
    elev = D(16)
    for name in C.PIECES:
        ob = import_piece(name)
        ob.matrix_world = Matrix.Rotation(TURN.get(name, DEFAULT_TURN), 4, 'Z')
        pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        centre = sum(pts, Vector()) / 8
        cam.location = centre + Vector((0, -math.cos(elev), math.sin(elev))) * dist
        aim(cam, centre)
        for th in ("player", "engine"):
            apply_theme(ob, th)
            render(os.path.join(C.PORTRAITS, "%s_%s.png" % (th, name)))
        bpy.data.objects.remove(ob)
    portrait_sheet()


def portrait_sheet():
    """Review sheet: all portraits over the game's dark slate, player row above engine row."""
    import numpy as np
    tile = 512
    sheet = np.zeros((2 * tile, 6 * tile, 4), dtype=np.float32)
    sheet[...] = (0.035, 0.04, 0.05, 1.0)
    for r, th in enumerate(("engine", "player")):  # Blender images are stored bottom-up
        for c, name in enumerate(LINEUP):
            im = bpy.data.images.load(os.path.join(C.PORTRAITS, "%s_%s.png" % (th, name)))
            im.colorspace_settings.name = 'Non-Color'
            px = np.array(im.pixels[:], dtype=np.float32).reshape(tile, tile, 4)
            a = px[..., 3:4]
            cell = sheet[r * tile:(r + 1) * tile, c * tile:(c + 1) * tile]
            cell[..., :3] = px[..., :3] * a + cell[..., :3] * (1 - a)
            bpy.data.images.remove(im)
    out = bpy.data.images.new("sheet", 6 * tile, 2 * tile, alpha=False)
    out.colorspace_settings.name = 'Non-Color'
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(C.BUILD, "portraits_sheet.png")
    out.file_format = 'PNG'
    out.save()
    print("RENDERED", out.filepath_raw)


def main():
    args = C.script_args()
    what = args[args.index("--what") + 1].split(",") if "--what" in args else ["lineup", "anim", "portraits"]
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 96
    clips = args[args.index("--clips") + 1].split(",") if "--clips" in args else list(STRIPS)
    if "lineup" in what:
        for th in ("player", "engine"):
            THEMES.clear()
            lineup(th, samples)
    if "anim" in what:
        for clip in clips:
            THEMES.clear()
            strip(clip, max(32, samples // 2))
    if "portraits" in what:
        THEMES.clear()
        portraits(samples)
    if "turn" in what:
        pieces = args[args.index("--pieces") + 1].split(",") if "--pieces" in args else list(C.PIECES)
        themes = args[args.index("--themes") + 1].split(",") if "--themes" in args else ["player"]
        for piece in pieces:
            for th in themes:
                THEMES.clear()
                turnaround(piece, th, samples)


if __name__ == "__main__":
    main()
