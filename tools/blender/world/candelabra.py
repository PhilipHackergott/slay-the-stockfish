"""Wrought-iron 3-arm candelabra -> models/props/candelabra.glb.

Contract: one object "candelabra" (origin bottom centre, arms along local X), slots iron / candle_wax / candle_flame,
empties flame_0..2. Height ~2.15 m so the flames sit ~0.75-0.86 m above the board when it stands on the floor.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import common as C  # noqa: E402

RNG = random.Random(4242)
MATS = ["iron", "candle_wax", "candle_flame"]
IRON, WAX, FLAME = 0, 1, 2

FLAT_BAR = [(-0.008, -0.012), (0.0, -0.016), (0.008, -0.012), (0.008, 0.012), (0.0, 0.016), (-0.008, 0.012)]


def in_plane(pts_rz, ang):
    c, s = math.cos(ang), math.sin(ang)
    return [Vector((r * c, r * s, z)) for r, z in pts_rz]


def spiral(cx, cz, r0, r1, a0, turns, n):
    out = []
    for i in range(n + 1):
        t = i / n
        a = a0 + 2 * math.pi * turns * t
        r = r0 + (r1 - r0) * t
        out.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return out


def flat_scroll(bm, pts3, normal, scale0=1.0, scale1=0.55, prof=FLAT_BAR):
    s = C.sweep(pts3, prof, up=normal, closed=False, closed_profile=True,
                scale=lambda t: scale0 + (scale1 - scale0) * t)
    C.merge(bm, s, mat=IRON)


def leg(bm, ang):
    ctrl = [(0.04, 0.215), (0.09, 0.19), (0.16, 0.135), (0.23, 0.06), (0.28, 0.018)]
    path = [(p.x, p.z) for p in C.catmull([(r, 0, z) for r, z in ctrl], n=4)]
    a_start = math.radians(-100)
    curl = spiral(0.30, 0.046, 0.038, 0.012, a_start, 1.15, 16)
    path = path[:-1] + curl
    normal = Vector((-math.sin(ang), math.cos(ang), 0))
    flat_scroll(bm, in_plane(path, ang), normal, 1.25, 0.6)
    # small leaf collar where the leg meets the drum
    pad = C.uvsphere(1.0, 6, 4)
    C.transform(pad, Matrix.Translation(in_plane([(0.07, 0.205)], ang)[0]) @ Matrix.Rotation(ang, 4, 'Z')
                @ Matrix.Diagonal((0.035, 0.022, 0.03, 1)))
    C.merge(bm, pad, mat=IRON)


def stem(bm):
    lower = [(0.0, 0.16), (0.055, 0.16), (0.085, 0.185), (0.09, 0.21), (0.08, 0.235), (0.06, 0.25), (0.045, 0.28),
             (0.034, 0.33), (0.03, 0.37), (0.042, 0.395), (0.046, 0.41), (0.03, 0.43), (0.022, 0.45), (0.044, 0.49),
             (0.052, 0.535), (0.045, 0.58), (0.024, 0.615), (0.032, 0.63), (0.032, 0.65), (0.0, 0.66)]
    C.merge(bm, C.lathe(lower, seg=10), mat=IRON)
    # twisted square bar
    sq = 0.013
    twist = C.sweep([Vector((0, 0, 0.65 + 0.47 * i / 40)) for i in range(41)],
                    [(-sq, -sq), (sq, -sq), (sq, sq), (-sq, sq)], up=None, closed=False, twist=6 * math.pi)
    C.merge(bm, twist, mat=IRON)
    upper = [(0.0, 1.11), (0.03, 1.11), (0.033, 1.13), (0.022, 1.15), (0.036, 1.18), (0.052, 1.225), (0.048, 1.265),
             (0.03, 1.29), (0.013, 1.305), (0.013, 1.495), (0.028, 1.505), (0.03, 1.53), (0.018, 1.55), (0.024, 1.565),
             (0.052, 1.578), (0.058, 1.60), (0.052, 1.622), (0.022, 1.632), (0.011, 1.64), (0.011, 1.715),
             (0.022, 1.735), (0.025, 1.755), (0.011, 1.775), (0.011, 1.83), (0.0, 1.83)]
    C.merge(bm, C.lathe(upper, seg=10), mat=IRON)
    # cage of C-scrolls round the upper rod
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        c = [(0.014, 1.315), (0.045, 1.335), (0.066, 1.38), (0.064, 1.43), (0.044, 1.47), (0.014, 1.488)]
        pts = [(p.x, p.z) for p in C.catmull([(r, 0, z) for r, z in c], n=3)]
        curl = spiral(0.045, 1.40, 0.016, 0.005, math.pi * 0.5, 0.8, 6)
        normal = Vector((-math.sin(ang), math.cos(ang), 0))
        flat_scroll(bm, in_plane(pts, ang), normal, 0.8, 0.8)
        flat_scroll(bm, in_plane(curl, ang), normal, 0.6, 0.4)


def arm(bm, sgn):
    ctrl = [(0.03, 1.605), (0.12, 1.575), (0.22, 1.588), (0.30, 1.632), (0.335, 1.69), (0.34, 1.73)]
    pts = [Vector((sgn * p.x, 0, p.z)) for p in C.catmull([(x, 0, z) for x, z in ctrl], n=5)]
    ring = [(0.012 * math.cos(a), 0.012 * math.sin(a)) for a in [2 * math.pi * i / 6 for i in range(6)]]
    C.merge(bm, C.sweep(pts, ring, up=None, closed=False, scale=lambda t: 1.0 - 0.2 * t), mat=IRON)
    normal = Vector((0, 1, 0))
    under = spiral(0.15, 1.515, 0.07, 0.014, math.radians(25), -1.25, 18)
    flat_scroll(bm, [Vector((sgn * x, 0, z)) for x, z in under], normal, 0.9, 0.5)
    over = spiral(0.235, 1.655, 0.045, 0.01, math.radians(-120), 1.1, 12)
    flat_scroll(bm, [Vector((sgn * x, 0, z)) for x, z in over], normal, 0.7, 0.4)


def pan(bm, x, z):
    prof = [(0.0, -0.03), (0.012, -0.03), (0.018, -0.01), (0.07, -0.003), (0.083, 0.008), (0.08, 0.016),
            (0.068, 0.008), (0.035, 0.01), (0.035, 0.04), (0.029, 0.042), (0.0, 0.042)]
    C.merge(bm, C.lathe(prof, seg=12), mat=IRON, matrix=Matrix.Translation((x, 0, z)))
    # little spike finial under the pan
    C.merge(bm, C.lathe([(0.0, -0.09), (0.01, -0.05), (0.014, -0.03), (0.0, -0.025)], seg=6, cap_top=False),
            mat=IRON, matrix=Matrix.Translation((x, 0, z)))


def drip(bm, p_top, outward, length, r=0.0055):
    pts = []
    n = 6
    wob = RNG.uniform(0, 10)
    for i in range(n + 1):
        t = i / n
        side = Vector((-outward.y, outward.x, 0)) * 0.004 * math.sin(wob + t * 4)
        pts.append(p_top + Vector((0, 0, -length * t)) + side + outward * (0.001 * t))
    prof = [(r * math.cos(a), r * math.sin(a)) for a in [2 * math.pi * i / 5 for i in range(5)]]
    s = C.sweep(pts, prof, up=None, closed=False, scale=lambda t: 0.75 + 0.55 * t ** 3)
    # round the tip
    tip = C.uvsphere(r * 1.3, 5, 2)
    C.merge(bm, s, mat=WAX)
    C.merge(bm, tip, mat=WAX, matrix=Matrix.Translation(pts[-1]))


def candle(bm, x, z0, height, radius, idx):
    """Candle standing in a pan socket at (x, z0); returns the flame centre."""
    seg = 12
    zt = z0 + height
    prof = [(0.0, z0), (radius, z0), (radius, zt - 0.012), (radius * 0.98, zt), (radius * 0.75, zt - 0.006),
            (radius * 0.35, zt - 0.014), (0.0, zt - 0.016)]
    c = C.lathe(prof, seg=seg)
    seed = idx * 3.1
    for v in c.verts:
        if v.co.z > zt - 0.02 and math.hypot(v.co.x, v.co.y) > radius * 0.5:
            a = math.atan2(v.co.y, v.co.x)
            v.co.z -= 0.018 * max(0.0, noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, seed))) + 0.35)
            v.co.x *= 1.0 + 0.06 * noise.noise(Vector((a, seed, 0)))
    C.merge(bm, c, mat=WAX, matrix=Matrix.Translation((x, 0, 0)))
    # drips down the side
    for k in range(4):
        a = RNG.uniform(0, 2 * math.pi)
        out = Vector((math.cos(a), math.sin(a), 0))
        top = Vector((x, 0, zt - 0.008)) + out * (radius + 0.0015)
        drip(bm, top, out, RNG.uniform(0.03, height * 0.85))
    # wax pooled in the pan
    pool = C.lathe([(0.0, z0 + 0.012), (radius + 0.02, z0 + 0.01), (radius + 0.03, z0 + 0.003), (radius + 0.035, z0 - 0.004)],
                   seg=12, cap_top=False)
    for v in pool.verts:
        a = math.atan2(v.co.y, v.co.x)
        k = 1.0 + 0.25 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, seed + 7)))
        v.co.x *= k
        v.co.y *= k
    C.merge(bm, pool, mat=WAX, matrix=Matrix.Translation((x, 0, 0)))
    # wick
    wick = C.lathe([(0.0, zt - 0.016), (0.0022, zt - 0.016), (0.0018, zt + 0.006), (0.0, zt + 0.011)], seg=4)
    C.merge(bm, wick, mat=IRON, matrix=Matrix.Translation((x, 0, 0)))
    # flame: teardrop, slightly bent
    fprof = [(0.0, 0.0), (0.0075, 0.006), (0.0115, 0.02), (0.0105, 0.036), (0.0065, 0.054), (0.0025, 0.068), (0.0, 0.076)]
    fl = C.lathe(fprof, seg=8)
    for v in fl.verts:
        v.co.x += 0.06 * v.co.z * v.co.z / 0.076
    base = zt + 0.002
    C.merge(bm, fl, mat=FLAME, matrix=Matrix.Translation((x, 0, base)))
    return Vector((x, 0, base + 0.03))


def chain(bm, start, links, size=0.016, wire=0.0028):
    p = Vector(start)
    for i in range(links):
        t = C.torus(size, wire, seg=6, rseg=3, sx=1.0)
        C.transform(t, Matrix.Diagonal((0.75, 1.0, 1.0, 1)))
        rot = Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Rotation(math.pi / 2 * (i % 2), 4, 'Y')
        C.merge(bm, t, mat=IRON, matrix=Matrix.Translation(p - Vector((0, 0, size))) @ rot)
        p = p - Vector((0, 0, size * 1.55))
    drop = C.lathe([(0.0, -0.05), (0.008, -0.02), (0.011, -0.008), (0.006, 0.0), (0.0, 0.004)], seg=6)
    C.merge(bm, drop, mat=IRON, matrix=Matrix.Translation(p))


def main():
    C.reset()
    bm = bmesh.new()
    for k in range(3):
        leg(bm, math.pi / 2 + k * 2 * math.pi / 3)
    stem(bm)
    for sgn in (-1, 1):
        arm(bm, sgn)
    side_z, centre_z = 1.745, 1.835
    pan(bm, -0.34, side_z)
    pan(bm, 0.34, side_z)
    pan(bm, 0.0, centre_z)
    flames = [
        candle(bm, -0.34, side_z + 0.01, 0.20, 0.03, 0),
        candle(bm, 0.0, centre_z + 0.01, 0.225, 0.034, 1),
        candle(bm, 0.34, side_z + 0.01, 0.19, 0.03, 2),
    ]
    for sgn in (-1, 1):
        chain(bm, (sgn * 0.245, 0, 1.596), 5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = C.bm_to_obj(bm, "candelabra", MATS)
    C.finish(obj, sharp_deg=48)
    C.log("candelabra", C.tris(obj), "tris", [m.name for m in obj.data.materials],
          "height", round(max(v.co.z for v in obj.data.vertices), 3))
    fl = C.bm_to_obj(C.box(10, 10, 0.1, center=(0, 0, -0.05)), "_floor", ["stone"])
    C.bake_ao([obj], samples=48, distance=0.15)
    C.bpy.data.objects.remove(fl)
    emp = [C.empty("flame_%d" % i, p, size=0.05) for i, p in enumerate(flames)]
    for e, p in zip(emp, flames):
        C.log(e.name, tuple(round(c, 3) for c in p))
    C.export_glb(os.path.join(C.MODELS, "props", "candelabra.glb"), [obj] + emp)


if __name__ == "__main__":
    main()
