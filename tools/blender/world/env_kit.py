"""Generators for the cathedral-ruin environment. Each returns a bmesh in local coords (Z up, base at z=0, front -Y)
with material indices into common.ENV_MATS."""
import math
import random

import bmesh
from mathutils import Matrix, Vector, noise

import common as C

STONE, DARK, TILES, IRON, WOOD, CROW, MOSS, BONE = range(8)


def M(loc=(0, 0, 0), rz=0.0, rx=0.0, ry=0.0, s=1.0):
    sc = s if isinstance(s, (tuple, list)) else (s, s, s)
    return (Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Rotation(ry, 4, 'Y')
            @ Matrix.Rotation(rx, 4, 'X') @ Matrix.Diagonal((sc[0], sc[1], sc[2], 1)))


def xz_to_y(outline, y0, y1):
    """Prism of an (x, z) outline spanning y0..y1 (y0 < y1)."""
    pr = C.prism(outline, -y1, -y0)
    C.transform(pr, Matrix.Rotation(math.pi / 2, 4, 'X'))
    return pr


def moss_tops(bm, thresh=0.62, scale=0.45, cut=0.18, seed=0.0, only=(STONE, DARK)):
    off = Vector((seed, seed * 0.7, 0))
    bm.normal_update()
    for f in bm.faces:
        if f.material_index not in only:
            continue
        n = f.normal
        if n.z < thresh:
            continue
        c = f.calc_center_median()
        if noise.noise(c * scale + off) > cut:
            f.material_index = MOSS


def world_moss(bm, matrix, thresh=0.62, scale=0.45, cut=0.18, only=(STONE, DARK)):
    """Moss on upward faces using world-space noise (coherent patches across parts)."""
    bm.normal_update()
    for f in bm.faces:
        if f.material_index not in only:
            continue
        n = (matrix.to_3x3() @ f.normal)
        if n.length < 1e-6 or n.z < thresh * n.length:
            continue
        c = matrix @ f.calc_center_median()
        if noise.noise(c * scale) > cut:
            f.material_index = MOSS


# ----------------------------------------------------------------------------------------------- outlines

def cluster_outline(core=0.35, shaft=0.12, shaft_d=0.36, small=0.07, small_d=0.37, n=40, octagon=True):
    centres = [(shaft_d * math.cos(k * math.pi / 2), shaft_d * math.sin(k * math.pi / 2), shaft) for k in range(4)]
    if small > 0:
        centres += [(small_d * math.cos(math.pi / 4 + k * math.pi / 2), small_d * math.sin(math.pi / 4 + k * math.pi / 2),
                     small) for k in range(4)]

    def fn(phi):
        if octagon:
            best = core * math.cos(math.pi / 8) / math.cos(((phi % (math.pi / 4)) - math.pi / 8))
        else:
            best = core
        d = (math.cos(phi), math.sin(phi))
        for cx, cy, r in centres:
            proj = cx * d[0] + cy * d[1]
            perp2 = cx * cx + cy * cy - proj * proj
            if perp2 <= r * r:
                best = max(best, proj + math.sqrt(r * r - perp2))
        return best
    return C.polar_outline(fn, n)


def drum(outline, z0, z1, chamfer=0.03, top_cap=False, bottom_cap=False, jag=None, scale=1.0, bm=None):
    """A stacked stone drum with chamfered joints. jag(angle)->depth lowers the top ring (broken top)."""
    if bm is None:
        bm = bmesh.new()
    pts = [(x * scale, y * scale) for x, y in outline]
    n = len(pts)
    k = 1.0 - chamfer / max(0.05, max(math.hypot(x, y) for x, y in pts))
    levels = [(z0, k), (z0 + chamfer, 1.0), (z1 - chamfer, 1.0), (z1, k)]
    if jag is not None:
        levels = levels[:3] + [(z1, 1.0)]
        raw = jag
        lim = (z1 - z0) - chamfer - 0.08

        def jag(a):
            return min(raw(a), lim)
    rings = []
    for li, (z, s) in enumerate(levels):
        ring = []
        for (x, y) in pts:
            zz = z
            if jag is not None and li == len(levels) - 1:
                zz = z1 - jag(math.atan2(y, x))
            elif jag is not None and li == len(levels) - 2:
                zz = min(z, z1 - jag(math.atan2(y, x)) - 0.02)
            ring.append(bm.verts.new((x * s, y * s, zz)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([a[i], a[j], b[j], b[i]])
    if jag is not None:
        cz = z1 - jag(None)
        cen = bm.verts.new((0, 0, cz))
        mid = []
        for v in rings[-1]:
            p = v.co * 0.5 + Vector((0, 0, cz)) * 0.5
            p.z = (v.co.z + cz) * 0.5 + 0.03 * noise.noise(v.co * 7)
            mid.append(bm.verts.new(p))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([rings[-1][i], rings[-1][j], mid[j], mid[i]])
            bm.faces.new([mid[i], mid[j], cen])
    elif top_cap:
        bm.faces.new(rings[-1])
    if bottom_cap:
        bm.faces.new(list(reversed(rings[0])))
    return bm


# ----------------------------------------------------------------------------------------------- rubble / bones

def rubble(rng, count, radius, center=(0, 0), z=0.0, size=(0.12, 0.45), avoid=None, bm=None, mat=STONE):
    """Scatter of bevelled blocks and irregular chunks, partly sunk."""
    if bm is None:
        bm = bmesh.new()
    placed = 0
    tries = 0
    while placed < count and tries < count * 8:
        tries += 1
        a = rng.uniform(0, 2 * math.pi)
        r = radius * math.sqrt(rng.random())
        x, y = center[0] + r * math.cos(a), center[1] + r * math.sin(a)
        if avoid and avoid(x, y):
            continue
        s = rng.uniform(*size) * (1.0 - 0.5 * r / max(radius, 1e-3))
        if rng.random() < 0.6:
            sx, sy, sz = s * rng.uniform(0.8, 1.6), s * rng.uniform(0.6, 1.1), s * rng.uniform(0.45, 0.9)
            p = C.box(sx, sy, sz, bevel=min(sx, sy, sz) * 0.12, seg=1)
            C.displace(p, s * 0.06, 4.0, seed=rng.randint(0, 9999))
        else:
            p = C.rand_rock(rng, (s * 0.7, s * 0.6, s * 0.45), sub=1, rough=0.35)
        C.merge(bm, p, mat=mat, matrix=M((x, y, z + s * 0.12), rng.uniform(0, 6.3), rng.uniform(-0.5, 0.5),
                                           rng.uniform(-0.5, 0.5)))
        p.free()
        placed += 1
    return bm


def fallen_drum(rng, radius=0.38, length=0.6, n=14):
    out = C.circle_pts(radius, n)
    d = drum(out, -length / 2, length / 2, chamfer=0.035, top_cap=True, bottom_cap=True)
    C.displace(d, 0.015, 3.0, seed=rng.randint(0, 999))
    C.transform(d, Matrix.Rotation(math.pi / 2, 4, 'Y'))
    C.transform(d, Matrix.Translation((0, 0, radius * 0.9)))
    return d


def skull(rng):
    bm = C.uvsphere(0.1, 10, 7)
    for v in bm.verts:
        v.co.x *= 1.15
        v.co.z *= 0.92
        if v.co.z < -0.04:
            v.co.z = -0.04 + (v.co.z + 0.04) * 0.3
        # eye sockets + nasal cavity: push in on the front
        for ey in (-0.035, 0.035):
            d = (v.co - Vector((0.1, ey, 0.0))).length
            if d < 0.04:
                v.co -= Vector((0.03 * (1 - d / 0.04), 0, 0))
    jaw = C.box(0.07, 0.085, 0.04, bevel=0.012, center=(0.075, 0, -0.06))
    C.merge(bm, jaw)
    C.transform(bm, Matrix.Translation((0, 0, 0.07)))
    C.set_mat(bm, BONE)
    return bm


def long_bone(rng, L=0.42):
    prof = [(0.0, 0), (0.03, 0.0), (0.038, 0.025), (0.02, 0.06), (0.017, L * 0.5), (0.02, L - 0.06), (0.04, L - 0.025),
            (0.03, L), (0.0, L)]
    b = C.lathe(prof, seg=6)
    C.transform(b, Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Translation((0, 0, -L / 2)))
    C.transform(b, Matrix.Translation((0, 0, 0.03)))
    C.set_mat(b, BONE)
    return b


def ribs(rng):
    bm = bmesh.new()
    for i in range(4):
        pts = []
        for k in range(7):
            t = k / 6
            a = math.pi * 0.95 * t
            pts.append(Vector((0.05 * i, 0.16 * math.sin(a) * (1 - 0.1 * i), 0.02 + 0.1 * math.sin(a) * 0.3)))
        prof = [(0.009 * math.cos(a), 0.009 * math.sin(a)) for a in [2 * math.pi * j / 4 for j in range(4)]]
        C.merge(bm, C.sweep(pts, prof, up=None, scale=lambda t: 1.0 - 0.4 * t), mat=BONE)
    return bm


def bone_pile(rng, n=3):
    bm = bmesh.new()
    for i in range(n):
        kind = rng.random()
        if kind < 0.35:
            p = skull(rng)
        elif kind < 0.8:
            p = long_bone(rng, rng.uniform(0.3, 0.46))
        else:
            p = ribs(rng)
        C.merge(bm, p, matrix=M((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), 0), rng.uniform(0, 6.3),
                                rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15)))
    return bm


# ----------------------------------------------------------------------------------------------- masonry

def masonry(x0, x1, z0, z1, thick, rng, course=0.5, blen=(0.7, 1.3), top=None, bevel=0.03, y_c=0.0,
            jitter=0.012, bm=None, mat=STONE, min_h=0.12):
    """Wall of individual blocks in running bond in the XZ plane, centred on y=y_c. top(x)->z limits the wall."""
    if bm is None:
        bm = bmesh.new()
    z = z0
    row = 0
    while z < z1 - 1e-3:
        h = min(course * rng.uniform(0.85, 1.15), z1 - z)
        if z1 - (z + h) < course * 0.4:
            h = z1 - z
        x = x0 - (rng.uniform(0.2, 0.6) if row % 2 else 0.0)
        while x < x1 - 1e-3:
            L = rng.uniform(*blen)
            xa, xb = max(x, x0), min(x + L, x1)
            if x1 - xb < 0.3:
                xb = x1
            if xb - xa > 0.12:
                zt = z + h
                if top is not None:
                    tz = min(top(xa), top(xb), top((xa + xb) / 2))
                    if tz < z + min_h:
                        x = xb
                        continue
                    zt = min(zt, tz)
                bx = C.box(xb - xa - 0.012, thick + rng.uniform(-0.03, 0.03), zt - z - 0.012, bevel=bevel, seg=1,
                           center=((xa + xb) / 2, y_c + rng.uniform(-jitter, jitter), (z + zt) / 2))
                if top is not None and zt < z + h - 1e-3:  # broken block: knock the top about
                    for v in bx.verts:
                        if v.co.z > (z + zt) / 2:
                            v.co.z -= rng.uniform(0.0, 0.12)
                C.merge(bm, bx, mat=mat)
                bx.free()
            x = xb
        z += h
        row += 1
    return bm


def voussoirs(path2, profile, rng, y_c=0.0, gap=0.012, per=3, keep=None, bm=None, mat=STONE, drop_last=None):
    """Split a 2D arch path (x, z) into individual swept stones."""
    if bm is None:
        bm = bmesh.new()
    pts = [Vector((x, y_c, z)) for x, z in path2]
    i = 0
    idx = 0
    while i < len(pts) - 1:
        seg = pts[i:i + per + 1]
        if len(seg) >= 2 and (keep is None or keep(idx)):
            a, b = seg[0], seg[-1]
            d0 = (seg[1] - seg[0]).normalized()
            d1 = (seg[-1] - seg[-2]).normalized()
            seg = [a + d0 * gap * 0.5] + seg[1:-1] + [b - d1 * gap * 0.5]
            s = C.sweep(seg, profile, up=(0, 1, 0), closed=False, closed_profile=True)
            bmesh.ops.recalc_face_normals(s, faces=s.faces)
            if drop_last is not None and idx == drop_last:
                C.transform(s, Matrix.Translation(-seg[0]) )
                C.transform(s, Matrix.Rotation(rng.uniform(-0.25, 0.25), 4, 'Y'))
                C.transform(s, Matrix.Translation(seg[0] + Vector((0.02, 0, -0.04))))
            C.merge(bm, s, mat=mat)
            s.free()
        i += per
        idx += 1
    return bm


ARCH_PROFILE = [(0.0, -0.26), (0.05, -0.31), (0.3, -0.31), (0.3, -0.38), (0.35, -0.44), (0.62, -0.44),
                (0.62, 0.44), (0.35, 0.44), (0.3, 0.38), (0.3, 0.31), (0.05, 0.31), (0.0, 0.26)]


def pier(rng, height, scale=1.0, capital=True, jag=None, tilt=0.0, bm=None):
    """Clustered gothic pier of stacked drums on a moulded base."""
    if bm is None:
        bm = bmesh.new()
    out = cluster_outline(core=0.35 * scale, shaft=0.12 * scale, shaft_d=0.36 * scale, small=0.07 * scale,
                          small_d=0.37 * scale)
    base_h = 0.32 * scale
    C.merge(bm, C.box(1.08 * scale, 1.08 * scale, base_h + 0.25, bevel=0.03, seg=1, center=(0, 0, (base_h - 0.25) / 2)),
            mat=STONE)
    mould = drum(out, base_h, base_h + 0.16 * scale, chamfer=0.05, scale=1.18, top_cap=True)
    C.merge(bm, mould, mat=STONE)
    z = base_h + 0.16 * scale
    top = height - (0.42 * scale if capital else 0.0)
    while z < top - 1e-3:
        h = min(rng.uniform(0.5, 0.7) * scale, top - z)
        if top - (z + h) < 0.25:
            h = top - z
        last = z + h >= top - 1e-3
        d = drum(out, z, z + h, chamfer=0.025, top_cap=last and capital, jag=jag if (last and not capital) else None)
        off = Vector((rng.uniform(-0.015, 0.015), rng.uniform(-0.015, 0.015), 0))
        C.merge(bm, d, mat=STONE, matrix=Matrix.Translation(off) @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 4, 'Z'))
        z += h
    if capital:
        cap = drum(out, top, top + 0.22 * scale, chamfer=0.05, scale=1.14, top_cap=True)
        C.merge(bm, cap, mat=STONE)
        C.merge(bm, C.box(1.0 * scale, 1.0 * scale, 0.2 * scale, bevel=0.03, seg=1,
                          center=(0, 0, top + 0.32 * scale)), mat=STONE)
    if tilt:
        C.transform(bm, Matrix.Rotation(tilt, 4, 'X'))
    return bm


def jag_fn(rng, depth=0.55):
    seed = rng.uniform(0, 100)
    lean = rng.uniform(0, 2 * math.pi)

    def f(a):
        if a is None:
            return depth * 0.25
        n = noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, seed)))
        side = 0.5 + 0.5 * math.cos(a - lean)
        return max(0.0, depth * (0.35 + 0.45 * n + 0.5 * side))
    return f


def broken_pillar(rng, height, scale=0.9):
    """Free-standing broken pier; returns (bmesh, top point for perching)."""
    jag = jag_fn(rng, depth=rng.uniform(0.35, 0.7))
    bm = pier(rng, height, scale=scale, capital=False, jag=jag)
    top = Vector((0, 0, height - jag(None)))
    return bm, top


# ----------------------------------------------------------------------------------------------- arches

def arch_fragment(rng, bays=2, span=3.0, spring=3.2, k=1.0, wall_top=None, broken_right=0, thick=0.88,
                  scale=1.0):
    """Arcade fragment of `bays` pointed arches on clustered piers, with masonry spandrels.

    broken_right: number of voussoir stones missing at the right end of the last arch (and its pier shortened).
    Returns (bmesh, perch points).
    """
    bm = bmesh.new()
    perches = []
    pitch = span + 0.9 * scale
    width = bays * pitch
    xs = [-width / 2 + pitch * i for i in range(bays + 1)]
    rise = C.arch_height(span, k)
    top_z = spring + rise + 0.62 + 0.9
    if wall_top is None:
        seed = rng.uniform(0, 100)

        def wall_top(x):
            t = (x + width / 2) / width
            drop = max(0.0, t - 0.5) * (5.0 + 1.2 * broken_right) if broken_right else 0.0
            return top_z - drop - 1.1 * abs(noise.noise(Vector((x * 0.45, seed, 0))))
    for i, x in enumerate(xs):
        h = spring
        last = i == len(xs) - 1
        if last and broken_right:
            jag = jag_fn(rng, 0.6)
            p = pier(rng, spring * 0.62, scale=scale * 0.95, capital=False, jag=jag)
            perches.append(Vector((x, 0, spring * 0.62 - jag(None))))
        else:
            p = pier(rng, h, scale=scale * 0.95)
        C.merge(bm, p, matrix=Matrix.Translation((x, 0, 0)))
    # arches
    for b in range(bays):
        cx = (xs[b] + xs[b + 1]) / 2
        path = [(cx + x, spring + z) for x, z in C.pointed_arch(span, k, n=12)]
        nst = (len(path) - 1 + 2) // 3
        keep = None
        if broken_right and b == bays - 1:
            cutoff = nst - broken_right

            def keep(i, cutoff=cutoff):
                return i < cutoff
        voussoirs(path, [(u * scale, v * thick / 0.88) for u, v in ARCH_PROFILE], rng, keep=keep, bm=bm,
                  drop_last=(nst - broken_right - 1) if (broken_right and b == bays - 1) else None)
    # spandrel masonry with the arch extrados cut out
    wall = masonry(xs[0] - 0.5 * scale, xs[-1] + 0.5 * scale, spring + 0.32 * scale, top_z, thick * 0.92, rng,
                   course=0.48, top=wall_top, bevel=0.025)
    cut = bmesh.new()
    for b in range(bays):
        cx = (xs[b] + xs[b + 1]) / 2
        ext = 0.62 * scale
        outline = [(cx + x, spring + z) for x, z in C.pointed_arch(span + 2 * ext, (k * span + ext) / (span + 2 * ext),
                                                                   n=14, leg=1.0)]
        C.merge(cut, xz_to_y(outline, -2, 2))
    wall = C.boolean(wall, cut, 'DIFFERENCE', self_inter=True)
    C.merge(bm, wall, mat=STONE)
    tops = [Vector((x, 0, wall_top(x))) for x in (xs[0] + 0.3, (xs[0] + xs[1]) / 2)]
    perches += [t for t in tops if t.z > spring + rise]
    return bm, perches


# ----------------------------------------------------------------------------------------------- rose window

def rose_window(rng):
    """Cathedral facade fragment with a rose window (~11 m), front faces -Y. Returns (bmesh, perches)."""
    bm = bmesh.new()
    perches = []
    W = 10.4
    T = 1.2
    RC = 6.7                # rose centre height
    R = 3.0                 # opening radius
    ring_w = 0.6
    seed = rng.uniform(0, 100)

    def top(x):
        # gable peaking left of centre, broken away on the right
        t = (x + W / 2) / W
        g = 10.9 - abs(x + 0.6) * 0.5
        if t > 0.62:
            g -= (t - 0.62) * 10.0
        return g - 0.45 * abs(noise.noise(Vector((x * 0.7, seed, 1.0))))
    wall = masonry(-W / 2, W / 2, 0.0, 11.0, T, rng, course=0.5, blen=(0.8, 1.4), top=top, bevel=0.03)
    cut = bmesh.new()
    C.merge(cut, xz_to_y(C.circle_pts(R + ring_w - 0.02, 48, 0, RC), -2, 2), mat=STONE)
    # blind arcade niches below the rose (recessed 0.28 m, dark backs)
    n_niche, pitch, nw = 6, 1.45, 0.92
    for i in range(n_niche):
        cx = -pitch * (n_niche - 1) / 2 + pitch * i
        out = [(cx + x, 1.75 + z) for x, z in C.pointed_arch(nw, 1.0, n=6, leg=1.4)]
        C.merge(cut, xz_to_y(out, -T / 2 - 0.3, -T / 2 + 0.28), mat=DARK)
    wall = C.boolean(wall, cut, 'DIFFERENCE', self_inter=True)
    C.merge(bm, wall)
    for i in range(n_niche + 1):
        cx = -pitch * (n_niche - 1) / 2 + pitch * (i - 0.5)
        col = C.lathe([(0.0, 0.0), (0.16, 0.0), (0.16, 0.2), (0.11, 0.3), (0.085, 0.36), (0.085, 1.6), (0.12, 1.66),
                       (0.15, 1.72), (0.15, 1.82), (0.0, 1.82)], seg=10)
        C.merge(bm, col, mat=STONE, matrix=Matrix.Translation((cx, -T / 2 - 0.02, 0)))
    for i in range(n_niche):
        cx = -pitch * (n_niche - 1) / 2 + pitch * i
        pts = [(cx + x, 1.78 + z) for x, z in C.pointed_arch(nw + 0.24, 1.0, n=6)]
        s = C.sweep([Vector((x, -T / 2 - 0.01, z)) for x, z in pts],
                    [(-0.08, 0), (-0.06, 0.1), (0.06, 0.1), (0.08, 0)], up=(0, -1, 0), closed=False,
                    closed_profile=False, caps=False)
        C.merge(bm, s, mat=STONE)
    # string course under the rose
    sc = C.sweep([Vector((-W / 2, -T / 2, 3.0)), Vector((W * 0.3, -T / 2, 3.0))],
                 [(-0.14, 0), (-0.1, 0.2), (0.08, 0.22), (0.14, 0.0)], up=(0, -1, 0), closed=False,
                 closed_profile=False, caps=False)
    C.merge(bm, sc, mat=STONE)
    # moulded voussoir ring (splayed toward the front)
    prof = [(0.0, -0.1), (0.08, -0.3), (0.22, -0.34), (0.26, -0.5), (0.42, -0.58), (ring_w, -0.62),
            (ring_w, 0.6), (0.0, 0.6)]
    circ = [(R * math.cos(a), RC + R * math.sin(a)) for a in [math.pi - 2 * math.pi * i / 72 for i in range(73)]]
    voussoirs(circ, prof, rng, per=3, bm=bm, keep=lambda i: not (15 <= i <= 16))
    # tracery: 12 spokes, petals with pointed heads, oculus with sexfoil, roundels
    trac = bmesh.new()
    d = 0.34

    def bar(w):
        c = w * 0.22
        return [(-w / 2, -d / 2 + c), (-w / 2 + c, -d / 2), (w / 2 - c, -d / 2), (w / 2, -d / 2 + c),
                (w / 2, d / 2 - c), (w / 2 - c, d / 2), (-w / 2 + c, d / 2), (-w / 2, d / 2 - c)]

    def tr(pts2, w, closed=True):
        s = C.sweep([Vector((x, 0.15, z)) for x, z in pts2], bar(w), up=(0, 1, 0), closed=closed, closed_profile=True)
        C.merge(trac, s, mat=STONE)
        s.free()
    missing = {7, 8}        # broken sector (lower right)
    tr(C.circle_pts(0.74, 28, 0, RC), 0.2)
    tr([(x, RC + z) for x, z in C.foil(6, 0.34, 0.29, n=48, rot=math.pi / 2)], 0.12)
    tr(C.circle_pts(1.62, 40, 0, RC, a0=math.pi * 0.2, a1=math.pi * 1.85, closed=False), 0.14, closed=False)
    for i in range(12):
        a = math.pi / 2 + 2 * math.pi * i / 12
        ca, sa = math.cos(a), math.sin(a)
        if i in missing:
            continue
        tr([(0.74 * ca, RC + 0.74 * sa), ((R + 0.05) * ca, RC + (R + 0.05) * sa)], 0.16, closed=False)
    for i in range(12):
        a = math.pi / 2 + 2 * math.pi * (i + 0.5) / 12
        if i in missing or (i + 1) % 12 in missing:
            continue
        chord = 2 * 2.25 * math.sin(math.pi / 12) - 0.16
        head = C.pointed_arch(chord, 1.0, n=6, leg=0.45)
        rot = a - math.pi / 2
        cr, sr = math.cos(rot), math.sin(rot)
        base_r = 1.92
        pts = [((x * cr - (z + base_r) * sr), RC + (x * sr + (z + base_r) * cr)) for x, z in head]
        tr(pts, 0.1, closed=False)
        tc = (2.46 * math.cos(a), RC + 2.46 * math.sin(a))
        tr([(tc[0] + x, tc[1] + z) for x, z in C.foil(3, 0.065, 0.08, n=18, rot=a)], 0.06)
        a2 = a + math.pi / 12
        tr(C.circle_pts(0.17, 12, 2.83 * math.cos(a2), RC + 2.83 * math.sin(a2)), 0.07)
    C.merge(bm, trac)
    # buttresses: left intact with pinnacle, right broken
    for side, h in ((-1, 8.4), (1, 4.6)):
        x = side * (W / 2 + 0.35)
        steps = [(0.0, h * 0.45, 1.9), (h * 0.45, h * 0.75, 1.45), (h * 0.75, h, 1.05)]
        for z0, z1, depth in steps:
            b = C.box(1.15, depth, z1 - z0, bevel=0.04, seg=1, center=(x, -T / 2 - depth / 2 + 0.5, (z0 + z1) / 2))
            C.merge(bm, b, mat=STONE)
            # sloped weathering on the set-off
            sl = C.box(1.2, depth, 0.12, bevel=0.02, center=(x, -T / 2 - depth / 2 + 0.5, z1 + 0.04))
            for v in sl.verts:
                if v.co.z > z1 + 0.04 and v.co.y < -T / 2 - depth / 2 + 0.5:
                    v.co.z -= 0.08
            C.merge(bm, sl, mat=STONE)
        yc = -T / 2 - 1.05 / 2 + 0.5
        if side < 0:
            pin = C.lathe([(0.0, h), (0.42, h), (0.42, h + 0.5), (0.36, h + 0.55), (0.0, h + 2.2)], seg=4,
                          phase=math.pi / 4)
            C.merge(bm, pin, mat=STONE, matrix=Matrix.Translation((x, yc, 0)))
            for cx_, cy_ in ((-0.45, -0.38), (0.45, -0.38), (-0.45, 0.38), (0.45, 0.38)):
                p2 = C.lathe([(0.0, h), (0.1, h), (0.0, h + 0.9)], seg=4)
                C.merge(bm, p2, mat=STONE, matrix=Matrix.Translation((x + cx_, yc + cy_, 0)))
            perches.append(Vector((x - 0.22, yc - 0.3, h)))
        else:
            jb = C.box(1.15, 1.9, 0.6, bevel=0.04, center=(x, -T / 2 - 0.95 + 0.5, h + 0.2))
            for v in jb.verts:
                if v.co.z > h + 0.2:
                    v.co.z -= rng.uniform(0.0, 0.5)
            C.merge(bm, jb, mat=STONE)
    # broken tracery and blocks at the foot (lower right, where the sector fell out)
    rb = rubble(rng, 26, 3.0, center=(2.4, -2.2), size=(0.18, 0.55))
    C.merge(bm, rb)
    for i in range(3):
        frag = C.sweep([Vector((0, 0, 0)), Vector((rng.uniform(0.8, 1.4), 0, 0))], bar(0.16), up=(0, 0, 1),
                       closed=False)
        C.merge(bm, frag, mat=STONE, matrix=M((rng.uniform(0.8, 3.6), rng.uniform(-3.2, -1.4), 0.1),
                                              rng.uniform(0, 6.3)))
    return bm, perches


# ----------------------------------------------------------------------------------------------- graves

def gravestone(rng, kind=None):
    kind = kind or rng.choice(["round", "gothic", "cross", "celtic", "slab"])
    bm = bmesh.new()
    th = rng.uniform(0.13, 0.18)
    if kind == "round":
        w, h = rng.uniform(0.55, 0.7), rng.uniform(0.75, 1.05)
        out = [(-w / 2, -0.2), (w / 2, -0.2)] + [(w / 2 * math.cos(a), h - w / 2 + w / 2 * math.sin(a))
                                                  for a in [math.pi * i / 10 for i in range(11)]] + [(-w / 2, -0.2)]
        out = out[:-1]
    elif kind == "gothic":
        w, h = rng.uniform(0.55, 0.7), rng.uniform(0.9, 1.25)
        arch = C.pointed_arch(w, 1.0, n=5)
        ah = C.arch_height(w)
        out = [(-w / 2, -0.2)] + [(x, h - ah + z) for x, z in arch] + [(w / 2, -0.2)]
    elif kind == "slab":
        w, h = rng.uniform(0.6, 0.8), rng.uniform(0.55, 0.8)
        out = [(-w / 2, -0.2), (w / 2, -0.2), (w / 2, h - 0.08), (w / 2 - 0.08, h), (-w / 2 + 0.08, h), (-w / 2, h - 0.08)]
    else:
        a, h = rng.uniform(0.11, 0.14), rng.uniform(1.25, 1.7)
        arm_z, arm_w = h * 0.68, rng.uniform(0.32, 0.42) if kind == "cross" else rng.uniform(0.4, 0.46)
        out = [(-a, -0.2), (a, -0.2), (a, arm_z - a), (arm_w, arm_z - a), (arm_w, arm_z + a), (a, arm_z + a),
               (a, h), (-a, h), (-a, arm_z + a), (-arm_w, arm_z + a), (-arm_w, arm_z - a), (-a, arm_z - a)]
        th = a * 1.5
    # chip the outline
    chipped = []
    for x, z in out:
        if z > 0.2 and rng.random() < 0.25:
            chipped.append((x * rng.uniform(0.88, 0.97), z - rng.uniform(0.0, 0.05)))
        else:
            chipped.append((x, z))
    body = xz_to_y(chipped, -th / 2, th / 2)
    bmesh.ops.bevel(body, geom=list(body.edges), offset=0.012, segments=1, affect='EDGES', clamp_overlap=True)
    C.displace(body, 0.008, 5.0, seed=rng.randint(0, 999))
    C.merge(bm, body, mat=STONE)
    prof = [(-0.025, 0), (-0.012, 0.018), (0.012, 0.018), (0.025, 0)]
    if kind in ("round", "gothic", "slab"):
        # carved border + cross relief on the front face
        inset = 0.07
        if kind == "round":
            w2 = w / 2 - inset
            border = [(-w2, 0.1), (w2, 0.1)] + [(w2 * math.cos(a), h - w / 2 + w2 * math.sin(a))
                                               for a in [math.pi * i / 10 for i in range(11)]][1:]
        elif kind == "gothic":
            w2 = w - 2 * inset
            border = [(-w2 / 2, 0.1)] + [(x, h - ah + z - 0.02) for x, z in C.pointed_arch(w2, 1.0, n=5)] + [(w2 / 2, 0.1)]
        else:
            border = [(-w / 2 + inset, 0.1), (w / 2 - inset, 0.1), (w / 2 - inset, h - inset), (-w / 2 + inset, h - inset)]
        s = C.sweep([Vector((x, -th / 2, z)) for x, z in border], prof, up=(0, -1, 0), closed=True, closed_profile=False,
                    caps=False)
        C.merge(bm, s, mat=STONE)
        cz = h * 0.62
        for p0, p1 in (((0, cz - 0.2), (0, cz + 0.14)), ((-0.1, cz + 0.02), (0.1, cz + 0.02))):
            s = C.sweep([Vector((p0[0], -th / 2, p0[1])), Vector((p1[0], -th / 2, p1[1]))],
                        [(-0.02, 0), (-0.01, 0.02), (0.01, 0.02), (0.02, 0)], up=(0, -1, 0), closed=False,
                        closed_profile=False, caps=False)
            C.merge(bm, s, mat=STONE)
    if kind == "celtic":
        ring = C.sweep([Vector((0.3 * math.cos(t), 0, arm_z + 0.3 * math.sin(t))) for t in
                        [2 * math.pi * i / 24 for i in range(24)]],
                       [(-0.05, -th * 0.42), (0.05, -th * 0.42), (0.05, th * 0.42), (-0.05, th * 0.42)], up=(0, 1, 0),
                       closed=True, closed_profile=True)
        bmesh.ops.recalc_face_normals(ring, faces=ring.faces)
        C.merge(bm, ring, mat=STONE)
    # little base mound
    if kind in ("cross", "celtic") or rng.random() < 0.5:
        C.merge(bm, C.box(0.5 if kind in ("cross", "celtic") else w + 0.12, 0.42, 0.28, bevel=0.03, center=(0, 0, -0.06)),
                mat=STONE)
    moss_tops(bm, thresh=0.5, scale=3.0, cut=0.1, seed=rng.uniform(0, 50))
    return bm


def tomb_pinnacle(rng, h=3.0):
    """Gothic tomb monument: stepped plinth, niched shaft with corner colonnettes, gables and a truncated spire
    with a flat cap (perch). Returns (bm, perch point)."""
    bm = bmesh.new()
    C.merge(bm, C.box(1.15, 1.15, 0.34, bevel=0.03, center=(0, 0, 0.05)), mat=STONE)
    C.merge(bm, C.box(0.95, 0.95, 0.5, bevel=0.03, center=(0, 0, 0.47)), mat=STONE)
    C.merge(bm, C.box(1.03, 1.03, 0.08, bevel=0.02, center=(0, 0, 0.76)), mat=STONE)
    z0 = 0.8
    hs = max(0.9, h - 2.03)
    z1 = z0 + hs
    C.merge(bm, C.box(0.7, 0.7, hs, bevel=0.02, center=(0, 0, (z0 + z1) / 2)), mat=STONE)
    arch = [(x, z + z1 - 0.14 - C.arch_height(0.36)) for x, z in C.pointed_arch(0.36, 1.0, n=5)]
    niche = [(-0.18, z0 + 0.16)] + arch + [(0.18, z0 + 0.16)]
    rib = [(-0.03, 0), (-0.015, 0.03), (0.015, 0.03), (0.03, 0)]
    for k in range(4):
        rot = Matrix.Rotation(k * math.pi / 2, 4, 'Z')
        C.merge(bm, xz_to_y(niche, -0.36, -0.345), mat=DARK, matrix=rot)
        path = [Vector((x, -0.352, z)) for x, z in niche]
        C.merge(bm, C.sweep(path, rib, up=(0, -1, 0), closed=False, closed_profile=False, caps=False), mat=STONE,
                matrix=rot)
        # gable over the niche
        gable = [(-0.38, z1), (0.38, z1), (0.0, z1 + 0.5)]
        C.merge(bm, xz_to_y(gable, -0.37, -0.25), mat=STONE, matrix=rot)
        # corner colonnette + pinnacle
        cx, cy = 0.35 * math.cos(math.pi / 4 + k * math.pi / 2) * math.sqrt(2), \
            0.35 * math.sin(math.pi / 4 + k * math.pi / 2) * math.sqrt(2)
        col = C.lathe([(0.0, z0), (0.07, z0), (0.05, z0 + 0.06), (0.05, z1 - 0.06), (0.075, z1), (0.0, z1)], seg=6)
        C.merge(bm, col, mat=STONE, matrix=Matrix.Translation((cx, cy, 0)))
        pin = C.lathe([(0.0, z1), (0.07, z1), (0.07, z1 + 0.12), (0.0, z1 + 0.42)], seg=4, phase=math.pi / 4)
        C.merge(bm, pin, mat=STONE, matrix=Matrix.Translation((cx, cy, 0)))
    C.merge(bm, C.box(0.84, 0.84, 0.08, bevel=0.02, center=(0, 0, z1 + 0.04)), mat=STONE)
    # truncated spire + cap
    zs = z1 + 0.08
    sp = C.lathe([(0.0, zs), (0.5, zs), (0.21, zs + 0.95), (0.0, zs + 0.95)], seg=4, phase=math.pi / 4)
    C.merge(bm, sp, mat=STONE)
    top = zs + 0.95
    C.merge(bm, C.box(0.3, 0.3, 0.07, bevel=0.015, center=(0, 0, top + 0.035)), mat=STONE)
    C.displace(bm, 0.006, 4.0, seed=rng.randint(0, 999))
    moss_tops(bm, thresh=0.8, scale=2.5, cut=0.15, seed=rng.uniform(0, 50))
    return bm, Vector((0, 0, top + 0.07))


# ----------------------------------------------------------------------------------------------- trees

def dead_tree(rng, height=6.0, spread=1.0, gnarl=1.0, depth=4):
    bm = bmesh.new()
    branches = []

    def grow(p, d, length, radius, level):
        nseg = max(3, int(length / 0.32))
        pts, rad = [p.copy()], [radius]
        dd = d.copy()
        for i in range(nseg):
            jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.6))) * (0.32 * gnarl)
            up = Vector((0, 0, 0.12 if level < 2 else -0.04))
            dd = (dd + jitter + up).normalized()
            p = p + dd * (length / nseg)
            pts.append(p.copy())
            rad.append(radius * (1.0 - 0.78 * (i + 1) / nseg))
        branches.append((pts, rad, level))
        if level >= depth:
            return
        kids = rng.randint(2, 4) if level > 0 else rng.randint(3, 4)
        for c in range(kids):
            t = rng.uniform(0.45, 0.95) if level > 0 else rng.uniform(0.55, 0.92)
            idx = min(len(pts) - 1, max(1, int(t * (len(pts) - 1))))
            base_dir = (pts[idx] - pts[idx - 1]).normalized()
            axis = base_dir.orthogonal().normalized()
            axis.rotate(Matrix.Rotation(rng.uniform(0, 2 * math.pi), 3, base_dir))
            ang = rng.uniform(0.45, 0.95) * spread
            nd = base_dir.copy()
            nd.rotate(Matrix.Rotation(ang, 3, axis))
            grow(pts[idx], nd, length * rng.uniform(0.55, 0.75), rad[idx] * rng.uniform(0.6, 0.8), level + 1)

    trunk_dir = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 1)).normalized()
    grow(Vector((0, 0, -0.2)), trunk_dir, height * 0.55, 0.21 * height / 6.0 + 0.12, 0)
    # roots
    for r in range(rng.randint(4, 6)):
        a = 2 * math.pi * r / 5 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), -0.35)).normalized()
        pts, rad = [], []
        p = Vector((0, 0, 0.45))
        L = rng.uniform(0.9, 1.6) * height / 6.0
        for i in range(6):
            t = i / 5
            pts.append(p + Vector((d.x * L * t, d.y * L * t, -0.55 * t * t - 0.1 * t)))
            rad.append((0.22 * height / 6.0 + 0.08) * (1.0 - 0.85 * t))
        branches.append((pts, rad, 1))
    for pts, rad, level in branches:
        sides = 8 if level == 0 else (6 if level == 1 else (5 if level == 2 else 4))
        prof = [(math.cos(2 * math.pi * j / sides), math.sin(2 * math.pi * j / sides)) for j in range(sides)]
        s = C.sweep(pts, prof, up=None, closed=False, scale=[max(0.006, r) for r in rad])
        # gnarled bark
        for v in s.verts:
            v.co += Vector(noise.noise_vector(v.co * 2.2)) * 0.035 * (1.5 if level == 0 else 0.6)
        C.merge(bm, s, mat=WOOD)
        s.free()
    return bm


# ----------------------------------------------------------------------------------------------- iron chains

def hanging_chain(rng, top_z, bottom_z, link=0.13, wire=0.024, hook=True):
    bm = bmesh.new()
    z = top_z
    i = 0
    sway = rng.uniform(0, 6.3)
    while z > bottom_z:
        t = C.torus(link, wire, seg=6, rseg=4, sx=1.0)
        C.transform(t, Matrix.Rotation(math.pi / 2, 4, 'X') @ Matrix.Diagonal((0.62, 1.0, 1.0, 1)))
        rot = Matrix.Rotation(math.pi / 2 * (i % 2) + 0.04 * math.sin(sway + i * 0.3), 4, 'Z')
        C.merge(bm, t, mat=IRON, matrix=Matrix.Translation((0, 0, z)) @ rot)
        z -= link * 1.45
        i += 1
    if hook:
        pts = []
        for k in range(14):
            tt = k / 13
            if tt < 0.35:
                pts.append(Vector((0, 0, -tt / 0.35 * 0.45)))
            else:
                a = math.pi * 1.25 * (tt - 0.35) / 0.65
                pts.append(Vector((0.2 - 0.2 * math.cos(a), 0, -0.45 - 0.2 * math.sin(a))))
        prof = [(0.04 * math.cos(a), 0.04 * math.sin(a)) for a in [2 * math.pi * j / 6 for j in range(6)]]
        s = C.sweep(pts, prof, up=None, closed=False, scale=lambda t: 1.0 - 0.75 * t ** 2)
        C.merge(bm, s, mat=IRON, matrix=Matrix.Translation((0, 0, z + link * 0.4)))
        ring = C.torus(0.07, 0.022, seg=8, rseg=4)
        C.merge(bm, ring, mat=IRON, matrix=Matrix.Translation((0, 0, z + link * 0.45)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    return bm


# ----------------------------------------------------------------------------------------------- crows

def crow(rng, pose="perch", head_turn=0.0):
    """Raven ~0.55 m long, facing +X, feet at z=0."""
    bm = bmesh.new()
    body = C.uvsphere(1.0, 10, 7)
    C.transform(body, M((0.0, 0, 0.17), ry=math.radians(-28), s=(0.17, 0.085, 0.092)))
    C.merge(bm, body, mat=CROW)
    head = bmesh.new()
    hs = C.uvsphere(1.0, 8, 6)
    C.transform(hs, M((0.0, 0, 0.0), s=(0.068, 0.052, 0.056)))
    C.merge(head, hs, mat=CROW)
    beak = C.lathe([(0.0, 0.0), (0.02, 0.0), (0.013, 0.05), (0.0, 0.085)], seg=5)
    for v in beak.verts:
        v.co.x *= 0.75
        v.co.y *= 1.25
        v.co.y -= 0.12 * (v.co.z / 0.085) ** 2 * 0.1
    C.transform(beak, Matrix.Rotation(math.pi / 2, 4, 'Y'))
    for v in beak.verts:
        v.co.z -= 0.25 * (max(0.0, v.co.x) / 0.085) ** 2 * 0.06
    C.merge(head, beak, mat=CROW, matrix=Matrix.Translation((0.05, 0, -0.008)))
    # throat hackles
    for k in range(3):
        sp = C.lathe([(0.0, 0.0), (0.012, 0.0), (0.0, 0.035)], seg=4)
        C.merge(head, sp, mat=CROW, matrix=M((0.02, (k - 1) * 0.015, -0.04), ry=math.radians(160)))
    C.merge(bm, head, matrix=M((0.16, 0, 0.255), rz=head_turn))
    # tail: flat fan
    tail = C.prism([(0.0, -0.035), (-0.19, -0.06), (-0.21, 0.0), (-0.19, 0.06), (0.0, 0.035)], -0.008, 0.008)
    C.merge(bm, tail, mat=CROW, matrix=M((-0.12, 0, 0.115), ry=math.radians(-18)))
    if pose == "spread":
        for sgn in (-1, 1):
            wing = [(0.0, 0.0), (0.07, 0.0), (0.05, 0.2), (0.0, 0.36), (-0.06, 0.42), (-0.1, 0.40), (-0.08, 0.36),
                    (-0.13, 0.36), (-0.1, 0.31), (-0.15, 0.29), (-0.11, 0.24), (-0.15, 0.2), (-0.1, 0.15), (-0.12, 0.05)]
            w = C.prism([(x, sgn * y) for x, y in wing], -0.008, 0.008)
            C.merge(bm, w, mat=CROW, matrix=M((0.05, sgn * 0.05, 0.22), rx=sgn * math.radians(35), ry=math.radians(-10)))
    else:
        for sgn in (-1, 1):
            wg = C.uvsphere(1.0, 8, 5)
            C.transform(wg, M((-0.06, sgn * 0.068, 0.17), ry=math.radians(-14), rz=sgn * math.radians(-4),
                              s=(0.19, 0.022, 0.07)))
            C.merge(bm, wg, mat=CROW)
    for sgn in (-1, 1):
        leg = C.lathe([(0.0, 0.0), (0.008, 0.0), (0.007, 0.09), (0.0, 0.095)], seg=4)
        C.merge(bm, leg, mat=CROW, matrix=Matrix.Translation((0.02, sgn * 0.03, 0.0)))
        for a in (-0.4, 0.0, 0.4, math.pi):
            toe = C.box(0.05, 0.008, 0.008, center=(0.025, 0, 0.004))
            C.merge(bm, toe, mat=CROW, matrix=M((0.02, sgn * 0.03, 0), rz=a))
    return bm


# ----------------------------------------------------------------------------------------------- island

def island(rng, rx, ry, depth, tile=0.55, clear=None, flat=None, cx=0.0, cy=0.0, z_top=0.0, n_edge=200,
           spikes=8, tiles_on=True, border=None, edge_noise=0.12):
    """Floating rock island with a flagstone top at z_top. Returns (floor_bm, rock_bm, boundary fn).

    clear(x, y) -> True skips tiles (under the altar); flat(x, y) -> True keeps tiles level.
    border: (inner_half, outer_half) square ring of large slabs.
    """
    seed = rng.uniform(0, 100)

    def rad(theta):
        c, s = math.cos(theta), math.sin(theta)
        base = 1.0 / math.sqrt((c / rx) ** 2 + (s / ry) ** 2)
        n1 = noise.noise(Vector((c * 1.3, s * 1.3, seed)))
        n2 = noise.noise(Vector((c * 4.1, s * 4.1, seed + 3)))
        n3 = noise.noise(Vector((c * 11.0, s * 11.0, seed + 9)))
        bite = 0.0
        return base * (1.0 + edge_noise * n1 + 0.06 * n2 + 0.025 * n3) - bite

    def inside(x, y, margin=0.0):
        th = math.atan2(y - cy, x - cx)
        return math.hypot(x - cx, y - cy) < rad(th) - margin

    floor = bmesh.new()
    if tiles_on:
        R = max(rx, ry) * 1.25
        y = cy - R
        row = 0
        while y < cy + R:
            hrow = tile * rng.uniform(0.9, 1.1)
            x = cx - R - (rng.uniform(0.15, 0.5) * tile if row % 2 else 0)
            while x < cx + R:
                L = tile * rng.uniform(0.8, 1.55)
                x0, x1, y0, y1 = x, x + L, y, y + hrow
                x = x1
                if border:
                    o = border[1] + 0.03
                    if x0 < o and x1 > -o and y0 < o and y1 > -o:
                        ox = min(x1, o) - max(x0, -o)
                        oy = min(y1, o) - max(y0, -o)
                        if ox <= oy:
                            if (x0 + x1) > 0:
                                x0 = o
                            else:
                                x1 = -o
                        else:
                            if (y0 + y1) > 0:
                                y0 = o
                            else:
                                y1 = -o
                        if x1 - x0 < 0.22 or y1 - y0 < 0.22 or (x0 < o and x1 > -o and y0 < o and y1 > -o):
                            continue
                mx, my = (x0 + x1) / 2, (y0 + y1) / 2
                if clear and clear(mx, my):
                    continue
                if not inside(mx, my):
                    continue
                edge_d = rad(math.atan2(my - cy, mx - cx)) - math.hypot(mx - cx, my - cy)
                if edge_d < 1.6 and rng.random() < 0.18 * (1.6 - edge_d):
                    continue
                if rng.random() < 0.025 and not (flat and flat(mx, my)):
                    continue
                _tile(floor, rng, x0, x1, y0, y1, z_top, flat(mx, my) if flat else False, edge_d)
            y += hrow
            row += 1
        if border:
            _border_ring(floor, rng, border[0], border[1], z_top, flat)
    # rock body
    rock = bmesh.new()
    rings_d = [0.0, 0.18, 0.5, 0.95, 1.6, 2.5, 3.6, 5.0, 6.6, 8.4, 10.5]
    rings_s = [1.0, 1.015, 1.0, 0.95, 0.88, 0.78, 0.66, 0.52, 0.38, 0.24, 0.1]
    scale_d = depth / 10.5
    verts = []
    for k, (d, s) in enumerate(zip(rings_d, rings_s)):
        ring = []
        for i in range(n_edge):
            th = 2 * math.pi * i / n_edge
            r = rad(th) * s
            p = Vector((cx + r * math.cos(th), cy + r * math.sin(th), z_top - 0.07 - d * scale_d))
            if k > 0:
                q = Vector((p.x * 0.35, p.y * 0.35, p.z * 0.6 + seed))
                cell = noise.cell(Vector((p.x * 0.5, p.y * 0.5, p.z * 0.9 + seed)))
                radial = Vector((math.cos(th), math.sin(th), 0))
                p += radial * (noise.noise(q) * 0.9 + (cell - 0.5) * 0.9) * min(1.0, k / 2) * max(rx, ry) / 14
                p.z += noise.noise(q * 1.7 + Vector((5, 5, 5))) * 0.5 * k / 3 * scale_d
                if k >= 6:
                    p.z -= max(0.0, noise.noise(Vector((p.x * 0.4, p.y * 0.4, seed)))) * 4.0 * scale_d
            ring.append(rock.verts.new(p))
        verts.append(ring)
    for a, b in zip(verts, verts[1:]):
        for i in range(n_edge):
            j = (i + 1) % n_edge
            rock.faces.new([a[i], b[i], b[j], a[j]])
    tip = rock.verts.new((cx, cy, z_top - depth * 1.12))
    for i in range(n_edge):
        rock.faces.new([verts[-1][i], tip, verts[-1][(i + 1) % n_edge]])
    # top cap (fan via two inner rings)
    inner = []
    for s in (0.66, 0.33):
        inner.append([rock.verts.new((cx + rad(2 * math.pi * i / n_edge) * s * math.cos(2 * math.pi * i / n_edge),
                                      cy + rad(2 * math.pi * i / n_edge) * s * math.sin(2 * math.pi * i / n_edge),
                                      z_top - 0.07)) for i in range(0, n_edge, 4)])
    outer = verts[0]
    m = len(inner[0])
    for i in range(m):
        j = (i + 1) % m
        rock.faces.new([outer[4 * i], outer[(4 * i + 1) % n_edge], outer[(4 * i + 2) % n_edge],
                        outer[(4 * i + 3) % n_edge], outer[(4 * j) % n_edge], inner[0][j], inner[0][i]][::-1])
        rock.faces.new([inner[0][i], inner[0][j], inner[1][j], inner[1][i]][::-1])
    cen = rock.verts.new((cx, cy, z_top - 0.07))
    for i in range(m):
        rock.faces.new([inner[1][i], inner[1][(i + 1) % m], cen][::-1])
    bmesh.ops.recalc_face_normals(rock, faces=rock.faces)
    C.set_mat(rock, DARK)
    # hanging spikes
    for s in range(spikes):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.1, 0.6)
        px = cx + rad(a) * rr * math.cos(a)
        py = cy + rad(a) * rr * math.sin(a)
        L = rng.uniform(0.35, 0.8) * depth
        r0 = rng.uniform(0.12, 0.22) * max(rx, ry)
        top = z_top - depth * (0.25 + 0.6 * rr)
        prof = [(r0 * (1 - t) ** 1.4 + 0.05, top - L * t) for t in [i / 6 for i in range(7)]]
        prof = [(0.0, top + 1.0)] + [(r, z) for r, z in prof] + [(0.0, top - L - 0.4)]
        sp = C.lathe(prof, seg=9, cap_bottom=False, cap_top=False, phase=rng.uniform(0, 1))
        for v in sp.verts:
            v.co += Vector(noise.noise_vector(v.co * 0.45 + Vector((seed, s, 0)))) * r0 * 0.35
        C.merge(rock, sp, mat=DARK, matrix=Matrix.Translation((px, py, 0)))
    world_moss(rock, Matrix.Identity(4), thresh=0.55, scale=0.35, cut=0.05, only=(DARK,))
    return floor, rock, inside


def _tile(bm, rng, x0, x1, y0, y1, z, flat, edge_d):
    g = 0.035
    x0 += g / 2 + rng.uniform(0, 0.02)
    x1 -= g / 2 + rng.uniform(0, 0.02)
    y0 += g / 2 + rng.uniform(0, 0.02)
    y1 -= g / 2 + rng.uniform(0, 0.02)
    pts = []
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    for i, (px, py) in enumerate(corners):
        nx, ny = corners[(i + 1) % 4]
        if rng.random() < 0.3:
            c = rng.uniform(0.03, 0.09)
            px_prev, py_prev = corners[i - 1]
            dprev = Vector((px_prev - px, py_prev - py)).normalized()
            dnext = Vector((nx - px, ny - py)).normalized()
            pts.append((px + dprev.x * c, py + dprev.y * c))
            pts.append((px + dnext.x * c, py + dnext.y * c))
        else:
            pts.append((px + rng.uniform(-0.012, 0.012), py + rng.uniform(-0.012, 0.012)))
        if rng.random() < 0.35:  # a dent mid-edge
            t = rng.uniform(0.3, 0.7)
            mxp, myp = px + (nx - px) * t, py + (ny - py) * t
            inward = Vector((-(ny - py), nx - px)).normalized()
            dd = rng.uniform(0.01, 0.03)
            pts.append((mxp + inward.x * dd, myp + inward.y * dd))
    th = 0.12
    t = C.prism(pts, -th, 0.0, bevel=0.018, seg=1, bevel_top_only=True)
    bottom = [f for f in t.faces if f.normal.z < -0.9]
    bmesh.ops.delete(t, geom=bottom, context='FACES_ONLY')
    if flat:  # level and never above the floor plane (altar and candelabras stand at exactly z)
        dz, rx_, ry_ = rng.uniform(-0.006, 0.0), 0.0, 0.0
    else:
        k = 1.0 + 2.5 * max(0.0, 1.6 - edge_d)
        dz = rng.uniform(-0.03, 0.02) * k
        rx_, ry_ = rng.uniform(-0.02, 0.02) * k, rng.uniform(-0.02, 0.02) * k
    cxm, cym = (x0 + x1) / 2, (y0 + y1) / 2
    m = Matrix.Translation((cxm, cym, z + dz)) @ Matrix.Rotation(rx_, 4, 'X') @ Matrix.Rotation(ry_, 4, 'Y') \
        @ Matrix.Translation((-cxm, -cym, 0))
    C.merge(bm, t, mat=TILES, matrix=m)
    t.free()


def _border_ring(bm, rng, inner, outer, z, flat):
    """Square processional ring of large slabs round the altar."""
    w = outer - inner
    for k in range(4):
        x = -outer
        while x < outer - w - 1e-3:
            L = rng.uniform(1.0, 1.5)
            if outer - w - (x + L) < 0.6:
                L = outer - w - x
            x0, x1 = x, x + L
            pts_y0, pts_y1 = -outer, -inner
            tb = bmesh.new()
            _tile(tb, rng, x0, x1, pts_y0, pts_y1, z, True, 9.0)
            C.merge(bm, tb, matrix=Matrix.Rotation(k * math.pi / 2, 4, 'Z'))
            x = x1


# ----------------------------------------------------------------------------------------------- far backdrop

def far_tower(rng, h, w, spire=True, broken=False):
    bm = bmesh.new()
    C.merge(bm, C.box(w, w, h, center=(0, 0, h / 2)), mat=STONE)
    # corner buttresses
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        C.merge(bm, C.box(w * 0.22, w * 0.22, h * 0.85, center=(sx * w * 0.5, sy * w * 0.5, h * 0.425)), mat=STONE)
        C.merge(bm, C.lathe([(0.0, 0), (w * 0.12, 0), (0.0, w * 0.9)], seg=4, phase=math.pi / 4), mat=STONE,
                matrix=Matrix.Translation((sx * w * 0.5, sy * w * 0.5, h * 0.85)))
    # belfry slits (dark insets)
    for k in range(4):
        slit = C.box(w * 0.18, 0.1, h * 0.18, center=(0, -w / 2 - 0.02, h * 0.78))
        C.merge(bm, slit, mat=DARK, matrix=Matrix.Rotation(k * math.pi / 2, 4, 'Z'))
    if spire and not broken:
        C.merge(bm, C.lathe([(0.0, h), (w * 0.62, h), (0.0, h + w * rng.uniform(2.2, 3.6))], seg=8, phase=math.pi / 8),
                mat=STONE)
    elif broken:
        top = C.box(w * 1.02, w * 1.02, w * 0.6, center=(0, 0, h + w * 0.3))
        for v in top.verts:
            if v.co.z > h + 0.01:
                v.co.z -= rng.uniform(0, w * 0.6)
        C.merge(bm, top, mat=STONE)
    return bm


def far_cathedral(rng, L, h):
    bm = bmesh.new()
    # nave walls with buttresses and a broken roof line
    for sy in (-1, 1):
        C.merge(bm, C.box(L, 0.8, h, center=(0, sy * 3.0, h / 2)), mat=STONE)
        for i in range(5):
            x = -L / 2 + L * (i + 0.5) / 5
            C.merge(bm, C.box(0.9, 1.8, h * 0.8, center=(x, sy * 4.1, h * 0.4)), mat=STONE)
            C.merge(bm, C.box(1.3, 0.2, h * 0.45, center=(x + L / 10, sy * 3.0 + sy * -0.45, h * 0.6)), mat=DARK)
    twin = far_tower(rng, h * 1.9, 3.6, spire=True)
    C.merge(bm, twin, matrix=Matrix.Translation((-L / 2 - 1.2, -3.0, 0)))
    twin2 = far_tower(rng, h * 1.75, 3.6, spire=False, broken=True)
    C.merge(bm, twin2, matrix=Matrix.Translation((-L / 2 - 1.2, 3.0, 0)))
    return bm
