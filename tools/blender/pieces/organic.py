"""Inflated side-profile solids: a closed (y, z) outline becomes a rounded, pillowed body that is
thickest where the point is far from the outline (like a carved relief turned into a sculpture)."""
import math

import bmesh
import numpy as np
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt

import common as C


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gauss(dy, dz, s):
    return np.exp(-(dy * dy + dz * dz) / (2 * s * s))


def centripetal(pts, spacing):
    """Closed centripetal Catmull-Rom through pts, sampled about every `spacing` metres."""
    P = [Vector(p) for p in pts]
    m = len(P)
    out = []
    for i in range(m):
        p0, p1, p2, p3 = P[i - 1], P[i], P[(i + 1) % m], P[(i + 2) % m]

        def nxt(t, a, b):
            return t + max((b - a).length, 1e-6) ** 0.5
        t0 = 0.0
        t1 = nxt(t0, p0, p1)
        t2 = nxt(t1, p1, p2)
        t3 = nxt(t2, p2, p3)
        n = max(2, int(math.ceil((p2 - p1).length / spacing)))
        for k in range(n):
            t = t1 + (t2 - t1) * k / n
            a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
            a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
            a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
            b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
            b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
            c = b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
            out.append((c.x, c.y))
    return np.array(out)


def inside(poly, P):
    y = P[:, 0][:, None]
    z = P[:, 1][:, None]
    A = poly[None, :, :]
    B = np.roll(poly, -1, axis=0)[None, :, :]
    za, zb = A[..., 1], B[..., 1]
    cond = (za > z) != (zb > z)
    dz = np.where(zb - za == 0, 1e-12, zb - za)
    yint = A[..., 0] + (z - za) * (B[..., 0] - A[..., 0]) / dz
    return np.count_nonzero(cond & (y < yint), axis=1) % 2 == 1


def dist_to(poly, P):
    A = poly
    AB = np.roll(poly, -1, axis=0) - A
    AP = P[:, None, :] - A[None, :, :]
    t = np.clip((AP * AB[None]).sum(-1) / (AB * AB).sum(-1)[None], 0.0, 1.0)
    proj = A[None] + t[..., None] * AB[None]
    return np.linalg.norm(P[:, None, :] - proj, axis=2).min(axis=1)


def inflate(outline, width_fn, name, spacing=0.01, r_edge=0.055, pillow=0.016, t_min=0.004, mat=C.BODY,
            edge_spacing=None):
    """outline: [(y, z)], width_fn(y, z) -> half width (numpy). Returns a closed mesh object.
    The outline is sampled every edge_spacing (default 0.8 * spacing), the interior every spacing."""
    boundary = centripetal(outline, edge_spacing or spacing * 0.8)
    nb = len(boundary)
    lo = boundary.min(axis=0)
    hi = boundary.max(axis=0)
    gy, gz = np.meshgrid(np.arange(lo[0], hi[0], spacing), np.arange(lo[1], hi[1], spacing))
    grid = np.stack([gy.ravel(), gz.ravel()], axis=1)
    grid = grid[inside(boundary, grid)]
    grid = grid[dist_to(boundary, grid) > (spacing * 0.6 if edge_spacing is None else max(edge_spacing, spacing * 0.5))]
    pts = np.concatenate([boundary, grid])
    coords = [Vector((float(y), float(z))) for y, z in pts]
    out_v, _e, out_f, orig_v, _oe, _of = delaunay_2d_cdt(coords, [], [list(range(nb))], 1, 1e-7)
    P = np.array([(v.x, v.y) for v in out_v])
    d = dist_to(boundary, P)
    is_b = np.array([any(i < nb for i in o) for o in orig_v])
    d[is_b] = 0.0
    w = width_fn(P[:, 0], P[:, 1])
    round_ = np.sqrt(1.0 - (1.0 - np.clip(d / r_edge, 0.0, 1.0)) ** 2)
    t = t_min + (w - t_min) * round_ + pillow * smoothstep(r_edge, r_edge * 3.0, d)

    bm = bmesh.new()
    top = [bm.verts.new((float(t[i]), float(P[i, 0]), float(P[i, 1]))) for i in range(len(P))]
    bot = [bm.verts.new((-float(t[i]), float(P[i, 0]), float(P[i, 1]))) for i in range(len(P))]
    for f in out_f:
        bm.faces.new([top[i] for i in f]).material_index = mat
        bm.faces.new([bot[i] for i in reversed(f)]).material_index = mat
    inv = {}
    for i, o in enumerate(orig_v):
        for k in o:
            inv[k] = i
    loop = []
    for k in range(nb):
        j = inv[k]
        if not loop or loop[-1] != j:
            loop.append(j)
    for a, b in zip(loop, loop[1:] + loop[:1]):
        if a != b:
            bm.faces.new((top[a], top[b], bot[b], bot[a])).material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return C.obj_from_bm(bm, name)
