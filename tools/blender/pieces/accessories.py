"""Accessory geometry for the fairy pieces: swept tubes and horns, lozenge blades, plates and kite shields,
hoods and helms (skull frame), feathered and folded bat wings, gun barrels, placed knight heads.

Frames: "front frame" as in common.py (x along the surface, z up, outward -y). "Skull frame" is the pawn
skull's own frame (z = 0 at the chin, front -y, before build_pieces.place_skull tilts, scales and lifts it).
"""
import math

import bmesh
import numpy as np
from mathutils import Matrix, Vector

import build_pieces as B
import common as C
import organic as O
from common import BODY, GLOW, TRIM, Profile

D = math.radians


# ---------------------------------------------------------------- transforms

def basis(z_dir, front=(0.0, -1.0, 0.0)):
    """Rotation taking local +Z to z_dir and local -Y as close to `front` as possible."""
    z = Vector(z_dir).normalized()
    f = Vector(front)
    f = f - z * f.dot(z)
    if f.length < 1e-6:
        f = Vector((0.0, 0.0, 1.0)) if abs(z.z) < 0.9 else Vector((0.0, -1.0, 0.0))
        f = f - z * f.dot(z)
    y = -f.normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_4x4()


def place(ob, base, z_dir=(0, 0, 1), front=(0.0, -1.0, 0.0)):
    ob.data.transform(Matrix.Translation(Vector(base)) @ basis(z_dir, front))
    return ob


def transform(objs, m):
    for o in objs:
        o.data.transform(m)
    return objs


def mirror_x(ob):
    ob.data.transform(Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)))
    ob.data.flip_normals()
    return ob


def copy(ob, name=None):
    dup = ob.copy()
    dup.data = ob.data.copy()
    dup.name = name or ob.name
    ob.users_collection[0].objects.link(dup)
    return dup


def mirrored(objs):
    """objs plus their mirror images across x = 0."""
    return list(objs) + [mirror_x(copy(o)) for o in objs]


def stretch(p, z0, z1, dz):
    """Stretch a lathe profile: heights in [z0, z1] scale so the band grows by dz, everything above moves dz."""
    k = 1.0 + dz / (z1 - z0)
    out = []
    for r, z in p.pts:
        if z > z1:
            z = z + dz
        elif z > z0:
            z = z0 + (z - z0) * k
        out.append((r, z))
    p.pts = out
    return p


def close_top(p, r_neck, z_top):
    """Close a profile that ends at a neck with a low dome to the axis."""
    p.to(r_neck, z_top)
    p.bez((r_neck * 0.8, z_top + 0.012), (r_neck * 0.4, z_top + 0.016), (0.0, z_top + 0.016), n=4)
    return p


# ---------------------------------------------------------------- curves and tubes

def bez3(p0, p1, p2, p3, n):
    P = [Vector(p) for p in (p0, p1, p2, p3)]
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append(P[0] * u ** 3 + P[1] * 3 * u * u * t + P[2] * 3 * u * t * t + P[3] * t ** 3)
    return out


def tube(name, pts, radii, segs=10, mat=BODY, caps=True, flat=1.0, ref=None):
    """Circle swept along a polyline with parallel-transport frames; a zero radius closes to a point.
    flat < 1 squashes the section along the frame normal (seeded from `ref`, default world up)."""
    P = [Vector(p) for p in pts]
    n = len(P)
    T = [(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized() for i in range(n)]
    r0 = Vector(ref) if ref is not None else (Vector((0, 0, 1)) if abs(T[0].z) < 0.95 else Vector((0, -1, 0)))
    nrm = (r0 - T[0] * r0.dot(T[0])).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(n):
        if i:
            nrm = T[i - 1].rotation_difference(T[i]) @ nrm
            nrm = (nrm - T[i] * nrm.dot(T[i])).normalized()
        bi = T[i].cross(nrm)
        if radii[i] < 1e-5:
            rings.append([bm.verts.new(P[i])])
            continue
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ring.append(bm.verts.new(P[i] + (nrm * (math.cos(a) * flat) + bi * math.sin(a)) * radii[i]))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        for j in range(segs):
            k = (j + 1) % segs
            if len(a) == 1:
                f = (a[0], b[k], b[j])
            elif len(b) == 1:
                f = (a[j], a[k], b[0])
            else:
                f = (a[j], a[k], b[k], b[j])
            bm.faces.new(f).material_index = mat
    if caps:
        for ring in (rings[0], rings[-1]):
            if len(ring) > 2:
                bm.faces.new(ring).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return C.obj_from_bm(bm, name)


def horn(name, ctrl, r0, n=20, segs=12, ridges=0, ridge_depth=0.10, mat=BODY, taper=0.9):
    """Tapering horn along a cubic Bezier (ctrl = 4 points), optional growth ridges."""
    pts = bez3(*ctrl, n)
    radii = []
    for i in range(n + 1):
        t = i / n
        r = r0 * (1.0 - t) ** taper
        if ridges and t < 0.85:
            r *= 1.0 - ridge_depth * (0.5 - 0.5 * math.cos(2 * math.pi * ridges * t))
        radii.append(r)
    radii[-1] = 0.0
    return C.soften(tube(name, pts, radii, segs, mat), 55)


def lathe_on(prof, name, base=(0, 0, 0), z_dir=(0, 0, 1), segs=24, front=(0.0, -1.0, 0.0), phase=0.0):
    ob = C.lathe(prof, name, segs, phase)
    return place(ob, base, z_dir, front)


def ring(name, r, minor, base=(0, 0, 0), z_dir=(0, 0, 1), segs=32, minor_segs=8, mat=TRIM, flat=1.0):
    """Torus of radius r around z_dir (tube radius minor; flat squashes it along the axis)."""
    pts = [Vector((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), 0.0))
           for i in range(segs)]
    bm = bmesh.new()
    rings_ = []
    for p in pts:
        out = p.normalized()
        rings_.append([bm.verts.new(p + out * minor * math.cos(a) + Vector((0, 0, 1)) * minor * flat * math.sin(a))
                       for a in (2 * math.pi * j / minor_segs for j in range(minor_segs))])
    for i in range(segs):
        a, b = rings_[i], rings_[(i + 1) % segs]
        for j in range(minor_segs):
            k = (j + 1) % minor_segs
            bm.faces.new((a[j], b[j], b[k], a[k])).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = C.obj_from_bm(bm, name)
    return place(ob, base, z_dir)


# ---------------------------------------------------------------- blades and weapons

def lozenge(name, prof_pts, thick_ratio=0.3, mat=TRIM):
    """Blade along +Z with a diamond section: prof_pts [(half_width, z)] from base to tip."""
    p = Profile(0.0, prof_pts[0][1])
    for r, z in prof_pts:
        p.to(r, z, mat)
    p.to(0.0, prof_pts[-1][1] + 1e-4, mat)
    ob = C.lathe(p, name, segs=4)
    ob.data.transform(Matrix.Diagonal((1.0, thick_ratio, 1.0, 1.0)))
    return C.harden(ob, bevel=0.002, segments=1, angle=30)


def leaf_head(name, length, half_w, base_w=0.012, thick_ratio=0.32):
    """Spear head: socket width at z 0, widest at 30 %, point at z = length."""
    pts = [(base_w, 0.0), (half_w * 0.75, length * 0.12), (half_w, length * 0.30), (half_w * 0.92, length * 0.45),
           (half_w * 0.6, length * 0.70), (half_w * 0.25, length * 0.9), (0.002, length)]
    return lozenge(name, pts, thick_ratio)


def sword(name, blade_len, half_w=0.026, grip=0.075, guard=0.075):
    """Short sword pointing +Z from the guard at z 0: blade, crossguard, grip, glowing pommel gem."""
    blade = lozenge(name + "_blade", [(half_w, 0.0), (half_w * 0.95, blade_len * 0.7), (half_w * 0.55, blade_len * 0.9),
                                       (0.002, blade_len)], 0.28)
    xg = B.union_all([C.box(name + "_guard", (0, 0, -0.008), (guard * 2, 0.026, 0.018), TRIM),
                      B.pyramid(name + "_gl", (-guard, 0, -0.008), (-1, 0, 0), 0.018, 0.026, 0.02),
                      B.pyramid(name + "_gr", (guard, 0, -0.008), (1, 0, 0), 0.018, 0.026, 0.02)], name + "_guard")
    C.harden(xg, bevel=0.003, segments=1, angle=30)
    gp = Profile(0.0, -0.017)
    gp.to(0.011, -0.017, TRIM)
    gp.to(0.012, -0.017 - grip, BODY)
    gp.to(0.0, -0.017 - grip, BODY)
    grip_ob = C.lathe(gp, name + "_grip", segs=8)
    pommel = C.uv_sphere(name + "_pommel", (0, 0, -0.03 - grip), (0.019, 0.019, 0.019), segs=10, rings=6, mat=GLOW)
    return [blade, xg, grip_ob, pommel]


def shaft(name, z0, z1, r=0.014, segs=10, mat=BODY):
    p = Profile(0.0, z0)
    p.to(r, z0, mat)
    p.to(r, z1, mat)
    p.to(0.0, z1, mat)
    return C.lathe(p, name, segs=segs)


def collar_ring(name, z, r, h=0.02, mat=TRIM, segs=12):
    p = Profile(0.0, z)
    p.to(r, z, mat)
    p.bead(0.004, h, n=4, mat=mat)
    p.to(0.0, z + h, mat)
    return C.lathe(p, name, segs=segs)


# ---------------------------------------------------------------- plates and shields

def plate(outline, half_t, name, spacing=0.02, r_edge=0.012, pillow=0.004, mat=BODY):
    """Rounded plate from a closed (x, z) outline in the front frame, mid plane y = 0, thickness 2 * half_t."""
    ob = O.inflate(outline, lambda y, z: half_t * np.ones_like(y), name, spacing=spacing, r_edge=r_edge,
                   pillow=pillow, t_min=half_t * 0.45, mat=mat)
    ob.data.transform(Matrix.Rotation(-math.pi / 2, 4, 'Z'))
    return ob


def kite(w, h, n=10):
    """Kite shield outline (x, z), CCW from the front: point at z 0, shoulders near 0.93 h, arched top."""
    side = bez3((0.0, 0.0, 0.0), (w * 0.55, 0.0, h * 0.18), (w * 1.02, 0.0, h * 0.55), (w * 0.97, 0.0, h * 0.92), n)
    top = [(w * 0.97 * math.cos(math.pi * i / n), h * 0.92 + h * 0.08 * math.sin(math.pi * i / n))
           for i in range(1, n)]
    right = [(v.x, v.z) for v in side]
    left = [(-x, z) for x, z in reversed(right)]
    return right + top + left[:-1]


def curve_onto(ob, radius, front_y):
    """Bend a front-frame part around a vertical cylinder of `radius`, its centre line ending at y = front_y."""
    C.wrap(ob, lambda z: radius)
    ob.data.transform(Matrix.Translation((0.0, radius + front_y, 0.0)))
    return ob


def kite_shield(name, w, h, sigil="cross", rim=0.016):
    """Kite shield in the front frame, point at the origin: pillowed plate, silver rim, glowing sigil."""
    half_t = 0.012
    parts = [plate(kite(w, h), half_t, name + "_plate", spacing=0.022, r_edge=0.014)]
    outer = kite(w + 0.006, h + 0.008, 14)
    inner = kite(w - rim, h - rim * 2.2, 14)
    inner = [(x, z + rim * 1.2) for x, z in inner]
    parts.append(C.harden(C.ring_prism(outer, inner, -half_t - 0.010, half_t * 0.5, name + "_rim"), bevel=0.003,
                          segments=1, angle=45))
    zc = h * 0.6
    if sigil == "cross":
        a, b = 0.018, w * 0.52
        pts = [(-a, zc - b * 1.45), (a, zc - b * 1.45), (a, zc - a), (b, zc - a), (b, zc + a), (a, zc + a),
               (a, zc + b * 0.9), (-a, zc + b * 0.9), (-a, zc + a), (-b, zc + a), (-b, zc - a), (-a, zc - a)]
        parts.append(C.prism(pts, -half_t - 0.012, -half_t + 0.004, name + "_sigil", GLOW, GLOW, GLOW))
    elif sigil == "chevron":
        a = 0.022
        pts = [(0.0, zc + 0.05), (w * 0.62, zc - 0.045), (w * 0.62, zc - 0.045 - a * 1.6), (0.0, zc + 0.05 - a * 1.6),
               (-w * 0.62, zc - 0.045 - a * 1.6), (-w * 0.62, zc - 0.045)]
        parts.append(C.prism(pts, -half_t - 0.012, -half_t + 0.004, name + "_sigil", GLOW, GLOW, GLOW))
        g = C.gem(0.0, zc - 0.12, 0.022, 0.034, name + "_gem", proud=0.012, back=0.0)
        g.data.transform(Matrix.Translation((0, -half_t - 0.004, 0)))
        parts.append(g)
    return parts


# ---------------------------------------------------------------- hoods and helms (skull frame)

def hood(name, peak=None, hem=0.245, crown=0.37, opening=None, folds=7, fold_depth=0.05, target=2600, mat=BODY):
    """Cowl over the pawn skull (skull frame): lathed drape from the shoulders (hem radius `hem`) over the
    head (top `crown`), draped folds round the shoulders, optional peak (tip point), face opening and a
    hollow inside so the face sits in shadow."""
    p = Profile(0.0, -0.13)
    p.to(hem - 0.012, -0.13)
    p.bez((hem + 0.004, -0.125), (hem + 0.002, -0.10), (hem - 0.010, -0.08), n=4)
    p.bez((hem - 0.03, -0.03), (0.205, 0.02), (0.200, 0.10), n=6)
    p.bez((0.198, 0.20), (0.16, crown - 0.03), (0.0, crown), n=9)
    ob = C.lathe(p, name, segs=48)
    for v in ob.data.vertices:
        x, y, z = v.co
        th = math.atan2(y, x)
        k = 1.0 + fold_depth * math.cos(folds * th) * float(O.smoothstep(0.06, -0.12, z))
        v.co.x, v.co.y = x * k, y * k * 1.08 + 0.022
    parts = [ob]
    if peak is not None:
        parts.append(C.cone(name + "_peak", (0.0, 0.03, crown - 0.10), peak, 0.115, segs=16))
    ob = C.join(parts, name)
    C.remesh(ob, 0.0055)
    C.smooth(ob, 0.6, 6)
    oc, orad = opening or ((0.0, -0.215, 0.115), (0.122, 0.13, 0.165))
    C.boolean(ob, C.uv_sphere(name + "_opening", oc, orad, segs=32, rings=20))
    C.boolean(ob, C.uv_sphere(name + "_cavity", (0, 0.02, 0.14), (0.172, 0.19, 0.205), segs=32, rings=20))
    C.decimate(ob, target)
    for f in ob.data.polygons:
        f.material_index = mat
    return C.soften(ob, 60)


def ribs(src, name, angles, keep_z, half_w=0.009, thick=0.012):
    """Silver straps running over a lathed dome along meridians at the given angles."""
    out = []
    for k, phi in enumerate(angles):
        nrm = (-math.sin(phi), math.cos(phi), 0.0)
        out.append(C.surface_band(src, (0, 0, 0), nrm, half_w, thick, "%s%d" % (name, k),
                                  keep=lambda c, phi=phi: c.z > keep_z and
                                  c.x * math.cos(phi) + c.y * math.sin(phi) > 0))
    return out


def nasal_helm(name, apex=0.40):
    """Norman spangenhelm over the cranium (skull frame): conical dome (body) with silver rim, ribs and nasal,
    a spike knob and a glowing brow gem."""
    p = Profile(0.0, 0.166)
    p.to(0.150, 0.166, TRIM)
    p.to(0.162, 0.164, TRIM)
    p.up(0.028, TRIM)
    p.to(0.157, 0.194)
    p.bez((0.160, 0.26), (0.085, apex - 0.05), (0.0, apex), n=12)
    helm = C.lathe(p, name, segs=32)
    m = Matrix.Translation((0, 0.026, 0)) @ Matrix.Diagonal((1.0, 1.12, 1.0, 1.0))
    helm.data.transform(m)
    C.harden(helm, bevel=0.003, segments=1, angle=35)
    parts = [helm] + ribs(helm, name + "_rib", B.around(4, D(45)), 0.19)
    tree = C.bvh(helm)
    hit, _n = C.surface_hit(tree, (0.0, -0.6, 0.18), (0, 1, 0))
    nasal = B.union_all([C.box(name + "_nasal", (0.0, hit.y - 0.006, 0.135), (0.030, 0.02, 0.095), TRIM),
                         B.pyramid(name + "_ntip", (0.0, hit.y - 0.006, 0.0875), (0, 0, -1), 0.030, 0.02, 0.016)],
                        name + "_nasal")
    C.harden(nasal, bevel=0.003, segments=1, angle=30)
    parts.append(nasal)
    hit, _n = C.surface_hit(tree, (0.0, -0.6, 0.24), (0, 1, 0))
    g = C.gem(0.0, 0.0, 0.020, 0.028, name + "_gem", proud=0.012, back=0.0)
    g.data.transform(Matrix.Translation((0, hit.y + 0.002, 0.242)) @ Matrix.Rotation(D(-24), 4, 'X'))
    parts.append(g)
    parts.append(C.cone(name + "_knob", (0, 0.026, apex - 0.012), (0, 0.026, apex + 0.03), 0.016, segs=8, mat=TRIM))
    return parts


def kettle_hat(name):
    """Brimmed kettle hat (skull frame): dome (body) with a silver comb, rim band and wide sloping brim."""
    p = Profile(0.0, 0.20)
    p.to(0.150, 0.20, TRIM)
    p.to(0.250, 0.142, TRIM)
    p.to(0.258, 0.150, TRIM)
    p.to(0.252, 0.162, TRIM)
    p.to(0.165, 0.212, TRIM)
    p.up(0.024, TRIM)
    p.to(0.160, 0.238)
    p.bez((0.162, 0.30), (0.11, 0.355), (0.0, 0.362), n=10)
    hat = C.lathe(p, name, segs=36)
    hat.data.transform(Matrix.Translation((0, 0.02, 0)) @ Matrix.Diagonal((1.0, 1.1, 1.0, 1.0)))
    C.harden(hat, bevel=0.003, segments=1, angle=35)
    comb = C.surface_band(hat, (0, 0, 0), (1, 0, 0), 0.011, 0.020, name + "_comb", keep=lambda c: c.z > 0.24)
    parts = [hat, comb]
    for k, phi in enumerate(B.around(4)):
        g = C.gem(0.0, 0.0, 0.016, 0.011, "%s_gem%d" % (name, k), proud=0.010, back=0.004)
        g.data.transform(Matrix.Translation((0, 0, 0.224)))
        C.wrap(g, lambda z: 0.165, phi)
        g.data.transform(Matrix.Translation((0, 0.02, 0)) @ Matrix.Diagonal((1.0, 1.1, 1.0, 1.0)))
        parts.append(g)
    return parts


def cross(name, s=1.0, gem=True, segments=2):
    """The king's cross (pointed, collared ends) scaled by s, base of the stem at the origin, facing -y."""
    w, d, za = 0.06 * s, 0.05 * s, 0.112 * s
    parts = [
        C.box(name + "_stem", (0, 0, 0.08 * s), (w, d, 0.22 * s), TRIM),
        C.box(name + "_arm", (0, 0, za), (0.20 * s, d, 0.056 * s), TRIM),
        B.pyramid(name + "_tt", (0, 0, 0.19 * s), (0, 0, 1), w, d, 0.05 * s),
        B.pyramid(name + "_tl", (-0.10 * s, 0, za), (-1, 0, 0), 0.056 * s, d, 0.04 * s),
        B.pyramid(name + "_tr", (0.10 * s, 0, za), (1, 0, 0), 0.056 * s, d, 0.04 * s),
        C.box(name + "_ct", (0, 0, 0.172 * s), (w + 0.02 * s, d + 0.016 * s, 0.022 * s), TRIM),
        C.box(name + "_cl", (-0.086 * s, 0, za), (0.022 * s, d + 0.016 * s, 0.076 * s), TRIM),
        C.box(name + "_cr", (0.086 * s, 0, za), (0.022 * s, d + 0.016 * s, 0.076 * s), TRIM),
    ]
    ob = B.union_all(parts, name)
    C.harden(ob, bevel=0.004 * s, segments=segments, angle=30)
    out = [ob]
    if gem:
        g = C.gem(0.0, za, 0.016 * s, 0.022 * s, name + "_gem", proud=0.01 * s, back=0.0)
        g.data.transform(Matrix.Translation((0, -d / 2, 0)))
        out.append(g)
    out_m = Matrix.Translation((0, 0, 0.03 * s))
    return transform(out, out_m)


def circlet(name, r=0.158, z=0.215, n=8, blade_h=0.06, gems=True):
    """Simple crown band for the skull: silver band with small points and glowing gems (skull frame)."""
    p = Profile(0.0, z)
    p.to(r - 0.008, z, TRIM)
    p.to(r + 0.004, z, TRIM)
    p.up(0.032, TRIM)
    p.to(r - 0.008, z + 0.034, TRIM)
    p.to(0.0, z + 0.034, TRIM)
    band = C.harden(C.lathe(p, name + "_band", segs=32), bevel=0.003, segments=1)
    parts = [band]
    parts += B.crown_ring(name, n, r - 0.002, z + 0.026, D(10), 0.02, blade_h, 0.014, pinch=0.45)
    if gems:
        for k, phi in enumerate(B.around(4)):
            g = C.gem(0.0, z + 0.016, 0.012, 0.012, "%s_gem%d" % (name, k), proud=0.009, back=0.004)
            C.wrap(g, lambda zz: r + 0.004, phi)
            parts.append(g)
    for o in parts:
        o.data.transform(Matrix.Translation((0, 0.028, 0)) @ Matrix.Diagonal((1.0, 1.1, 1.0, 1.0)))
    return parts


# ---------------------------------------------------------------- wings

def wing_frame(root, span, up):
    """Local wing frame: +x along the span, +z toward the leading edge (up), the wing's face toward -y."""
    X = Vector(span).normalized()
    Z = Vector(up)
    Z = (Z - X * Z.dot(X)).normalized()
    Y = Z.cross(X)
    return Matrix.Translation(Vector(root)) @ Matrix((X, Y, Z)).transposed().to_4x4()


def _wing_layer(length, n, f_len, sweep, droop, lift, u0=0.08):
    arm = bez3((0, 0, 0), (length * 0.35, 0, lift), (length * 0.7, 0, lift * 0.7), (length, 0, -droop), 40)
    anchors, tips = [], []
    for i in range(n):
        t = i / max(n - 1, 1)
        a = arm[int(round((u0 + (1.0 - u0) * t) * 40))]
        ang = sweep[0] + (sweep[1] - sweep[0]) * t ** 1.2
        ln = f_len[0] + (f_len[1] - f_len[0]) * t ** 0.9
        anchors.append(a)
        tips.append(a + Vector((math.sin(ang), 0.0, -math.cos(ang))) * ln)
    outline = [(v.x, v.z) for v in arm[::4]]
    for i in reversed(range(n)):
        outline.append((tips[i].x, tips[i].z))
        if i:
            mid_a = (anchors[i] + anchors[i - 1]) / 2
            mid_t = (tips[i] + tips[i - 1]) / 2
            nv = mid_a.lerp(mid_t, 0.70)
            outline.append((nv.x, nv.z))
    outline.append((0.0, -f_len[0] * 0.55))
    return arm, outline


def plate_wing(name, length, n=7, f_len=(0.14, 0.30), sweep=(D(18), D(80)), droop=0.03, lift=0.05,
               coverts=0.5, thick=0.011, arm_r=0.018, gem=True, spacing=0.03, edge=0.012):
    """Folded feathered wing as layered plates in its own frame (x = span from the root at the origin,
    feathers hang toward -z and trail toward +x, face toward -y): long primaries, a covert row on top,
    silver leading-edge arm, glowing gem at the root. Place it with wing_frame()."""
    arm, outline = _wing_layer(length, n, f_len, sweep, droop, lift)
    parts = [plate_xz(outline, thick, name + "_primaries", spacing, edge)]
    if coverts:
        _arm, out2 = _wing_layer(length * 0.82, n - 1, (f_len[0] * coverts, f_len[1] * coverts * 0.9),
                                 (sweep[0] + D(6), sweep[1] - D(4)), droop * 0.8, lift, u0=0.05)
        cov = plate_xz(out2, thick, name + "_coverts", spacing, edge)
        cov.data.transform(Matrix.Translation((0.0, -thick * 1.6, 0.004)))
        parts.append(cov)
    parts.append(tube(name + "_arm", [a + Vector((0, -thick * 2.2, 0)) for a in arm[::4]],
                      [arm_r * (1.0 - 0.65 * i / 10) for i in range(11)], segs=8, mat=TRIM))
    if gem:
        g = C.gem(0.0, 0.0, 0.020, 0.026, name + "_gem", proud=0.012, back=0.004)
        g.data.transform(Matrix.Translation((length * 0.10, -thick * 2.2 - arm_r - 0.004, -0.008)))
        parts.append(g)
    return parts


def plate_xz(outline, half_t, name, spacing, edge):
    ob = O.inflate(outline, lambda y, z: half_t * np.ones_like(y), name, spacing=spacing, r_edge=half_t * 1.2,
                   pillow=half_t * 0.3, t_min=half_t * 0.4, edge_spacing=edge)
    ob.data.transform(Matrix.Rotation(-math.pi / 2, 4, 'Z'))
    return ob


def feather_wing(name, length, n=8, chord=0.22, f_len=(0.14, 0.30), f_w=(0.030, 0.026), sweep=(D(20), D(78)),
                 thick=0.012, arm_r=0.020, arm_mat=TRIM, gem=True, coverts=True, curl=0.0):
    """Folded bird wing in its own frame (x = span from the root at the origin, feathers hang toward -z
    and trail toward +x). Returns parts; place them with wing_frame()."""
    parts = []
    arm = bez3((0, 0, 0), (length * 0.35, 0, 0.03), (length * 0.7, 0, 0.02), (length, 0, -0.03 - curl), 10)
    parts.append(tube(name + "_arm", arm, [arm_r * (1.0 - 0.6 * i / 10) for i in range(11)], segs=8, mat=arm_mat))
    for i in range(n):
        t = i / max(n - 1, 1)
        u = 0.06 + 0.92 * t
        anchor = bez3((0, 0, 0), (length * 0.35, 0, 0.03), (length * 0.7, 0, 0.02), (length, 0, -0.03 - curl),
                      40)[int(round(u * 40))]
        ang = sweep[0] + (sweep[1] - sweep[0]) * t ** 1.3
        ln = f_len[0] + (f_len[1] - f_len[0]) * t ** 0.8
        hw = f_w[0] + (f_w[1] - f_w[0]) * t
        f = B.blade("%s_f%d" % (name, i), hw, ln, thick, mat=BODY, pinch=0.82)
        f.data.transform(Matrix.Rotation(math.pi - ang, 4, 'Y'))  # +z (blade tip) -> down, trailing toward +x
        f.data.transform(Matrix.Translation(anchor + Vector((0.0, -0.004 * i, 0.012))))
        parts.append(f)
    if coverts:
        for i in range(n - 2):
            t = i / max(n - 3, 1)
            anchor = bez3((0, 0, 0), (length * 0.35, 0, 0.03), (length * 0.7, 0, 0.02), (length, 0, -0.03 - curl),
                          40)[int(round((0.04 + 0.7 * t) * 40))]
            ang = sweep[0] * 0.6 + (sweep[1] * 0.75 - sweep[0] * 0.6) * t
            f = B.blade("%s_c%d" % (name, i), f_w[0] * 0.95, f_len[0] * 0.62, thick, mat=BODY, pinch=0.85)
            f.data.transform(Matrix.Rotation(math.pi - ang, 4, 'Y'))
            f.data.transform(Matrix.Translation(anchor + Vector((0.0, -0.004 * n - 0.006 - 0.003 * i, 0.008))))
            parts.append(f)
    if gem:
        g = C.gem(0.0, 0.0, 0.020, 0.026, name + "_gem", proud=0.012, back=0.004)
        g.data.transform(Matrix.Translation((length * 0.16, -0.004 * n - arm_r - 0.006, 0.0)))
        parts.append(g)
    return parts


def bat_wing(name, apex, tips, shoulder, radius, phi, claw=0.05, scallop=0.07, spacing=0.024):
    """Folded bat/dragon wing wrapped round the piece at angle phi: membrane between the wrist (apex), the
    shoulder and the finger tips (left to right), silver finger bones, a claw at the wrist. Front-frame (x, z)."""
    outline = [apex, shoulder]
    for a, b in zip(tips, tips[1:]):
        outline.append(a)
        outline.append(((a[0] + b[0]) / 2, max(a[1], b[1]) + scallop))
    outline.append(tips[-1])
    mem = plate(outline, 0.007, name + "_membrane", spacing=spacing, r_edge=0.01, pillow=0.002)
    rad = radius
    parts = [mem]
    for k, tip in enumerate([shoulder] + list(tips)):
        pts = [Vector((apex[0] + (tip[0] - apex[0]) * t, -0.010, apex[1] + (tip[1] - apex[1]) * t))
               for t in (i / 8 for i in range(9))]
        parts.append(tube("%s_bone%d" % (name, k), pts, [0.013 - 0.008 * i / 8 for i in range(9)], segs=6,
                          mat=TRIM))
    parts.append(C.cone(name + "_claw", (apex[0], -0.012, apex[1] - 0.02), (apex[0] + 0.012, -0.03, apex[1] + claw),
                        0.018, segs=8, mat=TRIM))
    g = C.gem(apex[0], apex[1] - 0.07, 0.016, 0.024, name + "_gem", proud=0.012, back=0.004)
    g.data.transform(Matrix.Translation((0, -0.012, 0)))
    parts.append(g)
    for o in parts:
        C.wrap(o, rad, phi)
    return parts


# ---------------------------------------------------------------- guns

def barrel(name, length, r_breech, r_muzzle, bore, rings=(0.22, 0.62), flare=1.3, knob=True, segs=20):
    """Gun barrel along +Z (breech at z 0, muzzle at `length`); the bore floor glows. Lathe."""
    p = Profile(0.0, -0.05 if knob else 0.0)
    if knob:
        p.arc((0.026, -0.032), (0.012, -0.014), n=5, mat=TRIM)
        p.to(0.012, -0.006, TRIM)
        p.to(r_breech * 0.8, 0.0, TRIM)
    else:
        p.to(r_breech * 0.8, 0.0, TRIM)
    p.bez((r_breech * 0.98, 0.004), (r_breech, 0.02), (r_breech, 0.04), n=4)
    L = length
    for zr in rings:
        z = L * zr
        r = r_breech + (r_muzzle - r_breech) * zr
        p.to(r, z - 0.012)
        p.to(r + 0.012, z - 0.008, TRIM)
        p.bead(0.006, 0.020, n=4, mat=TRIM)
        p.to(r, z + 0.016)
    p.to(r_muzzle, L * 0.86)
    p.bez((r_muzzle * 1.05, L * 0.93), (r_muzzle * flare, L * 0.96), (r_muzzle * flare, L), n=5)
    p.to(r_muzzle * flare + 0.004, L + 0.004, TRIM)
    p.up(0.014, TRIM)
    p.to(bore + 0.006, L + 0.02, TRIM)
    p.to(bore, L + 0.012, TRIM)
    p.to(bore, L - 0.05)
    p.to(bore * 0.98, L - 0.07, GLOW)
    p.to(0.0, L - 0.075, GLOW)
    ob = C.lathe(p, name, segs=segs)
    return C.harden(ob, bevel=0.003, segments=1, angle=40)


# ---------------------------------------------------------------- knight heads

def knight_on(scale, base, target=4200, ears=True, mane=True, bridle=None, extra=None, tilt=0.0):
    """Knight head (eyes, bridle) scaled and placed with its neck base at `base` (knight frame neck is at
    z 0.335). bridle: None = no tack, else kwargs for knight_bridle. extra(head) may add knight-frame parts.
    Returns (head, parts)."""
    head, eyes = B.knight_head(target, ears, mane)
    for e in eyes:
        C.decimate(e, 120)
    parts = [head] + eyes
    if bridle is not None:
        parts += B.knight_bridle(head, **bridle)
    if extra is not None:
        parts += extra(head)
    m = Matrix.Translation(Vector(base)) @ Matrix.Rotation(tilt, 4, 'X') @ Matrix.Scale(scale, 4) @ \
        Matrix.Translation((0, 0, -0.335))
    transform(parts, m)
    return head, parts
