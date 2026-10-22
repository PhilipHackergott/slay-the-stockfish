"""Geometry, material, animation and export helpers for the chess piece builds (Blender 5.2, headless).

Conventions: metres, Blender Z up, origin at the centre of the bottom face, the piece's front faces -Y.
Decals (gems, frames, cutters) are authored in a flat "front frame": x along the surface, z up, the surface
at y = 0 and outward = -y; `wrap()` bends them onto a surface of revolution.
"""
import math
import os
import sys

import bmesh
import bpy
from bpy_extras import anim_utils
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

BODY, TRIM, GLOW = 0, 1, 2
MAT_NAMES = ("piece_body", "piece_trim", "piece_glow")
FPS = 60  # 0.55 s and 0.75 s are half frames at 30 fps; the glTF exporter truncates strip ends to whole frames
FRONT = -math.pi / 2

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BUILD = os.path.join(ROOT, "build", "blender", "pieces")
MODELS = os.path.join(ROOT, "models", "pieces")
PORTRAITS = os.path.join(ROOT, "art", "portraits")
PIECES = ("king", "queen", "rook", "bishop", "knight", "pawn")
HEIGHTS = {"pawn": 0.85, "rook": 1.00, "knight": 1.10, "bishop": 1.20, "queen": 1.45, "king": 1.60}


def script_args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    return scene


# ---------------------------------------------------------------- materials

EXPORT_LOOK = {
    "piece_body": dict(base=(0.72, 0.65, 0.52), rough=0.55, metal=0.0, emit=0.0),
    "piece_trim": dict(base=(0.62, 0.62, 0.64), rough=0.38, metal=1.0, emit=0.0),
    "piece_glow": dict(base=(0.30, 0.62, 1.00), rough=0.40, metal=0.0, emit=4.0),
}


def principled(mat):
    for n in mat.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            return n
    raise RuntimeError("no principled node in " + mat.name)


def piece_materials():
    mats = []
    for name in MAT_NAMES:
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            look = EXPORT_LOOK[name]
            bsdf = principled(mat)
            bsdf.inputs["Base Color"].default_value = (*look["base"], 1.0)
            bsdf.inputs["Roughness"].default_value = look["rough"]
            bsdf.inputs["Metallic"].default_value = look["metal"]
            if look["emit"]:
                bsdf.inputs["Emission Color"].default_value = (*look["base"], 1.0)
                bsdf.inputs["Emission Strength"].default_value = look["emit"]
        mats.append(mat)
    return mats


# ---------------------------------------------------------------- mesh plumbing

def obj_from_bm(bm, name, smooth=True):
    me = bpy.data.meshes.new(name)
    for f in bm.faces:
        f.smooth = smooth
    bm.to_mesh(me)
    bm.free()
    for m in piece_materials():
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def apply_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob


def apply_transform(ob):
    ob.data.transform(ob.matrix_basis)
    ob.matrix_basis = Matrix.Identity(4)
    return ob


def delete(ob):
    me = ob.data
    bpy.data.objects.remove(ob)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    for o in objs:
        apply_transform(o)
    with bpy.context.temp_override(active_object=objs[0], object=objs[0],
                                   selected_objects=objs, selected_editable_objects=objs):
        bpy.ops.object.join()
    ob = objs[0]
    ob.name = name
    ob.data.name = name
    return ob


def mesh_volume(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    vol = abs(bm.calc_volume(signed=False))
    bm.free()
    return vol


def boolean(ob, cutter, op='DIFFERENCE', keep_cutter=False):
    """Boolean with a sanity check on the result volume; tries EXACT, then MANIFOLD, else skips the cut."""
    v_ob = mesh_volume(ob.data)
    v_cut = mesh_volume(cutter.data)
    cutter.hide_render = True
    cutter.display_type = 'WIRE'
    if op == 'DIFFERENCE':
        lo, hi = v_ob - v_cut - 1e-6, v_ob + 1e-6
    else:
        lo, hi = max(v_ob, v_cut) - 1e-6, v_ob + v_cut + 1e-6
    ok = False
    for solver in ('EXACT', 'MANIFOLD'):
        mod = ob.modifiers.new("bool", 'BOOLEAN')
        mod.operation = op
        mod.solver = solver
        mod.object = cutter
        mod.material_mode = 'TRANSFER'
        dg = bpy.context.evaluated_depsgraph_get()
        res = ob.evaluated_get(dg).data
        vol = mesh_volume(res)
        if lo <= vol <= hi and len(res.vertices) > 0.5 * len(ob.data.vertices):
            apply_mods(ob)
            ok = True
            break
        ob.modifiers.remove(mod)
    if not ok:
        print("WARNING boolean %s %s on %s rejected (volume check), cut skipped" % (op, cutter.name, ob.name))
    if not keep_cutter:
        delete(cutter)
    return ob


def harden(ob, bevel=0.006, segments=2, angle=40.0):
    """Smooth shading, sharp edges above `angle`, small bevel on those edges with hardened normals."""
    me = ob.data
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(angle))
    if bevel > 0:
        mod = ob.modifiers.new("bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(angle)
        mod.use_clamp_overlap = True
        mod.harden_normals = True
        mod.miter_outer = 'MITER_ARC'
        apply_mods(ob)
    return ob


def soften(ob, angle=75.0):
    ob.data.shade_smooth()
    ob.data.set_sharp_from_angle(angle=math.radians(angle))
    return ob


def remesh(ob, voxel=0.006):
    mod = ob.modifiers.new("remesh", 'REMESH')
    mod.mode = 'VOXEL'
    mod.voxel_size = voxel
    mod.adaptivity = 0.0
    mod.use_smooth_shade = True
    return apply_mods(ob)


def smooth(ob, factor=0.5, iterations=4):
    mod = ob.modifiers.new("smooth", 'SMOOTH')
    mod.factor = factor
    mod.iterations = iterations
    return apply_mods(ob)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def decimate(ob, target_tris):
    tris = tri_count(ob)
    if tris > target_tris:
        mod = ob.modifiers.new("decimate", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = target_tris / tris
        mod.use_collapse_triangulate = True
        apply_mods(ob)
    return ob


def set_material(ob, index):
    for p in ob.data.polygons:
        p.material_index = index
    return ob


def bvh(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def surface_hit(tree, origin, direction):
    loc, normal, _i, _d = tree.ray_cast(Vector(origin), Vector(direction).normalized())
    if loc is None:
        raise RuntimeError("ray missed the surface from %s" % (origin,))
    return loc, normal


# ---------------------------------------------------------------- lathe

def _circumcentre(a, b, c):
    ax, ay = a
    bx, by = b
    cx, cy = c
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
    return ux, uy


class Profile:
    """Lathe profile of (r, z) points from the axis at the bottom to the axis at the top (or into a hollow).
    Every segment carries a material index."""

    def __init__(self, r=0.0, z=0.0):
        self.pts = [(r, z)]
        self.mats = []

    @property
    def cur(self):
        return self.pts[-1]

    def to(self, r, z, mat=BODY):
        if (abs(r - self.cur[0]) + abs(z - self.cur[1])) > 1e-6:
            self.pts.append((r, z))
            self.mats.append(mat)
        return self

    def up(self, dz, mat=BODY):
        return self.to(self.cur[0], self.cur[1] + dz, mat)

    def arc(self, mid, end, n=6, mat=BODY):
        """Circular arc from the current point through `mid` to `end`."""
        p0 = self.cur
        cx, cy = _circumcentre(p0, mid, end)
        rad = math.hypot(p0[0] - cx, p0[1] - cy)
        a0 = math.atan2(p0[1] - cy, p0[0] - cx)
        a1 = math.atan2(mid[1] - cy, mid[0] - cx)
        a2 = math.atan2(end[1] - cy, end[0] - cx)
        tau = 2 * math.pi
        if (a1 - a0) % tau <= (a2 - a0) % tau:
            sweep = (a2 - a0) % tau
        else:
            sweep = -((a0 - a2) % tau)
        for i in range(1, n):
            a = a0 + sweep * i / n
            self.to(cx + rad * math.cos(a), cy + rad * math.sin(a), mat)
        return self.to(end[0], end[1], mat)

    def bead(self, bulge, height, n=6, mat=BODY):
        """Half-round bead straight up from the current point."""
        r, z = self.cur
        return self.arc((r + bulge, z + height / 2), (r, z + height), n, mat)

    def bez(self, c1, c2, end, n=10, mat=BODY):
        p0 = self.cur
        for i in range(1, n + 1):
            t = i / n
            u = 1 - t
            r = u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * end[0]
            z = u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * end[1]
            self.to(r, z, mat)
        return self

    def radius_fn(self):
        """Outer radius at height z (max over the profile segments crossing z)."""
        segs = list(zip(self.pts[:-1], self.pts[1:]))

        def radius(z):
            best = 0.0
            for (r0, z0), (r1, z1) in segs:
                if z0 == z1:
                    if abs(z - z0) < 1e-6:
                        best = max(best, r0, r1)
                    continue
                if (z0 - z) * (z1 - z) <= 0:
                    best = max(best, r0 + (z - z0) / (z1 - z0) * (r1 - r0))
            return max(best, 0.005)
        return radius


def lathe(prof, name, segs=48, phase=0.0):
    bm = bmesh.new()
    angles = [phase + 2 * math.pi * j / segs for j in range(segs)]
    rings = []
    for r, z in prof.pts:
        if r < 1e-5:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for a in angles])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for j in range(segs):
            k = (j + 1) % segs
            if len(a) == 1:
                f = bm.faces.new((a[0], b[k], b[j]))
            elif len(b) == 1:
                f = bm.faces.new((a[j], a[k], b[0]))
            else:
                f = bm.faces.new((a[j], a[k], b[k], b[j]))
            f.material_index = prof.mats[i]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(bm, name)


# ---------------------------------------------------------------- decals (front frame) and wrapping

def wrap(ob, radius, phi=FRONT, inset=0.0):
    """Bend a front-frame part onto the surface of revolution radius(z), centred on angle phi."""
    for v in ob.data.vertices:
        x, y, z = v.co
        r = radius(z)
        th = phi + x / r
        rr = r - y - inset
        v.co = (rr * math.cos(th), rr * math.sin(th), z)
    ob.data.update()
    return ob


def resample(pts, per_edge):
    """Closed polygon -> per_edge points on every edge (same count for matching loops)."""
    out = []
    n = len(pts)
    for i in range(n):
        a = Vector(pts[i])
        b = Vector(pts[(i + 1) % n])
        for j in range(per_edge):
            out.append(tuple(a.lerp(b, j / per_edge)))
    return out


def prism(pts, y_front, y_back, name, mat_front=BODY, mat_back=BODY, mat_side=BODY, smooth=False):
    """Closed prism from a CCW (x, z) polygon (as seen from -Y), between y_front (outer) and y_back."""
    bm = bmesh.new()
    fr = [bm.verts.new((x, y_front, z)) for x, z in pts]
    bk = [bm.verts.new((x, y_back, z)) for x, z in pts]
    bm.faces.new(fr).material_index = mat_front
    bm.faces.new(list(reversed(bk))).material_index = mat_back
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((fr[i], bk[i], bk[j], fr[j])).material_index = mat_side
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(bm, name, smooth)


def ring_prism(outer, inner, y_front, y_back, name, mat=TRIM):
    """Closed frame between two loops with the same point count."""
    bm = bmesh.new()
    of = [bm.verts.new((x, y_front, z)) for x, z in outer]
    ob_ = [bm.verts.new((x, y_back, z)) for x, z in outer]
    inf = [bm.verts.new((x, y_front, z)) for x, z in inner]
    ib = [bm.verts.new((x, y_back, z)) for x, z in inner]
    n = len(outer)
    for i in range(n):
        j = (i + 1) % n
        for quad in ((of[i], of[j], inf[j], inf[i]), (ob_[j], ob_[i], ib[i], ib[j]),
                     (ob_[i], ob_[j], of[j], of[i]), (ib[j], ib[i], inf[i], inf[j])):
            bm.faces.new(quad).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(bm, name, smooth=False)


def gem(cx, cz, w, h, name, proud=0.014, back=0.03, mat=GLOW):
    """Faceted diamond gem in the front frame; corners sit on the surface."""
    bm = bmesh.new()
    front = bm.verts.new((cx, -proud, cz))
    rear = bm.verts.new((cx, back, cz))
    ring = [bm.verts.new(p) for p in ((cx + w, 0.003, cz), (cx, 0.003, cz + h), (cx - w, 0.003, cz),
                                     (cx, 0.003, cz - h))]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((ring[i], ring[j], front)).material_index = mat
        bm.faces.new((ring[j], ring[i], rear)).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return obj_from_bm(bm, name, smooth=False)


def diamond(cx, cz, w, h):
    return [(cx + w, cz), (cx, cz + h), (cx - w, cz), (cx, cz - h)]


def gem_set(radius, cz, w, h, name, phis, frame=0.016, per_edge=2):
    """Gems with a metal diamond frame at each angle in phis; returns the list of objects."""
    parts = []
    for k, phi in enumerate(phis):
        g = gem(0.0, cz, w, h, "%s_gem%d" % (name, k))
        outer = resample(diamond(0.0, cz, w + frame, h + frame * 1.35), per_edge)
        inner = resample(diamond(0.0, cz, w, h), per_edge)
        fr = ring_prism(outer, inner, -0.008, 0.012, "%s_frame%d" % (name, k))
        for o in (g, fr):
            wrap(o, radius, phi)
        parts += [g, fr]
    return parts


def surface_band(src, co, no, half_width, thick, name, keep=None, mat=TRIM, offset=0.4):
    """Metal strap that hugs src: its faces between two parallel planes, solidified outward."""
    bm = bmesh.new()
    bm.from_mesh(src.data)
    bm.transform(src.matrix_world)
    co = Vector(co)
    no = Vector(no).normalized()
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co + no * half_width,
                           plane_no=no, clear_outer=True)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co - no * half_width,
                           plane_no=no, clear_inner=True)
    if keep is not None:
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(f.calc_center_median())], context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    for f in bm.faces:
        f.material_index = mat
    ob = obj_from_bm(bm, name)
    mod = ob.modifiers.new("solid", 'SOLIDIFY')
    mod.thickness = thick
    mod.offset = offset
    mod.use_rim = True
    mod.use_even_offset = True
    mod.material_offset_rim = 0
    apply_mods(ob)
    ob.data.shade_smooth()
    ob.data.set_sharp_from_angle(angle=math.radians(50))
    return ob


# ---------------------------------------------------------------- primitives

def uv_sphere(name, centre, radii, segs=16, rings=10, mat=BODY):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    bm.transform(Matrix.Diagonal((*radii, 1.0)))
    bm.transform(Matrix.Translation(Vector(centre)))
    for f in bm.faces:
        f.material_index = mat
    return obj_from_bm(bm, name)


def box(name, centre, size, mat=BODY):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.transform(Matrix.Diagonal((*size, 1.0)))
    bm.transform(Matrix.Translation(Vector(centre)))
    for f in bm.faces:
        f.material_index = mat
    return obj_from_bm(bm, name, smooth=False)


def cone(name, base, tip, r_base, segs=10, flatten=(1.0, 1.0), mat=BODY):
    """Cone from base centre to tip, cross-section scaled by flatten in the base's local x/y."""
    base = Vector(base)
    tip = Vector(tip)
    axis = tip - base
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_base, radius2=0.0,
                          depth=axis.length)
    bm.transform(Matrix.Translation(Vector((0, 0, axis.length / 2))))
    bm.transform(Matrix.Diagonal((flatten[0], flatten[1], 1.0, 1.0)))
    rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    bm.transform(rot)
    bm.transform(Matrix.Translation(base))
    for f in bm.faces:
        f.material_index = mat
    return obj_from_bm(bm, name, smooth=False)


# ---------------------------------------------------------------- AO, UVs

def ensure_world():
    world = bpy.data.worlds.get("bake_world") or bpy.data.worlds.new("bake_world")
    bpy.context.scene.world = world
    return world


def use_gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == 'METAL'
        scene.cycles.device = 'GPU'
    except Exception as exc:  # CPU fallback is fine, just slower
        print("GPU unavailable, using CPU:", exc)
        scene.cycles.device = 'CPU'


def white_ao(ob):
    """Placeholder 'ao' attribute (all white) for quick builds without the bake."""
    me = ob.data
    attr = me.color_attributes.get("ao") or me.color_attributes.new("ao", 'FLOAT_COLOR', 'CORNER')
    for d in attr.data:
        d.color = (1.0, 1.0, 1.0, 1.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    return attr


def bake_ao(ob, samples=48, distance=0.25):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    use_gpu(scene)
    scene.cycles.samples = samples
    world = ensure_world()
    world.light_settings.distance = distance
    me = ob.data
    attr = me.color_attributes.get("ao") or me.color_attributes.new("ao", 'FLOAT_COLOR', 'CORNER')
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for o in scene.objects:
        o.select_set(o is ob)
    bpy.context.view_layer.objects.active = ob
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.render.bake.use_selected_to_active = False
    bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
    return attr


def smart_uv(ob):
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    bpy.context.view_layer.objects.active = ob
    if not ob.data.uv_layers:
        ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode='OBJECT')


# ---------------------------------------------------------------- animation

CHANNELS = (("location", 0), ("location", 1), ("location", 2), ("rotation_euler", 0), ("rotation_euler", 1),
            ("rotation_euler", 2), ("scale", 0), ("scale", 1), ("scale", 2))
REST = {("location", i): 0.0 for i in range(3)}
REST.update({("rotation_euler", i): 0.0 for i in range(3)})
REST.update({("scale", i): 1.0 for i in range(3)})


def _set_keys(fc, keys):
    """keys: [(t_seconds, value[, slope_in[, slope_out]])], slopes in units/s; None = auto-clamped."""
    keys = sorted(keys, key=lambda k: k[0])
    pts = []
    for k in keys:
        kp = fc.keyframe_points.insert(k[0] * FPS, k[1], options={'FAST'})
        kp.interpolation = 'BEZIER'
        kp.handle_left_type = 'AUTO_CLAMPED'
        kp.handle_right_type = 'AUTO_CLAMPED'
        pts.append(kp)
    fc.update()
    for i, k in enumerate(keys):
        s_in = k[2] if len(k) > 2 else None
        s_out = k[3] if len(k) > 3 else s_in
        if s_in is None and s_out is None:
            continue
        kp = pts[i]
        f, v = kp.co
        if s_in is not None and i > 0:
            dt = (f - pts[i - 1].co[0]) / 3
            kp.handle_left_type = 'FREE'
            kp.handle_left = (f - dt, v - s_in * dt / FPS)
        if s_out is not None and i < len(keys) - 1:
            dt = (pts[i + 1].co[0] - f) / 3
            kp.handle_right_type = 'FREE'
            kp.handle_right = (f + dt, v + s_out * dt / FPS)
    fc.update()


def add_clip(ob, name, duration, channels):
    """One action per clip on ob, every transform channel keyed (missing channels hold rest),
    pushed to its own muted NLA track named like the clip."""
    ad = ob.animation_data_create()
    act = bpy.data.actions.new(name)
    slot = act.slots.new(id_type='OBJECT', name=ob.name)
    ad.action = act
    ad.action_slot = slot
    bag = anim_utils.action_ensure_channelbag_for_slot(act, slot)
    for path, idx in CHANNELS:
        keys = channels.get((path, idx))
        if keys is None:
            rest = REST[(path, idx)]
            keys = [(0.0, rest), (duration, rest)]
        fc = bag.fcurves.new(path, index=idx)
        _set_keys(fc, keys)
    ad.action = None
    track = ad.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, act)
    strip.action_slot = slot
    strip.extrapolation = 'NOTHING'
    strip.frame_end = duration * FPS
    track.mute = True
    act.use_fake_user = True
    return act


# ---------------------------------------------------------------- export

def export_glb(ob, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o is ob)
    bpy.context.view_layer.objects.active = ob
    bpy.context.scene.frame_set(0)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials='EXPORT',
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_force_sampling=True,
        export_frame_step=1,
        export_anim_slide_to_zero=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_object=True,
        export_bake_animation=False,
        export_current_frame=False,
    )
