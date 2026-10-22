"""Build the six chess pieces, bake AO, add the clips and export models/pieces/<piece>.glb.

Blender --background --factory-startup --python build_pieces.py -- [--only king,pawn] [--no-ao]
"""
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import anims  # noqa: E402
import common as C  # noqa: E402
import organic as O  # noqa: E402
from common import BODY, GLOW, TRIM, Profile  # noqa: E402

D = math.radians
SEGS = 36


# ---------------------------------------------------------------- shared parts

def plinth(R):
    """Bottom face, plinth with chamfer, half-round bead, ledge. Ends near (R - 0.058, 0.115)."""
    p = Profile(0.0, 0.0)
    p.to(R, 0.0)
    p.to(R, 0.036)
    p.to(R - 0.012, 0.048)
    p.to(R - 0.026, 0.050)
    p.bead(0.016, 0.046, n=6)
    p.to(R - 0.045, 0.100)
    p.up(0.012)
    p.to(R - 0.058, 0.115)
    return p


def lower_body(p, torus_r, band_r):
    """Big torus, silver band, ready for the piece's bell."""
    r, z = p.cur
    p.arc((torus_r, z + 0.032), (band_r + 0.012, z + 0.064), n=7)
    p.to(band_r, z + 0.068)
    p.up(0.017, TRIM)
    p.to(band_r - 0.008, p.cur[1] + 0.004)
    return p


def collar(p, z, disc_r, band_r, ring_r, neck_r):
    """Collar under the head: chamfered disc, silver band, small ring. Starts at height z."""
    p.to(disc_r - 0.045, z)
    p.to(disc_r, z + 0.018)
    p.bead(0.012, 0.030)
    p.to(band_r, p.cur[1] + 0.005)
    p.up(0.022, TRIM)
    p.to(ring_r, p.cur[1] + 0.004)
    p.bead(0.008, 0.020)
    p.to(neck_r, p.cur[1] + 0.007)
    return p


def blade(name, half_w, height, thick, mat=TRIM, pinch=0.6):
    """Pointed crown leaf/spike in the front frame, base on z = 0."""
    pts = [(-half_w, 0.0), (half_w, 0.0)]
    side = [(1.04, 0.25), (0.92, 0.5), (pinch, 0.75)]
    pts += [(half_w * a, height * b) for a, b in side]
    pts.append((0.0, height))
    pts += [(-half_w * a, height * b) for a, b in reversed(side)]
    ob = C.prism(pts, -thick / 2, thick / 2, name, mat, mat, mat)
    return C.harden(ob, bevel=0.005, segments=2, angle=30)


def place_around(ob, phi, radius, z, tilt):
    """Lean the front-frame part outward by tilt, move it to radius/z and turn it to angle phi."""
    m = Matrix.Rotation(phi + math.pi / 2, 4, 'Z') @ Matrix.Translation((0.0, -radius, z)) @ \
        Matrix.Rotation(tilt, 4, 'X')
    ob.data.transform(m)
    return ob


def crown_ring(name, n, radius, z, tilt, half_w, height, thick, gem_size=None, phase=0.0, pinch=0.6):
    parts = []
    for k in range(n):
        phi = C.FRONT + phase + 2 * math.pi * k / n
        b = blade("%s_blade%d" % (name, k), half_w, height, thick, pinch=pinch)
        place_around(b, phi, radius, z, tilt)
        parts.append(b)
        if gem_size:
            g = C.gem(0.0, height * 0.36, gem_size[0], gem_size[1], "%s_bgem%d" % (name, k), proud=0.008,
                      back=0.01)
            g.data.transform(Matrix.Translation((0.0, -thick / 2, 0.0)))
            place_around(g, phi, radius, z, tilt)
            parts.append(g)
    return parts


def around(n, phase=0.0):
    return [C.FRONT + phase + 2 * math.pi * k / n for k in range(n)]


def pyramid(name, base, axis, w, d, length, mat=TRIM):
    """Square pyramid: base centre, unit axis, base width w (side axis) and depth d (y)."""
    base = Vector(base)
    axis = Vector(axis).normalized()
    side = Vector((0, 1, 0)).cross(axis)
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side.normalize()
    depth = Vector((0, 1, 0))
    bm = bmesh.new()
    corners = [bm.verts.new(base + side * sx * w / 2 + depth * sy * d / 2)
               for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    apex = bm.verts.new(base + axis * length)
    bm.faces.new(corners)
    for i in range(4):
        bm.faces.new((corners[i], corners[(i + 1) % 4], apex))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.material_index = mat
    return C.obj_from_bm(bm, name, smooth=False)


def union_all(parts, name):
    base = parts[0]
    for p in parts[1:]:
        C.boolean(base, p, op='UNION')
    base.name = name
    return base


def finial(name, z0, orb_r, spike_h, spike_r, mat=TRIM):
    p = Profile(0.0, z0)
    p.to(spike_r * 0.9, z0 + 0.004, mat)
    zc = z0 + orb_r * 0.9
    p.arc((orb_r, zc), (spike_r * 0.75, zc + orb_r * 0.85), n=8, mat=mat)
    p.to(spike_r * 1.35, p.cur[1] + 0.006, mat)
    p.up(0.012, mat)
    p.to(spike_r, p.cur[1] + 0.006, mat)
    p.bez((spike_r * 0.9, p.cur[1] + spike_h * 0.4), (spike_r * 0.35, p.cur[1] + spike_h * 0.8),
          (0.0, p.cur[1] + spike_h), n=8, mat=mat)
    ob = C.lathe(p, name, segs=16)
    return C.harden(ob, bevel=0.003, segments=1, angle=40)


def bent_box(x0, x1, z0, z1, y_front, y_back, name, nx=12, mat_back=GLOW, mat=BODY):
    """Box subdivided along x so it can be wrapped; back face gets mat_back (cut floor)."""
    bm = bmesh.new()
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    ft = [bm.verts.new((x, y_front, z1)) for x in xs]
    fb = [bm.verts.new((x, y_front, z0)) for x in xs]
    bt = [bm.verts.new((x, y_back, z1)) for x in xs]
    bb = [bm.verts.new((x, y_back, z0)) for x in xs]
    for i in range(nx):
        j = i + 1
        bm.faces.new((fb[i], fb[j], ft[j], ft[i])).material_index = mat
        bm.faces.new((bb[j], bb[i], bt[i], bt[j])).material_index = mat_back
        bm.faces.new((ft[i], ft[j], bt[j], bt[i])).material_index = mat
        bm.faces.new((fb[j], fb[i], bb[i], bb[j])).material_index = mat
    bm.faces.new((fb[0], ft[0], bt[0], bb[0])).material_index = mat
    bm.faces.new((fb[-1], bb[-1], bt[-1], ft[-1])).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return C.obj_from_bm(bm, name, smooth=False)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- king

def build_king():
    p = plinth(0.38)
    lower_body(p, 0.338, 0.29)
    p.bez((0.292, 0.25), (0.275, 0.30), (0.258, 0.33), n=6)
    p.to(0.265, 0.335)
    p.bead(0.012, 0.030)
    p.to(0.245, 0.370)
    p.bez((0.20, 0.52), (0.143, 0.70), (0.142, 0.835), n=10)
    collar(p, 0.845, 0.218, 0.192, 0.200, 0.150)
    p.bez((0.128, 0.975), (0.128, 0.99), (0.142, 1.005), n=4)
    p.bez((0.18, 1.06), (0.238, 1.14), (0.242, 1.225), n=7)
    p.to(0.246, 1.232, TRIM)
    p.up(0.016, TRIM)
    p.to(0.222, 1.254, TRIM)
    p.to(0.206, 1.248)
    p.to(0.200, 1.20)
    p.to(0.182, 1.192)
    p.bez((0.17, 1.24), (0.10, 1.288), (0.0, 1.292), n=5)
    rad = p.radius_fn()
    body = C.harden(C.lathe(p, "king_body", SEGS), bevel=0.005)

    parts = [body]
    parts += crown_ring("king_crown", 8, 0.236, 1.226, D(11), 0.036, 0.105, 0.026, pinch=0.5)
    parts += C.gem_set(rad, 0.50, 0.026, 0.046, "king_low", around(4))
    parts += C.gem_set(rad, 1.12, 0.020, 0.034, "king_crown", around(4, D(22.5)))
    parts.append(finial("king_orb", 1.27, 0.045, 0.02, 0.022))

    # cross with pointed, collared ends; faces -Y
    w, d, za = 0.06, 0.05, 1.472
    cross = [
        C.box("x_stem", (0, 0, 1.44), (w, d, 0.22), TRIM),
        C.box("x_arm", (0, 0, za), (0.20, d, 0.056), TRIM),
        pyramid("x_tip_top", (0, 0, 1.55), (0, 0, 1), w, d, 0.05),
        pyramid("x_tip_l", (-0.10, 0, za), (-1, 0, 0), 0.056, d, 0.04),
        pyramid("x_tip_r", (0.10, 0, za), (1, 0, 0), 0.056, d, 0.04),
        C.box("x_col_top", (0, 0, 1.532), (w + 0.02, d + 0.016, 0.022), TRIM),
        C.box("x_col_l", (-0.086, 0, za), (0.022, d + 0.016, 0.076), TRIM),
        C.box("x_col_r", (0.086, 0, za), (0.022, d + 0.016, 0.076), TRIM),
    ]
    cross_ob = union_all(cross, "king_cross")
    C.harden(cross_ob, bevel=0.005, segments=2, angle=30)
    parts.append(cross_ob)
    parts.append(C.gem(0.0, za, 0.016, 0.022, "x_gem", proud=0.01, back=0.0))
    parts[-1].data.transform(Matrix.Translation((0, -d / 2, 0)))
    return parts


# ---------------------------------------------------------------- queen

def build_queen():
    p = plinth(0.37)
    lower_body(p, 0.328, 0.28)
    p.bez((0.282, 0.24), (0.265, 0.29), (0.248, 0.318), n=6)
    p.to(0.254, 0.322)
    p.bead(0.010, 0.026)
    p.to(0.236, 0.352)
    p.bez((0.19, 0.48), (0.134, 0.64), (0.134, 0.755), n=10)
    collar(p, 0.765, 0.210, 0.184, 0.192, 0.140)
    p.bez((0.12, 0.895), (0.12, 0.91), (0.13, 0.925), n=4)
    p.bez((0.17, 0.98), (0.228, 1.07), (0.230, 1.15), n=7)
    p.to(0.234, 1.157, TRIM)
    p.up(0.014, TRIM)
    p.to(0.212, 1.176, TRIM)
    p.to(0.198, 1.170)
    p.to(0.192, 1.12)
    p.to(0.172, 1.112)
    p.bez((0.16, 1.16), (0.09, 1.20), (0.0, 1.205), n=5)
    rad = p.radius_fn()
    body = C.harden(C.lathe(p, "queen_body", SEGS), bevel=0.005)

    parts = [body]
    parts += crown_ring("queen_crown", 8, 0.222, 1.15, D(16), 0.048, 0.19, 0.028, gem_size=(0.013, 0.026),
                        pinch=0.62)
    parts += C.gem_set(rad, 0.45, 0.026, 0.046, "queen_low", around(4))
    parts += C.gem_set(rad, 1.05, 0.016, 0.028, "queen_crown", around(8, D(22.5)))
    parts.append(finial("queen_finial", 1.195, 0.045, 0.17, 0.026))
    return parts


# ---------------------------------------------------------------- bishop

def build_bishop():
    p = plinth(0.37)
    lower_body(p, 0.325, 0.276)
    p.bez((0.272, 0.25), (0.205, 0.31), (0.172, 0.37), n=8)
    collar(p, 0.375, 0.215, 0.192, 0.198, 0.158)
    p.to(0.155, 0.490)
    p.to(0.200, 0.496, TRIM)
    p.up(0.026, TRIM)
    p.to(0.196, 0.526)
    p.bez((0.236, 0.68), (0.16, 1.00), (0.012, 1.118), n=14)
    p.to(0.0, 1.121)
    rad = p.radius_fn()
    head = C.lathe(p, "bishop_body", SEGS)

    # helm visor: wide eye slit with a breath slit below it; the cut floors glow
    zv = 0.79
    for cut in (bent_box(-0.15, 0.15, zv - 0.016, zv + 0.016, -0.12, 0.03, "visor", nx=28),
                bent_box(-0.014, 0.014, 0.60, zv, -0.12, 0.03, "slit", nx=3)):
        C.wrap(cut, rad)
        C.boolean(head, cut)
    C.harden(head, bevel=0.004)

    parts = [head]

    def on_surface(c, tol=0.012):
        return abs(math.hypot(c.x, c.y) - rad(c.z)) < tol

    def front_angle(c):
        return abs(math.atan2(c.x, -c.y))

    parts.append(C.surface_band(head, (0, 0, 0), (1, 0, 0), 0.017, 0.014, "bishop_crest",
                                keep=lambda c: on_surface(c) and (c.z > 0.845 or (c.y > 0.0 and c.z > 0.53))))
    parts.append(C.surface_band(head, (0, 0, zv + 0.045), (0, 0, 1), 0.011, 0.012, "bishop_brow",
                                keep=lambda c: on_surface(c) and c.y < 0 and front_angle(c) < D(62)))
    for sx in (-1, 1):
        phi = C.FRONT + sx * D(58)
        nrm = (-math.sin(phi), math.cos(phi), 0.0)
        parts.append(C.surface_band(
            head, (0, 0, 0), nrm, 0.011, 0.012, "bishop_cheek",
            keep=lambda c, phi=phi: on_surface(c) and 0.53 < c.z < zv + 0.05 and
            c.x * math.cos(phi) + c.y * math.sin(phi) > 0))
    crest_gem = C.gem(0.0, 0.985, 0.016, 0.028, "crest_gem", proud=0.012, back=0.004)
    parts.append(C.wrap(crest_gem, lambda z: rad(z) + 0.010))
    parts += C.gem_set(rad, 0.27, 0.016, 0.05, "bishop_low", around(2))
    parts.append(finial("bishop_finial", 1.105, 0.026, 0.035, 0.013))
    return parts


# ---------------------------------------------------------------- rook

def arch_pts(a, z_sill, z_spring, n_side=6, n_arc=10):
    """Equilateral pointed arch outline (CCW from the front), half width a."""
    apex = z_spring + math.sqrt(3) * a
    pts = [(-a, z_sill), (a, z_sill)]
    pts += [(a, z_sill + (z_spring - z_sill) * i / n_side) for i in range(1, n_side)]
    # right arc: centre (-a, z_spring), radius 2a, from angle 0 to 60 deg
    pts += [(-a + 2 * a * math.cos(D(60) * i / n_arc), z_spring + 2 * a * math.sin(D(60) * i / n_arc))
            for i in range(0, n_arc)]
    pts.append((0.0, apex))
    pts += [(a - 2 * a * math.cos(D(60) * i / n_arc), z_spring + 2 * a * math.sin(D(60) * i / n_arc))
            for i in reversed(range(0, n_arc))]
    pts += [(-a, z_sill + (z_spring - z_sill) * i / n_side) for i in reversed(range(1, n_side))]
    return pts


def window_cutter(a, z_sill, z_spring, y_back, name, phi=C.FRONT):
    pts = arch_pts(a, z_sill, z_spring)
    ob = C.prism(pts, -0.45, y_back, name, mat_front=BODY, mat_back=GLOW, mat_side=BODY)
    ob.data.transform(Matrix.Rotation(phi + math.pi / 2, 4, 'Z'))
    return ob


def build_rook():
    p = plinth(0.37)
    lower_body(p, 0.325, 0.278)
    p.bez((0.272, 0.23), (0.246, 0.255), (0.238, 0.28), n=5)
    p.bez((0.236, 0.45), (0.228, 0.62), (0.222, 0.74), n=10)
    p.to(0.236, 0.745)
    p.bead(0.012, 0.026)
    p.to(0.228, 0.775)
    p.up(0.016, TRIM)
    p.to(0.231, 0.794)
    p.bez((0.236, 0.82), (0.276, 0.832), (0.281, 0.87), n=8)
    p.to(0.283, 0.992)
    p.to(0.273, 1.0)
    p.to(0.234, 1.0)
    p.to(0.226, 0.993)
    p.to(0.226, 0.942)
    p.to(0.0, 0.938)
    rad = p.radius_fn()
    body = C.lathe(p, "rook_body", SEGS, phase=math.pi / SEGS)

    for k, phi in enumerate(around(6)):
        notch = C.box("notch%d" % k, (0.0, -0.25, 1.0), (0.10, 0.16, 0.118))
        notch.data.transform(Matrix.Rotation(phi + math.pi / 2, 4, 'Z'))
        C.boolean(body, notch)
    a, z_sill, z_spring = 0.064, 0.40, 0.60
    C.boolean(body, window_cutter(a, z_sill, z_spring, -0.188, "window"))
    for k, phi in enumerate((D(30), D(150))):
        C.boolean(body, window_cutter(0.019, 0.47, 0.62, -0.20, "slit%d" % k, phi))
    C.harden(body, bevel=0.005)

    parts = [body]
    f = 0.021
    outer = arch_pts(a + f, z_sill - f, z_spring)
    inner = arch_pts(a, z_sill, z_spring)
    frame = C.ring_prism(outer, inner, -0.014, 0.014, "rook_frame")
    C.wrap(frame, rad)
    C.harden(frame, bevel=0.003, segments=1, angle=45)
    parts.append(frame)
    sill = C.box("rook_sill", (0.0, -0.012, z_sill - f - 0.008), (2 * (a + f) + 0.03, 0.05, 0.018), TRIM)
    C.wrap(sill, rad)
    C.harden(sill, bevel=0.004, segments=1)
    parts.append(sill)
    return parts


# ---------------------------------------------------------------- knight

KNIGHT_OUTLINE = [  # (y, z) side profile, front = -y
    (-0.150, 0.335), (-0.168, 0.445), (-0.142, 0.540),
    (-0.105, 0.592),  # throat notch
    (-0.150, 0.600), (-0.230, 0.598),  # jaw underside
    (-0.300, 0.612),  # chin
    (-0.330, 0.640),  # mouth corner
    (-0.368, 0.656),  # lip
    (-0.388, 0.690),  # nose tip
    (-0.378, 0.735),  # nostril top
    (-0.300, 0.822),  # nose bridge
    (-0.200, 0.925),  # brow
    (-0.130, 0.985),  # forehead
    (-0.050, 1.025),  # poll
    (0.030, 1.010), (0.095, 0.930),  # crest
    (0.140, 0.800), (0.162, 0.640), (0.178, 0.470), (0.182, 0.335),
]


def knight_width(y, z):
    w = 0.122 * np.ones_like(y)
    w *= 1.0 - 0.45 * O.smoothstep(-0.17, -0.385, y)                                  # muzzle
    w *= 1.0 - 0.32 * O.smoothstep(0.0, 0.14, y) * O.smoothstep(0.70, 0.95, z)        # crest
    w *= 1.0 - 0.12 * O.smoothstep(0.93, 1.03, z)                                     # top of the head
    w += 0.030 * O.gauss(y + 0.08, z - 0.73, 0.085)                                   # jowl
    w += 0.016 * O.gauss(y + 0.20, z - 0.925, 0.032)                                  # brow ridge
    w += 0.012 * O.gauss(y + 0.37, z - 0.70, 0.028)                                   # nostril flare
    w -= 0.010 * O.gauss(y + 0.10, z - 0.90, 0.04)                                    # temple hollow
    w += 0.022 * O.smoothstep(0.50, 0.36, z)                                          # neck root
    return w


KNIGHT_MANE = [  # anchor (y, z), direction (y, z), length
    ((0.020, 1.012), (0.35, 1.0), 0.085), ((0.055, 0.985), (0.6, 0.8), 0.11), ((0.088, 0.940), (0.8, 0.6), 0.11),
    ((0.115, 0.878), (0.9, 0.45), 0.105), ((0.136, 0.805), (0.95, 0.33), 0.10), ((0.150, 0.725), (0.97, 0.26), 0.09),
    ((0.158, 0.645), (0.98, 0.2), 0.08), ((0.162, 0.565), (0.99, 0.15), 0.07), ((0.162, 0.490), (1.0, 0.1), 0.055),
]


def knight_head():
    parts = [O.inflate(KNIGHT_OUTLINE, knight_width, "k_slab")]
    for sx in (-1, 1):
        parts.append(C.cone("k_ear", (sx * 0.048, -0.055, 0.985), (sx * 0.072, -0.085, 1.106), 0.05,
                            segs=12, flatten=(1.0, 0.55)))
    parts.append(C.cone("k_forelock", (0.0, -0.075, 1.0), (0.0, -0.165, 1.012), 0.032, segs=10,
                        flatten=(0.7, 1.0)))
    for i, ((y, z), (dy, dz), ln) in enumerate(KNIGHT_MANE):
        nrm = Vector((0, dy, dz)).normalized()
        base = Vector((0, y - 0.03 * nrm.y, z - 0.03 * nrm.z))
        parts.append(C.cone("k_mane%d" % i, base, base + nrm * (ln + 0.03), 0.046, segs=10, flatten=(0.36, 1.0)))
        if 1 <= i <= 7:
            for sx in (-1, 1):
                b2 = Vector((sx * 0.05, y - 0.05 * nrm.y, z - 0.035))
                d2 = (nrm + Vector((sx * 0.45, 0, -0.15))).normalized()
                parts.append(C.cone("k_lock", b2, b2 + d2 * (ln * 0.7 + 0.03), 0.034, segs=8, flatten=(0.4, 1.0)))
    head = C.join(parts, "knight_head")
    C.remesh(head, 0.0052)
    C.smooth(head, 0.5, 3)

    tree = C.bvh(head)
    cut = []
    eyes = []
    for sx in (-1, 1):
        hit, n = C.surface_hit(tree, (sx * 0.5, -0.172, 0.874), (-sx, 0, 0))
        cut.append(C.uv_sphere("k_socket", hit - n * 0.008, (0.040, 0.044, 0.034)))
        eyes.append(C.uv_sphere("knight_eye", hit - n * 0.026, (0.029, 0.031, 0.026), mat=GLOW))
        hit, n = C.surface_hit(tree, (sx * 0.034, -0.6, 0.700), (0, 1, 0))
        cut.append(C.uv_sphere("k_nostril", hit + Vector((0, 0.008, 0)), (0.019, 0.024, 0.024)))
    mouth = C.box("k_mouth", (0.0, 0.0, 0.0), (0.4, 0.11, 0.012))
    mouth.data.transform(Matrix.Translation((0, -0.31, 0.640)) @ Matrix.Rotation(D(8), 4, 'X'))
    cut.append(mouth)
    for c in cut:
        C.boolean(head, c)
    C.decimate(head, 5600)
    C.soften(head, 70)
    return head, eyes


def build_knight():
    p = plinth(0.37)
    lower_body(p, 0.325, 0.276)
    p.bez((0.272, 0.245), (0.25, 0.28), (0.236, 0.298), n=6)
    p.to(0.241, 0.30, TRIM)
    p.bead(0.010, 0.024, mat=TRIM)
    p.to(0.232, 0.328)
    p.to(0.228, 0.345)
    p.to(0.236, 0.348, TRIM)
    p.up(0.016, TRIM)
    p.to(0.224, 0.368)
    p.to(0.212, 0.374)
    p.to(0.0, 0.374)
    rad = p.radius_fn()
    base = C.harden(C.lathe(p, "knight_body", SEGS), bevel=0.005)
    head, eyes = knight_head()
    parts = [base, head] + eyes
    parts += C.gem_set(rad, 0.252, 0.02, 0.032, "knight_low", around(4))

    nose_c = Vector((0, -0.2985, 0.722))
    parts.append(C.surface_band(head, nose_c, (0, -0.942, -0.336), 0.013, 0.016, "k_noseband",
                                keep=lambda c: (c - nose_c).length < 0.15))
    poll_c = Vector((0, -0.005, 1.02))
    parts.append(C.surface_band(head, poll_c, (0, 0.971, -0.238), 0.013, 0.016, "k_headpiece",
                                keep=lambda c: c.z > 0.585 and (c - Vector((0, -0.06, 0.80))).length < 0.33))
    tree = C.bvh(head)
    for sx in (-1, 1):
        ros, rn = C.surface_hit(tree, (sx * 0.5, -0.069, 0.76), (-sx, 0, 0))
        nb, nn = C.surface_hit(tree, (sx * 0.5, nose_c.y, nose_c.z), (-sx, 0, 0))
        plane_n = (nb - ros).cross((rn + nn).normalized()).normalized()

        def keep(c, ros=ros, nb=nb, sx=sx):
            t = max(0.0, min(1.0, (c - ros).dot(nb - ros) / (nb - ros).length_squared))
            return c.x * sx > 0.02 and (c - ros.lerp(nb, t)).length < 0.05

        parts.append(C.surface_band(head, ros.lerp(nb, 0.5), plane_n, 0.011, 0.014, "k_cheekstrap", keep=keep))
        rp = Profile(0.0, 0.0)
        rp.to(0.034, 0.0, TRIM)
        rp.to(0.037, 0.008, TRIM)
        rp.to(0.031, 0.015, TRIM)
        rp.bez((0.022, 0.021), (0.01, 0.023), (0.0, 0.023), n=4, mat=TRIM)
        rosette = C.lathe(rp, "k_rosette", segs=14)
        rosette.data.transform(Matrix.Translation(ros - rn * 0.004) @
                               Vector((0, 0, 1)).rotation_difference(rn).to_matrix().to_4x4())
        C.harden(rosette, bevel=0.002, segments=1, angle=40)
        parts.append(rosette)
    return parts


# ---------------------------------------------------------------- pawn

SKULL_SCALE = 1.2
SKULL_TILT = D(-9)  # face tilted up a little so the top-down camera sees it


def skull_local():
    """Skull in its own frame: z = 0 at the chin, front -y. Returns (skull, eyes)."""
    sk = [
        C.uv_sphere("s_cranium", (0, 0.025, 0.158), (0.150, 0.168, 0.138), segs=32, rings=20),
        C.uv_sphere("s_brow", (0, -0.116, 0.150), (0.128, 0.042, 0.034)),
        C.box("s_maxilla", (0, -0.094, 0.072), (0.150, 0.10, 0.08)),
        C.box("s_mandible", (0, -0.082, 0.022), (0.124, 0.10, 0.044)),
        C.uv_sphere("s_chin", (0, -0.122, 0.012), (0.048, 0.03, 0.024)),
        C.uv_sphere("s_neck", (0, 0.035, 0.03), (0.095, 0.105, 0.08)),
    ]
    for sx in (-1, 1):
        sk.append(C.uv_sphere("s_cheek", (sx * 0.088, -0.098, 0.098), (0.052, 0.052, 0.034)))
        sk.append(C.box("s_ramus", (sx * 0.066, -0.03, 0.055), (0.03, 0.07, 0.09)))
    skull = C.join(sk, "pawn_skull")
    C.remesh(skull, 0.0042)
    C.smooth(skull, 0.5, 4)
    for v in skull.data.vertices:  # temples: pinch the sides above the cheekbones
        x, y, z = v.co
        v.co.x = x * (1.0 - 0.08 * float(O.smoothstep(0.07, 0.15, z) * O.smoothstep(0.05, -0.10, y)))
    skull.data.update()

    tree = C.bvh(skull)
    cut = []
    eyes = []
    for sx in (-1, 1):
        hit, _n = C.surface_hit(tree, (sx * 0.057, -0.5, 0.118), (0, 1, 0))
        cut.append(C.uv_sphere("s_socket", hit + Vector((0, 0.016, 0)), (0.049, 0.048, 0.045)))
        eyes.append(C.uv_sphere("pawn_eye", hit + Vector((0, 0.044, 0)), (0.029, 0.029, 0.029), mat=GLOW))
    hit, _n = C.surface_hit(tree, (0.0, -0.5, 0.075), (0, 1, 0))
    heart = [(0.0, 0.106), (-0.014, 0.085), (-0.025, 0.062), (-0.012, 0.050), (0.0, 0.056), (0.012, 0.050),
             (0.025, 0.062), (0.014, 0.085)]
    cut.append(C.prism(heart, hit.y - 0.05, hit.y + 0.04, "s_nose"))
    hit, _n = C.surface_hit(tree, (0.0, -0.5, 0.038), (0, 1, 0))
    cut.append(C.box("s_mouth", (0, hit.y + 0.002, 0.038), (0.13, 0.03, 0.008)))
    for i in range(-2, 3):
        hit, _n = C.surface_hit(tree, (i * 0.024 + 0.012, -0.5, 0.038), (0, 1, 0))
        cut.append(C.box("s_tooth", (i * 0.024 + 0.012, hit.y, 0.039), (0.0055, 0.024, 0.052)))
    for c in cut:
        C.boolean(skull, c)
    C.decimate(skull, 5000)
    C.soften(skull, 70)
    return skull, eyes


def build_pawn():
    p = plinth(0.36)
    lower_body(p, 0.316, 0.268)
    p.bez((0.264, 0.245), (0.232, 0.29), (0.192, 0.315), n=6)
    p.to(0.196, 0.320)
    p.bead(0.010, 0.024)
    p.to(0.175, 0.348)
    p.bez((0.13, 0.37), (0.108, 0.40), (0.112, 0.418), n=5)
    p.to(0.132, 0.422)
    p.to(0.182, 0.434)
    p.bead(0.010, 0.024)
    p.to(0.166, 0.462)
    p.up(0.010, TRIM)
    p.to(0.132, 0.476)
    p.to(0.0, 0.478)
    rad = p.radius_fn()
    base = C.harden(C.lathe(p, "pawn_body", SEGS), bevel=0.005)

    skull, eyes = skull_local()
    m = Matrix.Rotation(SKULL_TILT, 4, 'X') @ Matrix.Scale(SKULL_SCALE, 4)
    for o in [skull] + eyes:
        o.data.transform(m)
    lift = C.HEIGHTS["pawn"] - max(v.co.z for v in skull.data.vertices)
    for o in [skull] + eyes:
        o.data.transform(Matrix.Translation((0, 0, lift)))

    parts = [base, skull] + eyes
    parts += C.gem_set(rad, 0.255, 0.018, 0.028, "pawn_low", around(4, D(45)))
    return parts



BUILDERS = {"king": build_king, "queen": build_queen, "rook": build_rook, "bishop": build_bishop,
            "knight": build_knight, "pawn": build_pawn}


# ---------------------------------------------------------------- main

def build_one(name, bake=True):
    t0 = time.time()
    C.reset_scene()
    parts = BUILDERS[name]()
    if "--parts" in C.script_args():
        groups = {}
        for o in parts:
            key = o.name.split(".")[0].rstrip("0123456789")
            groups[key] = groups.get(key, 0) + C.tri_count(o)
        print("PARTS %s %s" % (name, sorted(groups.items(), key=lambda kv: -kv[1])))
    ob = C.join(parts, name)
    ob.data.validate(clean_customdata=False)
    C.smart_uv(ob)
    if bake:
        C.bake_ao(ob)
    else:
        C.white_ao(ob)
    anims.add_all(ob, C.HEIGHTS[name])
    os.makedirs(C.BUILD, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(C.BUILD, name + ".blend"))
    C.export_glb(ob, os.path.join(C.MODELS, name + ".glb"))
    xs = [v.co for v in ob.data.vertices]
    stats = {
        "tris": C.tri_count(ob),
        "height": max(v.z for v in xs) - min(v.z for v in xs),
        "min_z": min(v.z for v in xs),
        "width_x": max(v.x for v in xs) - min(v.x for v in xs),
        "width_y": max(v.y for v in xs) - min(v.y for v in xs),
        "seconds": round(time.time() - t0, 1),
    }
    print("BUILT %s %s" % (name, json.dumps(stats)))
    return stats


def main():
    args = C.script_args()
    only = list(C.PIECES)
    if "--only" in args:
        only = args[args.index("--only") + 1].split(",")
    bake = "--no-ao" not in args
    path = os.path.join(C.BUILD, "stats.json")
    stats = json.load(open(path)) if os.path.exists(path) else {}
    for name in only:
        stats[name] = build_one(name, bake)
    with open(path, "w") as fh:
        json.dump(stats, fh, indent=1)


if __name__ == "__main__":
    main()
