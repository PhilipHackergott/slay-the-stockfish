"""Shared helpers for the world assets: bmesh primitives, sweeps, gothic curves, finishing, AO bake, glb export.

Run inside Blender (bpy). Coordinates: metres, Z up, board centre = origin.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BUILD = os.path.join(ROOT, "build", "blender", "world")
MODELS = os.path.join(ROOT, "models")

# Export stand-in materials (the game swaps them by name): base colour, roughness, metallic, emission.
PALETTE = {
    "board_light": ((0.66, 0.64, 0.62, 1), 0.35, 0.0, None),
    "board_dark": ((0.035, 0.035, 0.045, 1), 0.4, 0.0, None),
    "board_rune": ((0.30, 0.45, 1.0, 1), 0.4, 0.0, (0.3, 0.5, 1.0, 1)),
    "board_rim": ((0.30, 0.295, 0.31, 1), 0.85, 0.0, None),
    "board_trim": ((0.07, 0.07, 0.08, 1), 0.6, 0.4, None),
    "stone": ((0.27, 0.27, 0.29, 1), 0.9, 0.0, None),
    "stone_dark": ((0.09, 0.09, 0.11, 1), 0.92, 0.0, None),
    "floor_tiles": ((0.17, 0.17, 0.19, 1), 0.9, 0.0, None),
    "iron": ((0.045, 0.045, 0.05, 1), 0.55, 0.85, None),
    "candle_wax": ((0.86, 0.80, 0.66, 1), 0.55, 0.0, None),
    "candle_flame": ((1.0, 0.62, 0.22, 1), 0.5, 0.0, (1.0, 0.55, 0.15, 1)),
    "wood_dead": ((0.11, 0.095, 0.085, 1), 0.9, 0.0, None),
    "crow": ((0.018, 0.018, 0.024, 1), 0.55, 0.0, None),
    "moss": ((0.09, 0.13, 0.06, 1), 0.95, 0.0, None),
    "bone": ((0.66, 0.62, 0.52, 1), 0.7, 0.0, None),
}

ENV_MATS = ["stone", "stone_dark", "floor_tiles", "iron", "wood_dead", "crow", "moss", "bone"]


def script_args():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def log(*a):
    print("[world]", *a, flush=True)


# ----------------------------------------------------------------------------------------------- materials

def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough, metal, emit = PALETTE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = 2.0
    m.diffuse_color = col
    return m


# ----------------------------------------------------------------------------------------------- bmesh helpers

def merge(dst, src, mat=None, matrix=None):
    """Append src bmesh into dst. mat=None keeps src material indices."""
    vmap = {}
    for v in src.verts:
        vmap[v] = dst.verts.new(matrix @ v.co if matrix is not None else v.co.copy())
    for f in src.faces:
        try:
            nf = dst.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            continue
        nf.material_index = f.material_index if mat is None else mat
        nf.smooth = f.smooth
    return dst


def set_mat(bm, mi):
    for f in bm.faces:
        f.material_index = mi
    return bm


def transform(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


def mat_trs(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    from mathutils import Euler
    return Matrix.LocRotScale(Vector(loc), Euler(rot, 'XYZ'), Vector(scale))


def box(sx, sy, sz, bevel=0.0, seg=1, center=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=seg, profile=0.5,
                        affect='EDGES', clamp_overlap=True)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def signed_area(pts):
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                     for i in range(len(pts)))


def prism(outline, z0, z1, bevel=0.0, seg=1, bevel_top_only=False):
    """Extrude a 2D outline [(x,y),...] (any winding) between z0 and z1."""
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
    if bevel > 0:
        if bevel_top_only:
            edges = [e for e in bm.edges if any(v.co.z > (z0 + z1) * 0.5 for v in e.verts)]
        else:
            edges = list(bm.edges)
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=seg, profile=0.5, affect='EDGES',
                        clamp_overlap=True)
    return bm


def lathe(profile, seg=16, cap_bottom=True, cap_top=True, phase=0.0):
    """Revolve [(r, z), ...] (bottom to top) around Z."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-5:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for i in range(seg):
            a = phase + 2 * math.pi * i / seg
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new([a[0], b[j], b[i]])
            elif len(b) == 1:
                bm.faces.new([a[i], a[j], b[0]])
            else:
                bm.faces.new([a[i], a[j], b[j], b[i]])
    if cap_bottom and len(rings[0]) > 2:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and len(rings[-1]) > 2:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def uvsphere(r=1.0, seg=8, rings=6):
    prof = []
    for k in range(rings + 1):
        t = math.pi * k / rings
        prof.append((r * math.sin(t), -r * math.cos(t)))
    prof[0] = (0, prof[0][1])
    prof[-1] = (0, prof[-1][1])
    return lathe(prof, seg=seg, cap_bottom=False, cap_top=False)


def torus(R, r, seg=8, rseg=4, sx=1.0):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c, s = math.cos(a), math.sin(a)
        ring = []
        for j in range(rseg):
            b = 2 * math.pi * j / rseg + math.pi / rseg
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * c * sx, rr * s, r * math.sin(b))))
        rings.append(ring)
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(rseg):
            k = (j + 1) % rseg
            bm.faces.new([a[j], b[j], b[k], a[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _frames(path, closed, up):
    n = len(path)
    tang = []
    for i in range(n):
        if closed:
            t = (path[(i + 1) % n] - path[i - 1])
        else:
            t = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        tang.append(t.normalized() if t.length > 1e-9 else Vector((0, 0, 1)))
    frames = []
    if up is not None:
        up = Vector(up).normalized()
        for i in range(n):
            side = tang[i].cross(up)
            if side.length < 1e-6:
                side = Vector((1, 0, 0))
            side.normalize()
            nrm = side.cross(tang[i]).normalized()
            frames.append((tang[i], side, nrm))
        return frames
    # rotation-minimising frames
    t0 = tang[0]
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    side = t0.cross(ref).normalized()
    nrm = side.cross(t0).normalized()
    frames.append((t0, side, nrm))
    for i in range(1, n):
        t = tang[i]
        nrm = (nrm - t * nrm.dot(t))
        if nrm.length < 1e-6:
            nrm = frames[-1][2]
        nrm.normalize()
        side = t.cross(nrm).normalized()
        frames.append((t, side, nrm))
    return frames


def sweep(path, profile, up=None, closed=False, closed_profile=True, scale=None, miter=True, caps=True,
          twist=0.0, bm=None):
    """Sweep a 2D profile [(u, v)] along a 3D path.

    With `up` (plane normal) the frame is planar: u runs in-plane (to the right of the tangent), v along `up`.
    Without `up` the frame is rotation-minimising (tubes). `scale` is a callable t->s or a list per point.
    """
    path = [Vector(p) for p in path]
    n = len(path)
    fresh = bm is None
    if bm is None:
        bm = bmesh.new()
    frames = _frames(path, closed, up)
    rings = []
    m = len(profile)
    for i in range(n):
        t, side, nrm = frames[i]
        s = 1.0
        if scale is not None:
            s = scale(i / max(1, n - 1)) if callable(scale) else scale[i]
        mit = 1.0
        if miter and up is not None and (closed or 0 < i < n - 1):
            seg_t = (path[(i + 1) % n] - path[i]).normalized() if (closed or i < n - 1) else t
            d = max(0.35, t.dot(seg_t))
            mit = 1.0 / d
        ang = twist * i / max(1, n - 1)
        ca, sa = math.cos(ang), math.sin(ang)
        ring = []
        for u, v in profile:
            uu, vv = (u * ca - v * sa), (u * sa + v * ca)
            ring.append(bm.verts.new(path[i] + side * (uu * s * mit) + nrm * (vv * s)))
        rings.append(ring)
    segs = n if closed else n - 1
    pm = m if closed_profile else m - 1
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % n]
        for j in range(pm):
            k = (j + 1) % m
            try:
                bm.faces.new([a[j], a[k], b[k], b[j]])
            except ValueError:
                pass
    if caps and not closed and closed_profile and m > 2:
        try:
            bm.faces.new(list(reversed(rings[0])))
            bm.faces.new(rings[-1])
        except ValueError:
            pass
    if closed_profile and (closed or caps) and fresh:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def circle_pts(r, n, cx=0.0, cy=0.0, a0=0.0, a1=2 * math.pi, closed=True):
    cnt = n if closed else n + 1
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n))
            for i in range(cnt)]


def pointed_arch(w, k=1.0, n=8, leg=0.0, closed=False):
    """2D pointed arch (x, y) from the left springer to the right; two circle arcs of radius k*w.

    With leg > 0 the outline starts/ends `leg` below the springers; closed=True returns a closed lancet outline.
    """
    R = k * w
    xc = -w / 2 + R
    th_apex = math.acos(max(-1.0, min(1.0, (0 - xc) / R)))
    pts = []
    if leg > 0:
        pts.append((-w / 2, -leg))
    for i in range(n + 1):
        a = math.pi + (th_apex - math.pi) * i / n
        pts.append((xc + R * math.cos(a), R * math.sin(a)))
    right = [(-x, y) for x, y in reversed(pts)]
    pts = pts + right[1:]
    return pts


def arch_height(w, k=1.0):
    R = k * w
    xc = -w / 2 + R
    th = math.acos(max(-1.0, min(1.0, -xc / R)))
    return R * math.sin(th)


def foil(lobes, a, b, n=48, rot=0.0):
    """Outline of `lobes` circles of radius b whose centres sit on a circle of radius a (trefoil, quatrefoil...)."""
    pts = []
    centres = [(a * math.cos(rot + 2 * math.pi * i / lobes), a * math.sin(rot + 2 * math.pi * i / lobes))
               for i in range(lobes)]
    for i in range(n):
        phi = rot + 2 * math.pi * i / n + math.pi / lobes
        d = (math.cos(phi), math.sin(phi))
        best = 0.0
        for cx, cy in centres:
            proj = cx * d[0] + cy * d[1]
            perp2 = cx * cx + cy * cy - proj * proj
            if perp2 <= b * b:
                best = max(best, proj + math.sqrt(b * b - perp2))
        pts.append((best * d[0], best * d[1]))
    return pts


def polar_outline(fn, n):
    return [(fn(2 * math.pi * i / n) * math.cos(2 * math.pi * i / n),
             fn(2 * math.pi * i / n) * math.sin(2 * math.pi * i / n)) for i in range(n)]


def catmull(points, n=6, closed=False):
    """Catmull-Rom spline through 3D points, n samples per span."""
    P = [Vector(p) for p in points]
    out = []
    m = len(P)
    spans = m if closed else m - 1
    for i in range(spans):
        p0 = P[(i - 1) % m] if closed else P[max(i - 1, 0)]
        p1 = P[i % m]
        p2 = P[(i + 1) % m] if closed else P[min(i + 1, m - 1)]
        p3 = P[(i + 2) % m] if closed else P[min(i + 2, m - 1)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(P[-1])
    return out


def to3d(pts2, plane="xz", origin=(0, 0, 0)):
    o = Vector(origin)
    if plane == "xz":
        return [o + Vector((x, 0, y)) for x, y in pts2]
    if plane == "xy":
        return [o + Vector((x, y, 0)) for x, y in pts2]
    raise ValueError(plane)


def rib(pts2, width, depth, plane="xz", origin=(0, 0, 0), closed=True, chamfer=0.35, flip=False):
    """Raised moulding rib along a 2D path drawn in a plane; projects `depth` out of the plane."""
    w = width / 2
    c = chamfer
    prof = [(-w, 0), (-w, depth * (1 - c)), (-w * (1 - c), depth), (w * (1 - c), depth), (w, depth * (1 - c)), (w, 0)]
    if plane == "xz":
        up = Vector((0, 1, 0)) if flip else Vector((0, -1, 0))
    else:
        up = Vector((0, 0, 1))
    return sweep(to3d(pts2, plane, origin), prof, up=up, closed=closed, closed_profile=False, caps=False)


def displace(bm, amp, freq, seed=0, mask=None):
    off = Vector((seed * 13.17, seed * 7.31, seed * 3.77))
    for v in bm.verts:
        if mask and not mask(v):
            continue
        d = noise.noise_vector(v.co * freq + off)
        v.co += Vector(d) * amp
    return bm


def rand_rock(rng, size, sub=1, rough=0.25, flat=0.0):
    """Irregular chunk: icosphere, noise-displaced, optionally flattened on one side."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    seed = rng.random() * 100
    for v in bm.verts:
        d = noise.noise(v.co * 1.7 + Vector((seed, seed * 0.5, seed * 0.25)))
        v.co *= (1.0 + rough * d)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if flat > 0:
        zmin = min(v.co.z for v in bm.verts)
        for v in bm.verts:
            if v.co.z < zmin + flat * size[2]:
                v.co.z = zmin + flat * size[2]
    return bm


# ----------------------------------------------------------------------------------------------- objects

def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def bm_to_obj(bm, name, mats):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    for mn in mats:
        me.materials.append(material(mn))
    obj = bpy.data.objects.new(name, me)
    link(obj)
    return obj


def obj_to_bm(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    return bm


def boolean(bm_a, bm_b, op='DIFFERENCE', self_inter=False, mats=("stone",)):
    """Exact boolean of two bmeshes, material indices kept (INDEX mode)."""
    a = bm_to_obj(bm_a, "_bool_a", mats)
    b = bm_to_obj(bm_b, "_bool_b", mats)
    mod = a.modifiers.new("b", 'BOOLEAN')
    mod.operation = op
    mod.solver = 'EXACT'
    mod.object = b
    mod.use_self = self_inter
    mod.use_hole_tolerant = True
    try:
        mod.material_mode = 'INDEX'
    except Exception:
        pass
    dg = bpy.context.evaluated_depsgraph_get()
    ev = a.evaluated_get(dg)
    out = bmesh.new()
    out.from_mesh(ev.to_mesh())
    ev.to_mesh_clear()
    for o in (a, b):
        me = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(me)
    return out


def empty(name, loc, rot=None, size=0.3, quat=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'
    e.empty_display_size = size
    e.location = Vector(loc)
    if quat is not None:
        e.rotation_mode = 'QUATERNION'
        e.rotation_quaternion = quat
    elif rot is not None:
        e.rotation_euler = rot
    link(e)
    return e


def finish(obj, sharp_deg=40.0, weighted=True, uv=True):
    """Smooth shading with sharp edges by angle, weighted normals, smart UVs."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=bm.edges)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    thr = math.radians(sharp_deg)
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
    bm.to_mesh(me)
    bm.free()
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.view_layer.objects:
        o.select_set(o == obj)
    if weighted:
        mod = obj.modifiers.new("wn", 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        mod.weight = 50
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if uv:
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)
    return obj


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def setup_cycles_gpu(samples=32):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception as e:  # CPU fallback
        log("GPU unavailable:", e)
    sc.cycles.samples = samples


def bake_ao(objs, samples=32, distance=1.0):
    """Bake ambient occlusion into a byte colour attribute 'ao' (corner domain), set active for export."""
    sc = bpy.context.scene
    setup_cycles_gpu(samples)
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake_world")
    sc.world.light_settings.distance = distance
    sc.render.bake.target = 'VERTEX_COLORS'
    sc.render.bake.margin = 0
    for obj in objs:
        me = obj.data
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        ca = me.color_attributes.new("ao", 'BYTE_COLOR', 'CORNER')
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
        log("baked ao", obj.name, tris(obj), "tris")


def export_glb(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
        export_normals=True, export_tangents=False, export_materials='EXPORT',
        export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True, export_cameras=False, export_lights=False,
        export_extras=False, export_image_format='NONE')
    log("exported", path)
