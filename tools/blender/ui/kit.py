"""Helpers for the UI texture kit (run inside Blender): scene, lights, procedural materials, bmesh shapes, masks.

Units: 1 Blender unit = 1 texture pixel at 1x (renders are SCALE x). Origin = texture centre, +X right, +Y up
(image up), +Z towards the top-down orthographic camera; relief heights are in pixels as well.
Objects are never transformed: geometry is built in place, so Object coordinates = texture pixels.
Material state (hover glow, rust, ...) lives in CTRL value nodes, so one scene renders every state.
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RAW = os.path.join(ROOT, "build", "ui", "raw")
SCALE = 2


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def lin8(rgb):
    return lin(tuple(v / 255.0 for v in rgb))


SOUL = lin8((0x6f, 0xb8, 0xff))
EMBER = lin8((0xff, 0x7a, 0x33))
SILVER = (0.52, 0.52, 0.54)
IRON_DARK = (0.016, 0.016, 0.018)

DEFAULTS = {"glow": 0.0, "glow_col": SOUL, "rust": 0.0, "dark": 0.0, "heat": 0.0, "face_glow": 0.0}
CTRL = {}


def log(*a):
    print("[ui]", *a, flush=True)


# ----------------------------------------------------------------------------------------------- scene

def init_gpu():
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == 'METAL'
        # scene-specialised Metal kernels recompile for every new material set (~1 min each): not worth it here
        prefs.kernel_optimization_level = 'OFF'
        return True
    except Exception as e:  # CPU fallback
        log("GPU unavailable:", e)
        return False


def clear():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.metaballs, bpy.data.materials, bpy.data.lights,
                 bpy.data.cameras, bpy.data.worlds):
        for x in list(coll):
            coll.remove(x)
    for im in list(bpy.data.images):
        if im.type == 'IMAGE':
            bpy.data.images.remove(im)
    CTRL.clear()


def link(o):
    bpy.context.scene.collection.objects.link(o)
    return o


def to_light(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def sun(name, az, el, energy, angle, shadow=True, color=(1, 1, 1)):
    lt = bpy.data.lights.new(name, 'SUN')
    lt.energy = energy
    lt.angle = math.radians(angle)
    lt.color = color
    lt.use_shadow = shadow
    o = bpy.data.objects.new(name, lt)
    o.rotation_euler = (-to_light(az, el)).to_track_quat('-Z', 'Y').to_euler()
    return link(o)


KEY_AZ, KEY_EL = 135.0, 38.0


def scene(W, H, samples=160, key=3.0, fill=0.16, env=0.38):
    """Cycles, transparent film, ortho top-down camera framing W x H px, grazing key from the top-left."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'GPU'
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.004
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 3
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 3.0
    sc.cycles.seed = 7
    sc.render.film_transparent = True
    sc.render.resolution_x = int(W * SCALE)
    sc.render.resolution_y = int(H * SCALE)
    sc.render.resolution_percentage = 100
    sc.render.use_persistent_data = True
    sc.render.dither_intensity = 0.0
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.render.image_settings.compression = 15
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = max(W, H)
    cam.clip_start = 1.0
    cam.clip_end = 4000.0
    co = link(bpy.data.objects.new("cam", cam))
    co.location = (0, 0, 1000)
    sc.camera = co
    sun("key", KEY_AZ, KEY_EL, key, 4.0, color=(1.0, 0.97, 0.93))
    sun("fill", -45.0, 58.0, fill, 35.0, shadow=False, color=(0.78, 0.85, 1.0))
    world(env)
    return sc


def world(strength):
    """Dark environment with a soft box towards the key: gives metals and bevels something to reflect."""
    w = bpy.data.worlds.new("env")
    bpy.context.scene.world = w
    if w.node_tree is None:
        w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    nt.links.new(tc.outputs["Generated"], dot.inputs[0])
    dot.inputs[1].default_value = to_light(KEY_AZ, 50.0)
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.clamp = True
    nt.links.new(dot.outputs["Value"], mr.inputs["Value"])
    mr.inputs["From Min"].default_value = 0.86
    mr.inputs["From Max"].default_value = 1.0
    mr.inputs["To Min"].default_value = 0.012
    mr.inputs["To Max"].default_value = 1.6
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = 'POWER'
    nt.links.new(mr.outputs["Result"], pw.inputs[0])
    pw.inputs[1].default_value = 1.6
    col = nt.nodes.new("ShaderNodeMix")
    col.data_type = 'RGBA'
    col.blend_type = 'MULTIPLY'
    col.inputs["Factor"].default_value = 1.0
    nt.links.new(pw.outputs[0], col.inputs[6])
    col.inputs[7].default_value = (0.85, 0.9, 1.0, 1)
    nt.links.new(col.outputs[2], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs["Surface"])


def ctrl_apply(state):
    """Set every control to the state's value (or its default); '_hide' lists object-name prefixes to hide."""
    for k, socks in CTRL.items():
        v = state.get(k, DEFAULTS[k])
        for s in socks:
            s.default_value = (*v[:3], 1.0) if isinstance(v, (tuple, list)) else v
    hide = state.get("_hide", ())
    for o in bpy.data.objects:
        o.hide_render = any(o.name.startswith(h) for h in hide)


def render(name):
    os.makedirs(RAW, exist_ok=True)
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(RAW, name + ".png")
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------------------------------- materials

class G:
    """Tiny shader-graph builder around a Principled BSDF."""

    def __init__(self, name):
        m = bpy.data.materials.new(name)
        if m.node_tree is None:
            m.use_nodes = True
        self.m = m
        self.nt = m.node_tree
        self.nt.nodes.clear()
        self.out = self.node("ShaderNodeOutputMaterial")
        self.bsdf = self.node("ShaderNodeBsdfPrincipled")
        self.link(self.bsdf.outputs[0], self.out.inputs["Surface"])
        self.tc = self.node("ShaderNodeTexCoord")
        self.geo = self.node("ShaderNodeNewGeometry")

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

    def set(self, name, v):
        self._in(self.bsdf, name, v)

    def co(self, aniso=None, offset=None):
        v = self.tc.outputs["Object"]
        if aniso is not None:
            v = self.vmath('MULTIPLY', v, aniso)
        if offset is not None:
            v = self.vmath('ADD', v, offset)
        return v

    def value(self, ctrl):
        n = self.node("ShaderNodeValue")
        n.outputs[0].default_value = DEFAULTS[ctrl]
        CTRL.setdefault(ctrl, []).append(n.outputs[0])
        return n.outputs[0]

    def color(self, ctrl):
        n = self.node("ShaderNodeRGB")
        n.outputs[0].default_value = (*DEFAULTS[ctrl][:3], 1.0)
        CTRL.setdefault(ctrl, []).append(n.outputs[0])
        return n.outputs[0]

    def noise(self, vec, scale, detail=4.0, rough=0.55, out="Fac", w=None):
        n = self.node("ShaderNodeTexNoise")
        if w is not None:
            n.noise_dimensions = '4D'
            self._in(n, "W", w)
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n.outputs[out]

    def voronoi(self, vec, scale, feature, out="Distance", rand=1.0, w=None, smooth=None):
        n = self.node("ShaderNodeTexVoronoi", feature=feature)
        if w is not None:
            n.voronoi_dimensions = '4D'
            self._in(n, "W", w)
        self._in(n, "Vector", vec)
        n.inputs["Scale"].default_value = scale
        n.inputs["Randomness"].default_value = rand
        if smooth is not None:
            n.inputs["Smoothness"].default_value = smooth
        return n.outputs[out]

    def maprange(self, v, a, b, c=0.0, d=1.0, clamp=True):
        n = self.node("ShaderNodeMapRange", clamp=clamp)
        self._in(n, "Value", v)
        n.inputs["From Min"].default_value = a
        n.inputs["From Max"].default_value = b
        n.inputs["To Min"].default_value = c
        n.inputs["To Max"].default_value = d
        return n.outputs["Result"]

    def math(self, op, a, b=0.0, c=None):
        n = self.node("ShaderNodeMath", operation=op)
        self._in(n, 0, a)
        self._in(n, 1, b)
        if c is not None:
            self._in(n, 2, c)
        return n.outputs[0]

    def mul(self, a, b):
        return self.math('MULTIPLY', a, b)

    def add(self, a, b):
        return self.math('ADD', a, b)

    def vmath(self, op, a, b=(0.0, 0.0, 0.0), scale=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self._in(n, 0, a)
        self._in(n, 1, b)
        if scale is not None:
            self._in(n, "Scale", scale)
        out = "Value" if op in ('DOT_PRODUCT', 'LENGTH', 'DISTANCE') else "Vector"
        return n.outputs[out]

    def mix(self, fac, a, b, blend='MIX'):
        n = self.node("ShaderNodeMix", data_type='RGBA', blend_type=blend, clamp_result=True)
        self._in(n, "Factor", fac)
        self._in(n, 6, a)
        self._in(n, 7, b)
        return n.outputs[2]

    def mixf(self, fac, a, b):
        n = self.node("ShaderNodeMix", data_type='FLOAT')
        self._in(n, "Factor", fac)
        self._in(n, 2, a)
        self._in(n, 3, b)
        return n.outputs[0]

    def sep(self, vec):
        n = self.node("ShaderNodeSeparateXYZ")
        self._in(n, 0, vec)
        return n.outputs

    def comb(self, x, y, z):
        n = self.node("ShaderNodeCombineXYZ")
        self._in(n, 0, x)
        self._in(n, 1, y)
        self._in(n, 2, z)
        return n.outputs[0]

    def slope(self):
        """0 on faces looking at the camera, towards 1 on walls."""
        return self.math('SUBTRACT', 1.0, self.sep(self.geo.outputs["Normal"])[2])

    def ao(self, dist, inside=False):
        n = self.node("ShaderNodeAmbientOcclusion", samples=8, inside=inside)
        n.inputs["Distance"].default_value = dist
        return n.outputs["AO"]

    def bump(self, height, strength, dist=1.0, normal=None):
        n = self.node("ShaderNodeBump")
        self._in(n, "Height", height)
        n.inputs["Strength"].default_value = strength
        n.inputs["Distance"].default_value = dist
        if normal is not None:
            self._in(n, "Normal", normal)
        return n.outputs["Normal"]

    def mask(self, mk, repeat=False):
        """Sample a Mask over the object: returns (R, G, B) float sockets."""
        img = mk.image(repeat)
        v = self.vmath('SUBTRACT', self.tc.outputs["Object"], (mk.x0, mk.y0, 0.0))
        v = self.vmath('DIVIDE', v, (mk.w, mk.h, 1.0))
        n = self.node("ShaderNodeTexImage", image=img, interpolation='Linear',
                      extension='REPEAT' if repeat else 'EXTEND')
        self.link(v, n.inputs["Vector"])
        s = self.node("ShaderNodeSeparateColor")
        self.link(n.outputs["Color"], s.inputs[0])
        return s.outputs[0], s.outputs[1], s.outputs[2]

    def emit(self, color, strength):
        self.set("Emission Color", color)
        self.set("Emission Strength", strength)


def _scale_col(c, k):
    return (c[0] * k, c[1] * k, c[2] * k, 1.0)


def mat_iron(name, aniso=None, seed=0.0, tone=1.0, wear=1.0, dent=15.0, glow_mask=None):
    """Blackened hand-forged iron: hammer dents, oxide mottling, worn silver on slopes, optional rust."""
    g = G(name)
    co = g.co(aniso, (seed * 37.1, seed * 11.3, seed * 5.7))
    cel = g.voronoi(co, 1.0 / dent, 'SMOOTH_F1', smooth=0.5)
    cel2 = g.voronoi(co, 2.3 / dent, 'SMOOTH_F1', smooth=0.5)
    big = g.noise(co, 1.0 / 55.0, 4.0, 0.55)
    mid = g.noise(co, 1.0 / 12.0, 5.0, 0.6)
    fine = g.noise(co, 1.0 / 2.2, 3.0, 0.5)
    base = g.mix(g.maprange(big, 0.3, 0.7), _scale_col(IRON_DARK, 0.45 * tone), _scale_col(IRON_DARK, 1.35 * tone))
    base = g.mix(g.maprange(mid, 0.56, 0.76, 0.0, 0.55), base, _scale_col((0.045, 0.04, 0.036), tone))
    base = g.mix(g.maprange(cel, 0.3, 0.62, 0.0, 0.45), base, _scale_col((0.06, 0.06, 0.064), tone))
    occ = g.ao(3.5)
    base = g.mix(g.maprange(occ, 0.35, 0.95, 0.85, 0.0), base, (0.002, 0.002, 0.0025, 1))
    edge = g.maprange(g.slope(), 0.1, 0.36)
    brk = g.maprange(g.noise(co, 1.0 / 6.0, 6.0, 0.65), 0.38, 0.58, 0.15, 1.0)
    wm = g.mul(g.mul(edge, brk), wear)
    # bright scratches (exposed metal) and dark pits
    sco = g.vmath('ADD', co, g.vmath('SCALE', g.vmath('SUBTRACT', g.noise(co, 1.0 / 30.0, 2.0, out="Color"),
                                                      (0.5, 0.5, 0.5)), scale=25.0))
    scr = g.maprange(g.voronoi(sco, 1.0 / 26.0, 'DISTANCE_TO_EDGE'), 0.0, 0.01, 1.0, 0.0)
    scr = g.mul(scr, g.maprange(g.noise(co, 1.0 / 16.0, 3.0), 0.52, 0.64, 0.0, 0.55 * wear))
    pit = g.maprange(g.voronoi(co, 1.0 / 3.2, 'F1', rand=1.0), 0.0, 0.14, 1.0, 0.0)
    pit = g.mul(pit, g.maprange(g.noise(co, 1.0 / 20.0, 3.0), 0.45, 0.65))
    base = g.mix(g.mul(pit, 0.9), base, (0.0, 0.0, 0.0, 1))
    wm = g.math('MAXIMUM', wm, scr)
    col = g.mix(wm, base, (*SILVER, 1))
    rust_amt = g.value("rust")
    rmask = g.mul(g.maprange(g.noise(co, 1.0 / 26.0, 6.0, 0.65), 0.36, 0.56), rust_amt)
    rcol = g.mix(g.maprange(mid, 0.4, 0.7), (0.07, 0.026, 0.01, 1), (0.16, 0.06, 0.02, 1))
    col = g.mix(rmask, col, rcol)
    dark = g.value("dark")
    col = g.mix(g.mul(dark, 0.6), col, (0.0, 0.0, 0.0, 1))
    g.set("Base Color", col)
    metal = g.mixf(wm, 0.25, 1.0)
    g.set("Metallic", g.mixf(rmask, metal, 0.05))
    g.set("Specular IOR Level", g.mixf(wm, 0.22, 0.5))
    rough = g.mixf(wm, g.maprange(mid, 0.3, 0.7, 0.48, 0.68), 0.24)
    g.set("Roughness", g.mixf(rmask, rough, 0.92))
    h = g.add(g.add(cel, g.mul(cel2, 0.35)), g.mul(fine, 0.1))
    h = g.math('SUBTRACT', g.add(h, g.mul(rmask, g.mul(fine, 0.8))), g.add(g.mul(pit, 0.5), g.mul(scr, 0.25)))
    g.set("Normal", g.bump(h, 0.6, 2.2))
    heat = g.value("heat")
    g.emit((*EMBER, 1), g.mul(g.mul(heat, g.add(g.mul(edge, 3.0), 0.4)), 2.5))
    return g.m


def mat_groove(name, strength=2.0, aniso=None):
    """The engraved line's floor: dark iron that emits glow_col * glow."""
    g = G(name)
    co = g.co(aniso)
    n = g.noise(co, 1.0 / 6.0, 4.0, 0.6)
    g.set("Base Color", g.mix(g.maprange(n, 0.3, 0.7), (0.012, 0.012, 0.014, 1), (0.03, 0.03, 0.034, 1)))
    g.set("Metallic", 0.6)
    g.set("Roughness", 0.5)
    glow = g.value("glow")
    flick = g.maprange(n, 0.25, 0.75, 0.8, 1.15)
    g.emit(g.color("glow_col"), g.mul(g.mul(glow, flick), strength))
    return g.m


def mat_slate(name, alpha=0.93, tone=0.85, aniso=None, cracks=1.0, mask=None, seed=0.0, torus=None,
              groove_glow=2.0, rim=None):
    """Dark slate fill: mottled, faint cracks, engraved lines/runes from a Mask (R = line, G = runes)."""
    g = G(name)
    w4 = None
    if torus is not None:  # seamless: map x, y onto two circles (4D noise), period = torus px
        r = torus / (2 * math.pi)
        o = g.sep(g.tc.outputs["Object"])
        ax = g.math('MULTIPLY', o[0], 2 * math.pi / torus)
        ay = g.math('MULTIPLY', o[1], 2 * math.pi / torus)
        co = g.comb(g.mul(g.math('COSINE', ax), r), g.mul(g.math('SINE', ax), r), g.mul(g.math('COSINE', ay), r))
        w4 = g.mul(g.math('SINE', ay), r)
    else:
        co = g.co(aniso, (seed * 17.3, seed * 9.1, seed * 3.3))
    big = g.noise(co, 1.0 / 90.0, 4.0, 0.55, w=w4)
    mid = g.noise(co, 1.0 / 20.0, 5.0, 0.6, w=w4)
    grain = g.noise(co, 1.0 / 1.6, 2.0, 0.5, w=w4)
    warp = g.vmath('ADD', co, g.vmath('SCALE', g.vmath('SUBTRACT', g.noise(co, 1.0 / 45.0, 4.0, out="Color", w=w4),
                                                       (0.5, 0.5, 0.5)), scale=38.0))
    edge = g.voronoi(warp, 1.0 / 95.0, 'DISTANCE_TO_EDGE', w=w4)
    crack = g.maprange(edge, 0.0, 0.011, 1.0, 0.0)
    cov = g.maprange(g.noise(co, 1.0 / 110.0, 4.0, 0.6, w=w4), 0.5, 0.6)
    crack = g.mul(g.mul(crack, cov), cracks)
    edge2 = g.voronoi(warp, 1.0 / 34.0, 'DISTANCE_TO_EDGE', w=w4)
    hair = g.mul(g.mul(g.maprange(edge2, 0.0, 0.02, 1.0, 0.0),
                       g.maprange(g.noise(co, 1.0 / 50.0, 3.0, 0.5, w=w4), 0.56, 0.66)), cracks * 0.55)
    speck = g.noise(co, 1.0 / 1.1, 2.0, 0.5, w=w4)
    t = tone
    col = g.mix(g.maprange(big, 0.3, 0.7), (0.020 * t, 0.022 * t, 0.031 * t, 1), (0.044 * t, 0.046 * t, 0.058 * t, 1))
    col = g.mix(g.maprange(mid, 0.45, 0.75, 0.0, 0.6), col, (0.052 * t, 0.053 * t, 0.062 * t, 1))
    col = g.mix(g.maprange(grain, 0.35, 0.65, 0.0, 0.35), col, (0.006, 0.006, 0.008, 1))
    col = g.mix(g.maprange(speck, 0.6, 0.7, 0.0, 0.5), col, (0.10 * t, 0.10 * t, 0.11 * t, 1))
    col = g.mix(g.add(crack, hair), col, (0.002, 0.002, 0.003, 1))
    h = g.add(g.mul(mid, 0.25), g.mul(grain, 0.12))
    h = g.math('SUBTRACT', h, g.mul(g.add(crack, g.mul(hair, 0.5)), 0.7))
    if mask is not None:
        R, Gm, B = g.mask(mask, repeat=torus is not None)
        col = g.mix(g.mul(R, 0.85), col, (0.004, 0.004, 0.005, 1))
        col = g.mix(g.mul(Gm, 0.55), col, (0.0035, 0.0035, 0.0045, 1))
        col = g.mix(g.mul(B, 0.5), col, (0.06, 0.06, 0.066, 1))
        h = g.math('SUBTRACT', h, g.add(g.mul(R, 1.6), g.mul(Gm, 1.1)))
        glow = g.value("glow")
        g.emit(g.color("glow_col"), g.mul(g.mul(R, glow), groove_glow))
    if rim is not None:  # darker towards the frame: (half width, half height, falloff px)
        o = g.sep(g.tc.outputs["Object"])
        d = g.math('MINIMUM', g.math('SUBTRACT', rim[0], g.math('ABSOLUTE', o[0])),
                   g.math('SUBTRACT', rim[1], g.math('ABSOLUTE', o[1])))
        col = g.vmath('SCALE', col, scale=g.maprange(d, 0.0, rim[2], 0.4, 1.0))
    g.set("Base Color", col)
    g.set("Roughness", g.maprange(mid, 0.3, 0.7, 0.78, 0.92))
    g.set("Specular IOR Level", 0.2)
    g.set("Normal", g.bump(h, 0.45, 1.0))
    g.set("Alpha", alpha)
    return g.m


def mat_bone(name, aniso=None, tone=1.0, seed=0.0, ao=5.0, glow_eyes=False):
    """Aged carved bone: warm mottling, dirt in crevices (AO), hairline cracks."""
    g = G(name)
    co = g.co(aniso, (seed * 13.7, seed * 3.1, seed * 7.9))
    big = g.noise(co, 1.0 / 40.0, 5.0, 0.55)
    mid = g.noise(co, 1.0 / 9.0, 5.0, 0.6)
    fine = g.noise(co, 1.0 / 2.0, 3.0, 0.5)
    t = tone
    col = g.mix(g.maprange(big, 0.3, 0.7), (0.17 * t, 0.125 * t, 0.065 * t, 1), (0.46 * t, 0.37 * t, 0.22 * t, 1))
    col = g.mix(g.maprange(mid, 0.5, 0.72, 0.0, 0.5), col, (0.58 * t, 0.49 * t, 0.33 * t, 1))
    stain = g.maprange(g.noise(co, 1.0 / 22.0, 4.0, 0.6), 0.5, 0.72, 0.0, 0.8)
    col = g.mix(stain, col, (0.09 * t, 0.055 * t, 0.025 * t, 1))
    warp = g.vmath('ADD', co, g.vmath('SCALE', g.vmath('SUBTRACT', g.noise(co, 1.0 / 25.0, 3.0, out="Color"),
                                                       (0.5, 0.5, 0.5)), scale=14.0))
    cr = g.mul(g.maprange(g.voronoi(warp, 1.0 / 26.0, 'DISTANCE_TO_EDGE'), 0.0, 0.018, 1.0, 0.0),
               g.maprange(g.noise(co, 1.0 / 30.0, 3.0), 0.48, 0.6))
    pit = g.mul(g.maprange(g.voronoi(co, 1.0 / 2.6, 'F1'), 0.0, 0.16, 1.0, 0.0),
                g.maprange(g.noise(co, 1.0 / 14.0, 3.0), 0.45, 0.62))
    col = g.mix(g.math('MAXIMUM', g.mul(cr, 0.85), g.mul(pit, 0.7)), col, (0.05, 0.035, 0.02, 1))
    occ = g.ao(ao)
    col = g.mix(g.maprange(occ, 0.3, 0.97, 0.92, 0.0), col, (0.02, 0.013, 0.007, 1))
    side = g.mul(g.maprange(g.slope(), 0.25, 0.9), g.maprange(big, 0.3, 0.7, 0.45, 0.8))
    col = g.mix(side, col, (0.06, 0.038, 0.016, 1))
    g.set("Base Color", col)
    g.set("Roughness", g.maprange(mid, 0.3, 0.7, 0.45, 0.68))
    g.set("Coat Weight", 0.05)
    g.set("Coat Roughness", 0.4)
    h = g.math('SUBTRACT', g.add(g.mul(mid, 0.35), g.mul(fine, 0.12)), g.add(g.mul(cr, 0.6), g.mul(pit, 0.4)))
    g.set("Normal", g.bump(h, 0.5, 1.2))
    return g.m


def mat_horn(name, seed=0.0):
    g = G(name)
    co = g.co(None, (seed, seed * 2, 0))
    n = g.noise(co, 1.0 / 5.0, 5.0, 0.6)
    col = g.mix(g.maprange(n, 0.3, 0.7), (0.035, 0.028, 0.022, 1), (0.10, 0.085, 0.065, 1))
    col = g.mix(g.maprange(g.slope(), 0.1, 0.6, 0.0, 0.5), col, (0.20, 0.17, 0.12, 1))
    g.set("Base Color", col)
    g.set("Roughness", 0.38)
    g.set("Coat Weight", 0.4)
    g.set("Normal", g.bump(g.noise(co, 1.0 / 1.5, 3.0), 0.3, 0.6))
    return g.m


def mat_gem(name, color, strength=1.5):
    g = G(name)
    g.set("Base Color", (color[0] * 0.25, color[1] * 0.25, color[2] * 0.25, 1))
    g.set("Roughness", 0.06)
    g.set("Coat Weight", 1.0)
    g.set("Coat Roughness", 0.02)
    g.set("Specular IOR Level", 0.8)
    occ = g.ao(4.0)
    g.emit((*color, 1), g.mul(g.maprange(occ, 0.3, 1.0, 0.45, 1.0), strength))
    return g.m


def mat_gold(name, seed=0.0, tone=1.0):
    g = G(name)
    co = g.co(None, (seed, seed, seed))
    mid = g.noise(co, 1.0 / 9.0, 5.0, 0.6)
    fine = g.noise(co, 1.0 / 1.8, 3.0, 0.5)
    col = g.mix(g.maprange(mid, 0.3, 0.7), (0.55 * tone, 0.34 * tone, 0.11 * tone, 1),
                (0.85 * tone, 0.58 * tone, 0.22 * tone, 1))
    occ = g.ao(5.0)
    col = g.mix(g.maprange(occ, 0.3, 0.95, 0.9, 0.0), col, (0.06, 0.035, 0.012, 1))
    g.set("Base Color", col)
    g.set("Metallic", 1.0)
    g.set("Roughness", g.maprange(fine, 0.3, 0.7, 0.24, 0.42))
    g.set("Normal", g.bump(g.add(g.mul(mid, 0.3), g.mul(fine, 0.2)), 0.3, 0.8))
    return g.m


def mat_enamel(name, seed=0.0):
    """Blood-red vitreous enamel with crackle; face_glow heats it to ember, dark presses it down."""
    g = G(name)
    co = g.co((0.35, 1.0, 1.0), (seed, seed, 0))
    big = g.noise(co, 1.0 / 30.0, 4.0, 0.55)
    crk = g.maprange(g.voronoi(g.co(None), 1.0 / 14.0, 'DISTANCE_TO_EDGE'), 0.0, 0.03, 1.0, 0.0)
    col = g.mix(g.maprange(big, 0.3, 0.7), (0.035, 0.0025, 0.002, 1), (0.10, 0.006, 0.004, 1))
    col = g.mix(g.mul(crk, 0.35), col, (0.015, 0.001, 0.001, 1))
    dark = g.value("dark")
    col = g.mix(g.mul(dark, 0.55), col, (0.0, 0.0, 0.0, 1))
    g.set("Base Color", col)
    g.set("Roughness", 0.32)
    g.set("Coat Weight", 0.8)
    g.set("Coat Roughness", 0.12)
    g.set("Normal", g.bump(g.math('SUBTRACT', g.mul(big, 0.2), g.mul(crk, 0.5)), 0.3, 0.8))
    fg = g.value("face_glow")
    g.emit((*EMBER, 1), g.mul(g.mul(fg, g.maprange(big, 0.2, 0.8, 0.4, 1.4)), 1.0))
    return g.m


def mat_liquid(name, strength=1.05):
    """Glowing liquid (colour = glow_col): bright core facing the camera, slow swirls along X (stretch-safe)."""
    g = G(name)
    co = g.co((0.06, 1.0, 1.0))
    sw = g.noise(co, 1.0 / 4.0, 4.0, 0.6)
    nz = g.sep(g.geo.outputs["Normal"])[2]
    core = g.math('POWER', g.maprange(nz, 0.0, 1.0), 3.0)
    k = g.add(g.mul(core, g.maprange(sw, 0.3, 0.7, 0.7, 1.3)), 0.18)
    col = g.color("glow_col")
    g.set("Base Color", g.mix(0.8, col, (0, 0, 0, 1)))
    g.set("Roughness", 0.1)
    g.set("Coat Weight", 1.0)
    g.emit(col, g.mul(k, strength))
    return g.m


def mat_emit(name, color, strength):
    g = G(name)
    g.set("Base Color", (0, 0, 0, 1))
    g.emit((*color, 1), strength)
    return g.m


def mat_recess(name, alpha=0.95):
    """Very dark matte for slots and channels."""
    return mat_slate(name, alpha=alpha, tone=0.55, cracks=0.3)


# ----------------------------------------------------------------------------------------------- bmesh

def merge(dst, src, mi=None):
    vmap = {v: dst.verts.new(v.co) for v in src.verts}
    for f in src.faces:
        try:
            nf = dst.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            continue
        nf.material_index = f.material_index if mi is None else mi
        nf.smooth = f.smooth
    src.free()
    return dst


def set_mi(bm, mi):
    for f in bm.faces:
        f.material_index = mi
    return bm


def xform(bm, m):
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    if m.determinant() < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def S(x=1.0, y=1.0, z=1.0):
    return Matrix.Diagonal((x, y, z, 1.0))


def copy(bm):
    c = bm.copy()
    return c


def signed_area(pts):
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                     for i in range(len(pts)))


def prism(outline, z0, z1, mi=0):
    if signed_area(outline) < 0:
        outline = list(reversed(outline))
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in outline]
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    set_mi(bm, mi)
    return bm


def plate(outline, z0, z1, steps=(), mi=0, face_mi=None):
    """Extruded outline with an inset stack on its top face (forged mouldings).

    steps: [(thickness, depth, mi), ...]: inset the top face by `thickness`, move it by `depth` (+ = up); the new
    ring of faces gets material `mi`. The remaining top face gets `face_mi` (default: last ring's mi).
    """
    bm = prism(outline, z0, z1, mi)
    bm.normal_update()
    top = [f for f in bm.faces if f.normal.z > 0.5]
    last = mi
    for t, d, m in steps:
        res = bmesh.ops.inset_region(bm, faces=top, thickness=t, depth=d, use_even_offset=True,
                                     use_boundary=True)
        for f in res["faces"]:
            f.material_index = m
        last = m
    for f in top:
        f.material_index = last if face_mi is None else face_mi
    return bm


def _frames(path, closed, up):
    n = len(path)
    tang = []
    for i in range(n):
        if closed:
            t = path[(i + 1) % n] - path[i - 1]
        else:
            t = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        tang.append(t.normalized() if t.length > 1e-9 else Vector((1, 0, 0)))
    frames = []
    if up is not None:
        up = Vector(up).normalized()
        for i in range(n):
            side = tang[i].cross(up)
            if side.length < 1e-6:
                side = Vector((1, 0, 0))
            side.normalize()
            frames.append((tang[i], side, side.cross(tang[i]).normalized()))
        return frames
    t0 = tang[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    side = t0.cross(ref).normalized()
    nrm = side.cross(t0).normalized()
    frames.append((t0, side, nrm))
    for i in range(1, n):
        t = tang[i]
        nrm = nrm - t * nrm.dot(t)
        if nrm.length < 1e-6:
            nrm = frames[-1][2]
        nrm.normalize()
        frames.append((t, t.cross(nrm).normalized(), nrm))
    return frames


def sweep(path, profile, up=(0, 0, 1), closed=False, closed_profile=True, caps=True, mi=0, miter=True, mis=None):
    """Sweep a 2D profile [(u, v)] along a 3D path. With `up` the frame is planar: u = right of the tangent
    in the plane, v = along `up`. `profile` may be a list per path point (lofts, tapers).
    `mis` gives a material index per profile segment (else `mi` for all)."""
    path = [Vector(p) for p in path]
    n = len(path)
    per_point = isinstance(profile[0], (list, tuple)) and isinstance(profile[0][0], (list, tuple))
    bm = bmesh.new()
    frames = _frames(path, closed, up)
    rings = []
    for i in range(n):
        t, side, nrm = frames[i]
        prof = profile[i] if per_point else profile
        mit = 1.0
        if miter and up is not None and (closed or 0 < i < n - 1):
            seg_t = (path[(i + 1) % n] - path[i]).normalized()
            mit = 1.0 / max(0.35, t.dot(seg_t))
        rings.append([bm.verts.new(path[i] + side * (u * mit) + nrm * v) for u, v in prof])
    m = len(rings[0])
    segs = n if closed else n - 1
    pm = m if closed_profile else m - 1
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % n]
        for j in range(pm):
            k = (j + 1) % m
            try:
                f = bm.faces.new([a[j], a[k], b[k], b[j]])
                f.material_index = mis[j] if mis else mi
            except ValueError:
                pass
    if caps and not closed and closed_profile and m > 2:
        for ring in (rings[0], rings[-1]):
            try:
                bm.faces.new(ring).material_index = mi
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    if closed_profile:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def catmull(points, n=6, closed=False):
    """Catmull-Rom spline through points (2D or 3D tuples), n samples per span; returns 3D tuples."""
    P = [Vector((p[0], p[1], p[2] if len(p) > 2 else 0.0)) for p in points]
    out = []
    m = len(P)
    spans = m if closed else m - 1
    for i in range(spans):
        p0 = P[(i - 1) % m] if closed else P[max(i - 1, 0)]
        p1, p2 = P[i % m], P[(i + 1) % m] if closed else P[min(i + 1, m - 1)]
        p3 = P[(i + 2) % m] if closed else P[min(i + 2, m - 1)]
        for k in range(n):
            t = k / n
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                       + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
            out.append((q.x, q.y, q.z))
    if not closed:
        out.append((P[-1].x, P[-1].y, P[-1].z))
    return out


def lance(x0, x1, y, w, h, z=0.0, tip=40.0, swell=1.7, mi=0):
    """Straight ridged bar along X from x0 to x1 (x1 > x0) ending in a spear tip at x1."""
    xs = [x0, x1 - tip, x1 - tip * 0.72, x1 - tip * 0.5, x1 - tip * 0.25, x1 - 0.8, x1]
    ws = [w, w * 0.8, w * swell, w * swell * 0.85, w * 0.55, w * 0.12, 0.05]
    hs = [h, h * 0.85, h * 1.15, h * 1.05, h * 0.7, h * 0.3, h * 0.2]
    path = [(x, y, z) for x in xs]
    profs = [[(-ww, 0.0), (-ww * 0.55, hh * 0.72), (0.0, hh), (ww * 0.55, hh * 0.72), (ww, 0.0)]
             for ww, hh in zip(ws, hs)]
    return sweep(path, profs, up=(0, 0, 1), closed_profile=False, caps=False, mi=mi)


def fit(bm, cx, cy, z0, width, zscale=1.0):
    """Scale a bmesh uniformly so its X extent is `width`, flatten Z by zscale, put its base at z0, centre at cx, cy."""
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    k = width / max(1e-6, max(xs) - min(xs))
    mx, my, mz = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs)
    for v in bm.verts:
        v.co = Vector(((v.co.x - mx) * k + cx, (v.co.y - my) * k + cy, (v.co.z - mz) * k * zscale + z0))
    return bm


def lathe(profile, seg=24, z0=0.0, cx=0.0, cy=0.0, mi=0, phase=0.0):
    """Revolve [(r, z), ...] (outside to the axis or bottom to top) around a vertical axis at (cx, cy)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-5:
            rings.append([bm.verts.new((cx, cy, z0 + z))])
            continue
        rings.append([bm.verts.new((cx + r * math.cos(phase + 2 * math.pi * i / seg),
                                    cy + r * math.sin(phase + 2 * math.pi * i / seg), z0 + z))
                      for i in range(seg)])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1 and len(b) == 1:
                continue
            try:
                if len(a) == 1:
                    bm.faces.new([a[0], b[j], b[i]])
                elif len(b) == 1:
                    bm.faces.new([a[i], a[j], b[0]])
                else:
                    bm.faces.new([a[i], a[j], b[j], b[i]])
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mi(bm, mi)
    return bm


def rivet(x, y, r, z=0.0, h=None, mi=0, seg=20):
    h = h if h is not None else r * 0.75
    prof = [(r * 1.08, 0.0), (r * 1.05, h * 0.25)]
    for k in range(1, 7):
        a = (math.pi / 2) * k / 7
        prof.append((r * math.cos(a), h * 0.25 + h * 0.75 * math.sin(a)))
    prof.append((0.0, h))
    return lathe(prof, seg, z, x, y, mi)


def dome(x, y, r, h, z=0.0, mi=0, seg=24, rings=6):
    prof = [(r, 0.0)]
    for k in range(1, rings):
        a = (math.pi / 2) * k / rings
        prof.append((r * math.cos(a), h * math.sin(a)))
    prof.append((0.0, h))
    return lathe(prof, seg, z, x, y, mi)


def gem(x, y, r, z, h=None, facets=8, mi=0):
    """Faceted cabochon: flat-shaded crown with a table."""
    h = h if h is not None else r * 0.75
    prof = [(r, 0.0), (r * 0.98, h * 0.3), (r * 0.78, h * 0.75), (r * 0.42, h), (0.0, h)]
    bm = lathe(prof, facets, z, x, y, mi, phase=math.pi / facets)
    for f in bm.faces:
        f.smooth = False
    return bm


def blade(base, tip, w0, h0, z0=0.0, bend=0.0, n=10, mi=0, w_pow=0.85, h_tip=0.25):
    """Pointed ridged spike/thorn in the XY plane from base to tip; bend curves it sideways (px)."""
    a, b = Vector((base[0], base[1], 0)), Vector((tip[0], tip[1], 0))
    d = b - a
    side = Vector((-d.y, d.x, 0)).normalized()
    path, profs = [], []
    for i in range(n + 1):
        t = i / n
        p = a + d * t + side * (bend * math.sin(math.pi * t * 0.5) * t)
        path.append((p.x, p.y, z0))
        w = max(0.06, w0 * (1 - t) ** w_pow)
        hh = h0 * (1 - t * (1 - h_tip))
        profs.append([(-w, 0.0), (-w * 0.55, hh * 0.7), (0.0, hh), (w * 0.55, hh * 0.7), (w, 0.0)])
    return sweep(path, profs, up=(0, 0, 1), closed_profile=False, caps=False, mi=mi)


def tube(path, radii, zscale=1.0, seg=14, mi=0, caps=True):
    """Round tube along a planar path (z from the path) with a radius per point; zscale flattens it."""
    profs = [[(r * math.cos(2 * math.pi * k / seg), r * zscale * math.sin(2 * math.pi * k / seg))
              for k in range(seg)] for r in radii]
    return sweep(path, profs, up=(0, 0, 1), closed_profile=True, caps=caps, mi=mi)


def sphere(c, r, sx=1.0, sy=1.0, sz=1.0, seg=20, rings=10, mi=0):
    prof = [(0.0, -r)]
    for k in range(1, rings):
        a = -math.pi / 2 + math.pi * k / rings
        prof.append((r * math.cos(a), r * math.sin(a)))
    prof.append((0.0, r))
    bm = lathe(prof, seg, 0.0, 0.0, 0.0, mi)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return bm


def rect_path(hw, hh, z=0.0, chamfer=0.0):
    """Closed CCW rectangle (optionally chamfered) path around the centre."""
    if chamfer <= 0:
        pts = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
    else:
        c = chamfer
        pts = [(-hw + c, -hh), (hw - c, -hh), (hw, -hh + c), (hw, hh - c), (hw - c, hh), (-hw + c, hh),
               (-hw, hh - c), (-hw, -hh + c)]
    return [(x, y, z) for x, y in pts]


def hv_split(bm, mi_h, mi_v, hw, hh):
    """Assign the faces of a rectangular frame to horizontal (top/bottom) or vertical (left/right) bars."""
    for f in bm.faces:
        c = f.calc_center_median()
        if (hh - abs(c.y)) < (hw - abs(c.x)):
            f.material_index = mi_h
        else:
            f.material_index = mi_v
    return bm


def frame(hw, hh, profile, chamfer=0.0, mi_h=0, mi_v=1):
    """Moulding swept around a rectangle (centreline half-sizes); profile u > 0 = outward."""
    bm = sweep(rect_path(hw, hh, 0.0, chamfer), profile, up=(0, 0, 1), closed=True, closed_profile=False)
    return hv_split(bm, mi_h, mi_v, hw, hh)


def ring(rc, profile, seg=128, mi=0):
    path = [(rc * math.cos(2 * math.pi * i / seg), rc * math.sin(2 * math.pi * i / seg), 0.0) for i in range(seg)]
    return sweep(path, profile, up=(0, 0, 1), closed=True, closed_profile=False, mi=mi)


def moulding(spec, w):
    """Profile builder: spec = [(du, v), ...] stepping inward from the outer edge u=+w/2 to -w/2."""
    pts = [(w / 2, 0.0)]
    u = w / 2
    for du, v in spec:
        u -= du
        pts.append((u, v))
    pts.append((pts[-1][0], 0.0))
    return pts


def bead(u0, u1, v0, v1, n=7):
    """Half-round bead between u0 > u1 (outer to inner), rising from v0 to v1."""
    out = []
    for k in range(n + 1):
        a = math.pi * k / n
        out.append((u0 + (u1 - u0) * (1 - math.cos(a)) / 2, v0 + (v1 - v0) * math.sin(a)))
    return out


def metaball(elems, res=0.8, threshold=0.6):
    """elems: dicts(type, co, r, size, neg, stiff, rot). Returns a bmesh of the polygonised surface."""
    metaball.n = getattr(metaball, "n", 0) + 1
    mb = bpy.data.metaballs.new(f"mb{metaball.n}")
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = threshold
    for e in elems:
        el = mb.elements.new(type=e.get("type", 'BALL'))
        el.co = e["co"]
        el.radius = e["r"]
        el.stiffness = e.get("stiff", 2.0)
        el.use_negative = e.get("neg", False)
        if "size" in e:
            el.size_x, el.size_y, el.size_z = e["size"]
        if "rot" in e:
            el.rotation = e["rot"]
    o = link(bpy.data.objects.new(f"mbo{metaball.n}", mb))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.objects.remove(o)
    bpy.data.metaballs.remove(mb)
    bpy.data.meshes.remove(me)
    for f in bm.faces:
        f.smooth = True
    return bm


def quat_x_to(d):
    return Vector((1, 0, 0)).rotation_difference(Vector(d).normalized())


def obj(bm, name, mats, sharp=38.0, shadow=True, smooth=True):
    """bmesh -> mesh object with smooth shading split at `sharp` degrees."""
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    thr = math.radians(sharp)
    if smooth:
        for f in bm.faces:
            f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) != 2:
            e.smooth = False
            continue
        try:
            e.smooth = e.calc_face_angle() < thr
        except ValueError:
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    o = link(bpy.data.objects.new(name, me))
    o.visible_shadow = shadow
    return o


def catcher(W, H, hole=0.0, z=-0.3, pad=0.0, rect=None):
    """Shadow catcher under everything. `hole` (radius) or `rect` (half sizes) cut it out where the result must
    stay transparent or where a semi-transparent fill sits (the fill would occlude the sky for the catcher)."""
    hw, hh = W / 2 + pad, H / 2 + pad
    bm = bmesh.new()
    if rect is not None:
        rx, ry = rect
        for x0, y0, x1, y1 in ((-hw, -hh, hw, -ry), (-hw, ry, hw, hh), (-hw, -ry, -rx, ry), (rx, -ry, hw, ry)):
            vs = [bm.verts.new((x, y, z)) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
            bm.faces.new(vs)
    elif hole <= 0:
        vs = [bm.verts.new((x, y, z)) for x, y in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh))]
        bm.faces.new(vs)
    else:
        n = 128
        inner, outer = [], []
        for i in range(n):
            a = 2 * math.pi * i / n
            c, s = math.cos(a), math.sin(a)
            k = min(hw / max(abs(c), 1e-6), hh / max(abs(s), 1e-6))
            inner.append(bm.verts.new((hole * c, hole * s, z)))
            outer.append(bm.verts.new((k * c, k * s, z)))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([inner[i], outer[i], outer[j], inner[j]])
    me = bpy.data.meshes.new("catcher")
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new("catcher", me))
    o.is_shadow_catcher = True
    return o


# ----------------------------------------------------------------------------------------------- masks

RUNES = [
    [[(0, 0), (0, 1)], [(0, 0.55), (0.5, 0.85)], [(0, 0.8), (0.45, 1.0)]],
    [[(0, 0), (0, 1)], [(0, 1), (0.5, 0.7), (0.5, 0)]],
    [[(0, 0), (0, 1)], [(0, 0.72), (0.42, 0.5), (0, 0.28)]],
    [[(0, 0), (0, 1)], [(0, 1), (0.45, 0.75)], [(0, 0.75), (0.45, 0.5)]],
    [[(0, 0), (0, 1)], [(0, 1), (0.45, 0.78), (0, 0.55), (0.45, 0)]],
    [[(0.45, 1), (0, 0.5), (0.45, 0)]],
    [[(0, 0), (0.6, 1)], [(0.6, 0), (0, 1)]],
    [[(0, 0), (0, 1)], [(0.5, 0), (0.5, 1)], [(0, 0.66), (0.5, 0.34)]],
    [[(0.25, 0), (0.25, 1)], [(0, 0.66), (0.5, 0.34)]],
    [[(0.25, 1), (0, 0.75), (0.25, 0.5)], [(0.35, 0.5), (0.6, 0.25), (0.35, 0)]],
    [[(0.25, 0), (0.25, 1)], [(0.25, 1), (0.5, 0.82)], [(0.25, 0), (0, 0.18)]],
    [[(0.3, 0), (0.3, 1)], [(0, 1), (0.3, 0.62), (0.6, 1)]],
    [[(0.45, 1), (0, 0.66), (0.45, 0.34), (0, 0)]],
    [[(0.3, 0), (0.3, 1)], [(0, 0.7), (0.3, 1), (0.6, 0.7)]],
    [[(0, 0), (0, 1)], [(0, 1), (0.42, 0.76), (0, 0.52), (0.42, 0.26), (0, 0)]],
    [[(0, 0), (0, 1)], [(0.55, 0), (0.55, 1)], [(0, 1), (0.55, 0.6)], [(0.55, 1), (0, 0.6)]],
    [[(0, 0), (0, 1)], [(0, 1), (0.42, 0.74)]],
    [[(0.3, 0.1), (0.6, 0.5), (0.3, 0.9), (0, 0.5), (0.3, 0.1)]],
    [[(0, 0), (0, 1)], [(0.6, 0), (0.6, 1)], [(0, 1), (0.6, 0)], [(0, 0), (0.6, 1)]],
    [[(0, 0), (0.3, 0.4), (0.6, 0)], [(0.3, 0.4), (0, 0.7), (0.3, 1), (0.6, 0.7), (0.3, 0.4)]],
]


class Mask:
    """Float raster over a px rectangle (x0, y0, w, h), row 0 = bottom (Blender image order).

    Channels: R engraved line (glows with `glow`), G runes, B worn highlight. Strokes are V-grooves (1 at the
    centre line falling to 0 at width/2), combined by max."""

    def __init__(self, x0, y0, w, h, res=SCALE, wrap=False):
        self.x0, self.y0, self.w, self.h, self.res, self.wrap = x0, y0, w, h, res, wrap
        self.nx, self.ny = int(round(w * res)), int(round(h * res))
        self.a = np.zeros((self.ny, self.nx, 4), np.float32)
        self.a[..., 3] = 1.0
        self._img = None

    def _seg(self, p, q, width, ch, k):
        hw = width / 2.0 + 1.0 / self.res
        offs = [(0, 0)]
        if self.wrap:
            offs = [(dx, dy) for dx in (-self.w, 0, self.w) for dy in (-self.h, 0, self.h)]
        for dx, dy in offs:
            px, py, qx, qy = p[0] + dx, p[1] + dy, q[0] + dx, q[1] + dy
            x_lo, x_hi = min(px, qx) - hw, max(px, qx) + hw
            y_lo, y_hi = min(py, qy) - hw, max(py, qy) + hw
            i0 = max(0, int((x_lo - self.x0) * self.res))
            i1 = min(self.nx, int((x_hi - self.x0) * self.res) + 2)
            j0 = max(0, int((y_lo - self.y0) * self.res))
            j1 = min(self.ny, int((y_hi - self.y0) * self.res) + 2)
            if i0 >= i1 or j0 >= j1:
                continue
            X = self.x0 + (np.arange(i0, i1) + 0.5) / self.res
            Y = self.y0 + (np.arange(j0, j1) + 0.5) / self.res
            X, Y = np.meshgrid(X, Y)
            vx, vy = qx - px, qy - py
            L2 = vx * vx + vy * vy
            t = np.clip(((X - px) * vx + (Y - py) * vy) / L2, 0.0, 1.0) if L2 > 1e-9 else 0.0
            d = np.hypot(X - (px + t * vx), Y - (py + t * vy))
            v = np.clip(1.0 - d / (width / 2.0), 0.0, 1.0) ** 0.7 * k
            blk = self.a[j0:j1, i0:i1, ch]
            np.maximum(blk, v, out=blk)

    def stroke(self, pts, width, ch=0, closed=False, k=1.0):
        pts = list(pts)
        if closed:
            pts = pts + [pts[0]]
        for i in range(len(pts) - 1):
            self._seg(pts[i], pts[i + 1], width, ch, k)

    def rune(self, idx, x, y, size, width, ch=1, k=1.0, rot=0.0):
        c, s = math.cos(rot), math.sin(rot)
        for st in RUNES[idx % len(RUNES)]:
            pts = []
            for u, v in st:
                u, v = (u - 0.3) * size, (v - 0.5) * size
                pts.append((x + u * c - v * s, y + u * s + v * c))
            self.stroke(pts, width, ch, k=k)

    def image(self, repeat=False):
        if self._img is None:
            im = bpy.data.images.new(f"mask{id(self)}", self.nx, self.ny, alpha=True, float_buffer=True)
            im.colorspace_settings.name = 'Non-Color'
            im.pixels.foreach_set(self.a.ravel())
            im.pack()
            self._img = im
        return self._img
