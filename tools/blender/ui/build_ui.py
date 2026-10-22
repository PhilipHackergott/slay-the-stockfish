"""Build and render the UI texture kit: one Blender scene per element group, one raw 2x RGBA render per state.

Blender --background --factory-startup --python-exit-code 1 --python build_ui.py -- [group ...] [--samples N]
Raw renders: build/ui/raw/<file>.png (post.py turns them into assets/ui/kit/). Contract: spec.py.
"""
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mathutils import Vector  # noqa: E402

import kit as K  # noqa: E402
import spec  # noqa: E402

SOUL, EMBER = K.SOUL, K.EMBER
GROUPS = {}


def group(name, size):
    def deco(fn):
        GROUPS[name] = (size, fn)
        return fn
    return deco


def corner_rot(sx, sy):
    """Rotation (deg) that maps the top-left corner frame (outward = (-1, +1)) onto corner (sx, sy)."""
    return {(-1, 1): 0, (1, 1): -90, (1, -1): 180, (-1, -1): 90}[(sx, sy)]


def place(bm, deg, x, y, z=0.0):
    return K.xform(bm, K.T(x, y, z) @ K.Rz(deg))


CORNERS = ((-1, 1), (1, 1), (1, -1), (-1, -1))


# ----------------------------------------------------------------------------------------------- shared parts

def prof_band(w, h=7.0, bead_h=6.8):
    """Forged frame moulding: hammered flat band outside, rounded bead inside (u > 0 = outward)."""
    if w < 16:
        return prof_thin(w, h)
    a = w / 2
    pts = [(a, 0.0), (a, h * 0.55), (a - 2.0, h), (a - 2.5, h)]
    band_in = -a + w * 0.42
    pts += [(band_in + 1.5, h), (band_in, h - 1.8), (band_in - 1.2, h - 2.6)]
    b0, b1 = band_in - 1.6, -a + 2.6
    pts += K.bead(b0, b1, h - 2.6, bead_h, 8)
    pts += [(-a + 1.4, h * 0.45), (-a, h * 0.25), (-a, 0.0)]
    return pts


def prof_heavy(w, h=11.0):
    """Modal frame: heavy half-round outer bar, dark channel with a thin spine, stepped inner rim."""
    a = w / 2
    pts = [(a, 0.0), (a, h * 0.5), (a - 1.2, h * 0.72)]
    pts += K.bead(a - 2.0, a - 23.0, h * 0.72, h * 1.5, 14)
    pts += [(a - 24.0, h * 0.42), (a - 25.5, h * 0.36)]
    pts += K.bead(a - 33.0, a - 37.5, h * 0.36, h * 0.66, 6)
    pts += [(a - 44.5, h * 0.36), (a - 46.0, h * 0.42), (a - 47.5, h * 0.8), (a - 60.0, h * 0.84),
            (a - 61.5, h * 0.68), (a - 64.5, h * 0.62), (a - 66.5, h * 0.4), (-a + 1.2, h * 0.24), (-a, 0.0)]
    return pts


def prof_thin(w, h=4.5):
    a = w / 2
    return [(a, 0.0), (a, h * 0.5), (a - 1.2, h * 0.9)] + K.bead(a - 1.6, -a + 1.6, h * 0.9, h * 1.15, 6) + \
        [(-a + 1.2, h * 0.9), (-a, h * 0.5), (-a, 0.0)]


def diamond(r):
    return [(0, r), (-r, 0), (0, -r), (r, 0)]


def boss(x, y, r, z, mi=0, rise=4.0):
    return K.plate([(x + px, y + py) for px, py in diamond(r)], z, z + 1.5,
                   [(r * 0.14, rise * 0.55, mi), (r * 0.12, 0.0, mi), (r * 0.12, rise * 0.45, mi), (r * 0.1, 0, mi)])


def corner_cap(cx, cy, deg, mat, gem_mat, z=6.5, r=26.0, outer=37.0, inner=44.0, diag_in=34.0, rivets=(),
               gem_r=6.5):
    """Gothic corner star (top-left frame, rotated by deg): eight ridged blades from a small boss, gem on top."""
    bm = K.bmesh.new()
    K.merge(bm, boss(0, 0, r * 0.55, z + 1.0, rise=3.0))
    sp = [((0, 0), (-outer * 0.98, outer * 0.98), 0.5 * r, 8.0), ((0, 0), (diag_in, -diag_in), 0.42 * r, 7.0),
          ((0, 0), (0, outer), 0.34 * r, 6.5), ((0, 0), (-outer, 0), 0.34 * r, 6.5),
          ((0, 0), (inner, 0), 0.3 * r, 6.0), ((0, 0), (0, -inner), 0.3 * r, 6.0)]
    for (bx, by), (tx, ty), w, h in sp:
        K.merge(bm, K.blade((bx, by), (tx, ty), w, h, z, w_pow=1.1, h_tip=0.15))
    for rx, ry in rivets:
        K.merge(bm, K.rivet(rx, ry, 4.4, z + 0.2))
    place(bm, deg, cx, cy)
    K.obj(bm, "cap", [mat])
    g = K.gem(0, 0, gem_r, z + 5.2)
    place(g, deg, cx, cy)
    K.obj(g, "gem", [gem_mat], smooth=False)


def iron_set(seed=0.0, tone=1.0, wear=1.0, dent=15.0):
    return (K.mat_iron("iron_h", aniso=(0.12, 1.0, 1.0), seed=seed, tone=tone, wear=wear, dent=dent),
            K.mat_iron("iron_v", aniso=(1.0, 0.12, 1.0), seed=seed + 1, tone=tone, wear=wear, dent=dent),
            K.mat_iron("iron", seed=seed + 2, tone=tone, wear=wear, dent=dent))


def fill_plate(hw, hh, mat, z1=1.0, chamfer=0.0):
    """Single top face: a closed prism would stack two 0.93-alpha layers."""
    bm = K.bmesh.new()
    bm.faces.new([bm.verts.new((p[0], p[1], z1)) for p in K.rect_path(hw, hh, 0, chamfer)])
    K.obj(bm, "fill", [mat], shadow=False)


def filigree(deg, cx, cy, mat, reach=56.0, z=1.0, r=1.6, thorns=3, curl=11.0):
    """Thin forged thorn-vine curls in the inner corner of a frame (top-left frame; rotated by deg)."""
    bm = K.bmesh.new()
    for flip in (False, True):
        pts = []
        n = 26
        for i in range(n + 1):
            t = i / n
            x = 4 + reach * t
            y = -4 - curl * math.sin(math.pi * min(1.0, t * 1.15)) * (1 - t) ** 0.5 - 2.0 * t
            pts.append((x, y))
        ex, ey = pts[-1]
        for k in range(1, 10):
            a = math.pi / 2 - k * 0.6
            rr = 5.5 * (1 - k / 13)
            pts.append((ex + rr * math.cos(a), ey - 5.5 + rr * math.sin(a)))
        if flip:
            pts = [(-y, -x) for x, y in pts]
        path = [(x, y, z + r) for x, y in pts]
        radii = [r * (1.0 - 0.55 * i / len(path)) for i in range(len(path))]
        K.merge(bm, K.tube(path, radii, 0.8, 8))
        for k in range(thorns):
            i = int((k + 0.6) * n / (thorns + 0.4))
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            dx, dy = x1 - x0, y1 - y0
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln, dx / ln
            sg = 1 if k % 2 else -1
            K.merge(bm, K.blade((x0, y0), (x0 + sg * nx * 7 + dx / ln * 4, y0 + sg * ny * 7 + dy / ln * 4),
                                1.8, 1.6, z + 0.5))
    place(bm, deg, cx, cy)
    K.obj(bm, "filigree", [mat])


def bone(a, b, rs, rb, z, zscale=0.8, seg=18):
    """Bone bar from a to b: exact uniform shaft, flared ends with two condyle lobes (stretch-safe middle)."""
    a, b = Vector((a[0], a[1], z)), Vector((b[0], b[1], z))
    L = (b - a).length
    d = (b - a).normalized()
    side = Vector((-d.y, d.x, 0))
    end = [(0.0, 0.3), (1.0, rb * 0.45), (2.6, rb * 0.62), (5.0, rb * 0.7), (8.5, rb * 0.66), (12.5, rs * 1.12),
           (17.0, rs * 1.03), (22.0, rs)]
    prof = end + [(L - s, r) for s, r in reversed(end)]
    path = [a + d * s for s, _ in prof]
    bm = K.tube(path, [r for _, r in prof], zscale, seg)
    for p, dd in ((a, d), (b, -d)):
        for sgn in (-1, 1):
            c = p + dd * (rb * 0.42) + side * (sgn * rb * 0.5)
            K.merge(bm, K.sphere(c, rb * 0.66, 1.0, 1.0, zscale, 18, 9))
    return bm


# ----------------------------------------------------------------------------------------------- panel

@group("panel", (512, 512))
def g_panel():
    W = H = 512
    K.scene(W, H)
    ih, iv, ic = iron_set()
    c = W / 2 - 40
    K.obj(K.frame(c, c, prof_band(40)), "frame", [ih, iv])
    mk = K.Mask(-c, -c, 2 * c, 2 * c)
    g = W / 2 - 72
    mk.stroke([(p[0], p[1]) for p in K.rect_path(g, g, 0, 10)], 2.4, 0, closed=True, k=0.55)
    fill_plate(c, c, K.mat_slate("slate", mask=mk, rim=(c, c, 56.0)))
    gem = K.mat_gem("gem", SOUL)
    for sx, sy in CORNERS:
        corner_cap(sx * c, sy * c, corner_rot(sx, sy), ic, gem, rivets=((52, 0), (0, -52)))
        filigree(corner_rot(sx, sy), sx * (c - 20), sy * (c - 20), ic, reach=30.0, curl=8.0)
    K.catcher(W, H, rect=(c - 4, c - 4))
    return {"panel": {}}


# ----------------------------------------------------------------------------------------------- buttons

def button(primary):
    W, H = 384, 96
    K.scene(W, H)
    rim = K.mat_iron("rim", aniso=(0.15, 1.0, 1.0), seed=4.0)
    groove = K.mat_groove("groove", aniso=(0.2, 1.0, 1.0))
    face = K.mat_enamel("enamel") if primary else K.mat_iron("face", aniso=(0.18, 1.0, 1.0), seed=9.0, tone=0.8,
                                                             wear=0.35, dent=22.0)
    tip, sh, hh = 184.0, 150.0, 38.0
    out = [(-tip, 0), (-sh, -hh), (sh, -hh), (tip, 0), (sh, hh), (-sh, hh)]
    steps = [(2.5, 2.5, 0), (5.5, 0.0, 0), (1.6, -2.6, 0), (3.6, 0.0, 2), (1.1, -1.7, 1), (1.1, 1.7, 1)]
    K.obj(K.plate(out, 0.0, 4.0, steps, face_mi=2), "plate", [rim, groove, face])
    rv = K.bmesh.new()
    for sx in (-1, 1):
        K.merge(rv, K.rivet(sx * 145.0, 0.0, 6.0, 3.9))
    K.obj(rv, "rivets", [K.mat_iron("rivet", seed=2.0)])
    K.catcher(W, H)


def button_states(pre, primary):
    if primary:
        return {pre + "_normal": {"glow": 0.22, "glow_col": EMBER},
                pre + "_hover": {"glow": 1.0, "glow_col": EMBER, "face_glow": 0.006},
                pre + "_pressed": {"glow": 1.0, "glow_col": EMBER, "dark": 0.4},
                pre + "_disabled": {"rust": 1.0, "dark": 0.2}}
    return {pre + "_normal": {},
            pre + "_hover": {"glow": 1.0, "glow_col": SOUL},
            pre + "_pressed": {"glow": 1.0, "glow_col": EMBER, "dark": 0.45},
            pre + "_disabled": {"rust": 1.0}}


@group("button", (384, 96))
def g_button():
    button(False)
    return button_states("button", False)


@group("button_primary", (384, 96))
def g_button_primary():
    button(True)
    return button_states("button_primary", True)


# ----------------------------------------------------------------------------------------------- card

@group("card", (384, 544))
def g_card():
    W, H = 384, 544
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=5.0)
    bh = K.mat_bone("bone_h", aniso=(0.4, 1.0, 1.0))
    bv = K.mat_bone("bone_v", aniso=(1.0, 0.4, 1.0), seed=3.0)
    bk = K.mat_bone("bone_k", seed=7.0)
    bc = 23.0
    hw, hh = W / 2 - bc, H / 2 - bc
    # slate fill with the engraved line (R channel glows)
    mk = K.Mask(-W / 2, -H / 2, W, H)
    gl = 52.0
    mk.stroke([(p[0], p[1]) for p in K.rect_path(W / 2 - gl, H / 2 - gl, 0, 16)], 3.4, 0, closed=True)
    fill_plate(W / 2 - 26, H / 2 - 26, K.mat_slate("slate", mask=mk, rim=(W / 2 - 26, H / 2 - 26, 44.0)), chamfer=10)
    # thin iron rim inside the bones
    K.obj(K.frame(W / 2 - 39, H / 2 - 39, prof_thin(8.0, 4.0), chamfer=14), "rim", [ih, iv])
    # bones: shafts uniform, knobbed ends crossing past the corners
    ext = 15.0
    shafts = K.bmesh.new()
    for sy in (-1, 1):
        K.merge(shafts, bone((-hw - ext, sy * hh), (hw + ext, sy * hh), 8.5, 15.0, 11.5, zscale=1.0), 0)
    for sx in (-1, 1):
        K.merge(shafts, bone((sx * hw, -hh - ext), (sx * hw, hh + ext), 8.5, 15.0, 9.0, zscale=1.0), 1)
    K.obj(shafts, "bones", [bh, bv])
    # spiked iron corner pieces inside the crossings
    gem = K.mat_gem("gem", SOUL, 1.6)
    for sx, sy in CORNERS:
        deg = corner_rot(sx, sy)
        bm = K.bmesh.new()
        K.merge(bm, boss(0, 0, 11.0, 5.0, rise=3.0))
        K.merge(bm, K.blade((-5, 5), (-13, 13), 5.0, 3.0, 6.0))
        K.merge(bm, K.blade((5, -5), (19, -19), 5.0, 3.5, 6.0))
        K.merge(bm, K.blade((5, 0), (17, 0), 3.6, 2.6, 6.0))
        K.merge(bm, K.blade((0, -5), (0, -17), 3.6, 2.6, 6.0))
        px, py = sx * (hw - 19), sy * (hh - 19)
        place(bm, deg, px, py)
        K.obj(bm, "corner", [ic])
        g = K.gem(0, 0, 3.8, 9.2)
        place(g, deg, px, py)
        K.obj(g, "gem", [gem], smooth=False)
    K.catcher(W, H, rect=(W / 2 - 30, H / 2 - 30))
    return {"card": {}, "card_hover": {"glow": 1.0, "glow_col": SOUL},
            "card_pressed": {"glow": 1.0, "glow_col": EMBER, "dark": 0.2}, "card_disabled": {}}


# ----------------------------------------------------------------------------------------------- skull

def skull(cx, cy, z0, width, zscale=0.6, horns=True, teeth=True):
    """Horned skull facing the camera, upright, cranium `width` px wide. Returns (bone, horn, sockets) bmeshes."""
    E = [dict(type='ELLIPSOID', co=(0, 3.0, 0), r=18.5, size=(1.0, 1.04, 0.8)),
         dict(type='CAPSULE', co=(0, -1.8, 5.2), r=4.6, size=(5.0, 1, 1)),
         dict(type='ELLIPSOID', co=(0, -6.8, 2.4), r=10.0, size=(0.62, 0.55, 0.6)),
         dict(type='ELLIPSOID', co=(0, -11.6, 1.0), r=9.0, size=(0.62, 0.3, 0.45))]
    for s in (-1, 1):
        E.append(dict(type='BALL', co=(s * 7.0, -5.6, 2.8), r=5.6))
    bone_bm = K.metaball(E, res=0.3)
    cav = [(-4.2, -3.8, 3.8, 3.0, 8.0, -0.3), (4.2, -3.8, 3.8, 3.0, 8.0, 0.3), (0.0, -7.9, 1.5, 2.1, 5.5, 0.0),
           (0.0, -10.0, 4.3, 0.75, 3.0, 0.0), (-5.6, -8.4, 1.8, 1.2, 1.6, 0.4), (5.6, -8.4, 1.8, 1.2, 1.6, -0.4)]
    bone_bm.normal_update()
    bottoms = {}
    for v in bone_bm.verts:
        if v.normal.z <= 0.05:
            continue
        d = 0.0
        for i, (ex, ey, rx, ry, D, rot) in enumerate(cav):
            lx, ly = v.co.x - ex, v.co.y - ey
            lx, ly = lx * math.cos(rot) + ly * math.sin(rot), -lx * math.sin(rot) + ly * math.cos(rot)
            q = (lx / rx) ** 2 + (ly / ry) ** 2
            if q < 1.0:
                t = 1.0 - q
                d = max(d, D * t * t * (3 - 2 * t))
                if q < 0.05:
                    bottoms[i] = min(bottoms.get(i, 1e9), v.co.z - D)
        v.co.z -= d * min(1.0, v.normal.z * 1.4)
    if teeth:
        for i in range(6):
            x = -3.0 + i * 1.2
            K.merge(bone_bm, K.sphere((x, -10.0, 3.6 - abs(x) * 0.3), 0.62, 0.86, 1.6, 1.0, 10, 6))
    xs = [v.co.x for v in bone_bm.verts]
    ys = [v.co.y for v in bone_bm.verts]
    zs = [v.co.z for v in bone_bm.verts]
    k = width / (max(xs) - min(xs))
    mx, my, mz = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs)

    def tf(bm):
        for v in bm.verts:
            v.co = Vector(((v.co.x - mx) * k + cx, (v.co.y - my) * k + cy, (v.co.z - mz) * k * zscale + z0))
        return bm

    horn_bm = None
    if horns:
        horn_bm = K.bmesh.new()
        for s in (-1, 1):
            ctrl = [(s * 6.6, 6.8, 4.0), (s * 10.6, 8.4, 4.0), (s * 13.8, 11.2, 3.4), (s * 14.6, 15.0, 2.6),
                    (s * 12.8, 18.0, 2.0)]
            path = K.catmull(ctrl, 7)
            n = len(path)
            radii = [2.7 * (1 - i / (n - 1)) ** 0.8 + 0.12 for i in range(n)]
            K.merge(horn_bm, K.tube(path, radii, 1.0, 12))
        tf(horn_bm)
    sockets = K.bmesh.new()
    for i in (0, 1):
        ex, ey = cav[i][:2]
        K.merge(sockets, K.sphere((ex, ey, bottoms.get(i, 0.0) + 0.6), 1.9, 1.0, 0.9, 0.6, 14, 7))
    return tf(bone_bm), horn_bm, tf(sockets)


def put_skull(cx, cy, z0, width, mats, zscale=0.6, horns=True, teeth=True, name="skull"):
    """mats = (bone, horn, socket)."""
    b, h, s = skull(cx, cy, z0, width, zscale, horns, teeth)
    K.obj(b, name, [mats[0]], sharp=89.0)
    if h is not None:
        K.obj(h, name + "_horns", [mats[1]], sharp=89.0)
    K.obj(s, name + "_eyes", [mats[2]], sharp=89.0)


@group("test_skull", (256, 256))
def g_test_skull():
    K.scene(256, 256)
    put_skull(0, -10, 0.0, 150.0, (K.mat_bone("b", ao=10.0), K.mat_horn("h"), K.mat_groove("e")), zscale=0.6)
    K.catcher(256, 256)
    return {"test_skull": {}}


# ----------------------------------------------------------------------------------------------- modal

@group("modal", (1024, 1024))
def g_modal():
    W = H = 1024
    K.scene(W, H, samples=128)
    ih, iv, ic = iron_set(seed=11.0, tone=0.8, dent=18.0)
    c = W / 2 - 47
    K.obj(K.frame(c, c, prof_heavy(70)), "frame", [ih, iv])
    inner = c - 35
    mk = K.Mask(-inner - 4, -inner - 4, 2 * inner + 8, 2 * inner + 8)
    gl = inner - 18
    mk.stroke([(p[0], p[1]) for p in K.rect_path(gl, gl, 0, 22)], 2.6, 0, closed=True, k=0.7)
    rng = __import__("random").Random(7)
    for sx, sy in CORNERS:
        for i in range(2):  # runes stay inside the unscaled corner blocks
            d = 20 + i * 22
            mk.rune(rng.randrange(40), sx * (gl - d - 18), sy * (gl - 12), 17, 2.0, k=0.8)
            mk.rune(rng.randrange(40), sx * (gl - 12), sy * (gl - d - 18), 17, 2.0, k=0.8)
    fill_plate(inner + 4, inner + 4, K.mat_slate("slate", tone=0.8, mask=mk, alpha=0.94, rim=(inner + 4, inner + 4, 110.0)))
    bone = K.mat_bone("skull_bone", ao=8.0, tone=0.8)
    horn = K.mat_horn("horn")
    eyes = K.mat_groove("eyes")
    gem = K.mat_gem("gem", SOUL, 1.5)
    for sx, sy in CORNERS:
        deg = corner_rot(sx, sy)
        bm = K.bmesh.new()
        # L-shaped bracket over the mitre: long points along both bars, short ones outwards
        kite = [(84, 0), (26, 10), (10, 26), (0, 40), (-40, 0), (-10, -26), (0, -84), (10, -10)]
        K.merge(bm, K.plate(kite, 12.0, 20.0, [(2.0, 2.5, 0), (3.5, 0.0, 0), (1.4, -1.8, 0)]))
        K.merge(bm, boss(0, 0, 30.0, 22.0, rise=4.0))
        for (tx, ty), w, h in (((-40, 40), 16.0, 9.0), ((0, 46), 9.0, 7.0), ((-46, 0), 9.0, 7.0)):
            K.merge(bm, K.blade((0, 0), (tx, ty), w, h, 21.0, w_pow=1.1, h_tip=0.15))
        # thorn vines lying on both bars
        for flip in (False, True):
            pts = [(52 + 7 * i, 2.5 * math.sin(i * 1.3)) for i in range(10)]
            if flip:
                pts = [(-y, -x) for x, y in pts]
            path = [(x, y, 19.0) for x, y, _ in K.catmull(pts, 3)]
            K.merge(bm, K.tube(path, [4.2 - 3.0 * i / len(path) for i in range(len(path))], 0.8, 10))
            for j in range(5):
                x0 = 58 + j * 12.0
                sg = 1 if j % 2 else -1
                base, tip = (x0, 0.0), (x0 + 7, sg * (15.0 - j * 1.2))
                if flip:
                    base, tip = (-base[1], -base[0]), (-tip[1], -tip[0])
                K.merge(bm, K.blade(base, tip, 4.2, 4.0, 18.5, bend=sg * 2.5))
        for rx, ry in ((106, 20), (106, -20), (20, -106), (-20, -106)):
            K.merge(bm, K.rivet(rx, ry, 5.0, 11.0))
        place(bm, deg, sx * c, sy * c)
        K.obj(bm, "corner", [ic])
        filigree(deg, sx * inner, sy * inner, ic, reach=44.0, curl=10.0, r=1.9)
        put_skull(sx * (c - 16), sy * (c - 16) + 6, 26.0, 84.0, (bone, horn, eyes), zscale=0.5)
    K.catcher(W, H, rect=(inner, inner))
    return {"modal": {}}


@group("modal_crest", (384, 160))
def g_crest():
    W, H = 384, 160
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=13.0)
    bm = K.bmesh.new()
    for s in (-1, 1):
        lb = K.lance(34, 188, 0, 6.5, 6.0, 3.0, tip=46)
        if s < 0:
            K.xform(lb, K.S(-1, 1, 1))
        K.merge(bm, lb)
        for j, x in enumerate((62, 96, 128, 156)):
            for sy in (-1, 1):
                ln = 15 - j * 2.5
                K.merge(bm, K.blade((s * x, sy * 3), (s * (x + 9), sy * (3 + ln)), 3.4, 3.4, 4.0, bend=-s * sy * 2))
    # thorned crown ring
    K.merge(bm, K.xform(K.ring(36.0, prof_thin(9.0, 6.0), seg=96), K.T(0, 12, 0)), 0)
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        K.merge(bm, K.blade((40 * math.cos(a), 12 + 40 * math.sin(a)),
                            (53 * math.cos(a + 0.12), 12 + 53 * math.sin(a + 0.12)), 3.4, 4.0, 3.0))
    # cross through the crown
    for (tx, ty), w in (((0, 76), 8.0), ((0, -74), 8.0), ((-44, 12), 6.5), ((44, 12), 6.5)):
        K.merge(bm, K.blade((0, ty * 0.06 if tx == 0 else 12), (tx, ty), w, 9.0, 8.0, w_pow=0.55, h_tip=0.3))
    K.merge(bm, boss(0, 12, 16.0, 9.0, rise=4.0))
    K.obj(bm, "crest", [ic])
    g = K.gem(0, 12, 7.0, 17.0)
    K.obj(g, "gem", [K.mat_gem("gem", SOUL, 1.6)], smooth=False)
    K.catcher(W, H)
    return {"modal_crest": {}}


@group("title_plaque", (768, 128))
def g_plaque():
    W, H = 768, 128
    K.scene(W, H)
    rim = K.mat_iron("rim", aniso=(0.12, 1.0, 1.0), seed=15.0)
    groove = K.mat_groove("groove", aniso=(0.2, 1.0, 1.0))
    face = K.mat_iron("face", aniso=(0.1, 1.0, 1.0), seed=16.0, tone=0.7, wear=0.3, dent=24.0)
    ic = K.mat_iron("iron", seed=17.0)
    tip, sh, hh = 350.0, 316.0, 38.0
    out = [(-tip, 0), (-sh, -hh), (sh, -hh), (tip, 0), (sh, hh), (-sh, hh)]
    steps = [(3.0, 3.0, 0), (6.5, 0.0, 0), (2.0, -3.0, 0), (4.5, 0.0, 2), (1.3, -1.8, 1), (1.3, 1.8, 1)]
    K.obj(K.plate(out, 0.0, 4.0, steps, face_mi=2), "plate", [rim, groove, face])
    bm = K.bmesh.new()
    for s in (-1, 1):
        x = s * 336
        K.merge(bm, boss(x, 0, 20.0, 6.0, rise=4.0))
        for (tx, ty), w, h in (((s * 382, 0), 9.0, 7.0), ((x, 61), 7.5, 6.5), ((x, -61), 7.5, 6.5),
                               ((x + s * 28, 30), 4.5, 4.5), ((x + s * 28, -30), 4.5, 4.5),
                               ((x - s * 30, 50), 4.0, 4.0), ((x - s * 30, -50), 4.0, 4.0)):
            K.merge(bm, K.blade((x, 0), (tx, ty), w, h, 6.0, w_pow=1.1, h_tip=0.15))
        K.merge(bm, K.rivet(s * 296, 0, 5.5, 5.0))
    K.obj(bm, "ends", [ic])
    gem = K.mat_gem("gem", SOUL, 1.5)
    for s in (-1, 1):
        K.obj(K.gem(s * 336, 0, 6.5, 10.5), "gem", [gem], smooth=False)
    K.catcher(W, H)
    return {"title_plaque": {}}


@group("tooltip", (256, 256))
def g_tooltip():
    W = H = 256
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=19.0, dent=10.0)
    c = W / 2 - 13
    K.obj(K.frame(c, c, prof_band(13.0, 4.0, 4.2)), "frame", [ih, iv])
    fill_plate(c, c, K.mat_slate("slate", tone=0.55, alpha=0.95, cracks=0.4, rim=(c, c, 22.0)))
    rv = K.bmesh.new()
    for sx, sy in CORNERS:
        K.merge(rv, K.rivet(sx * c, sy * c, 5.0, 3.5))
    K.obj(rv, "rivets", [ic])
    K.catcher(W, H, rect=(c - 3, c - 3))
    return {"tooltip": {}}


# ----------------------------------------------------------------------------------------------- dividers

def sigil(cx, cy, R, z, thorns=8):
    bm = K.bmesh.new()
    K.merge(bm, K.xform(K.ring(R, prof_thin(R * 0.3, 5.0), seg=72), K.T(cx, cy, z)))
    for i in range(thorns):
        a = 2 * math.pi * (i + 0.5) / thorns
        K.merge(bm, K.blade((cx + (R + 1) * math.cos(a), cy + (R + 1) * math.sin(a)),
                            (cx + (R + 11) * math.cos(a + 0.15), cy + (R + 11) * math.sin(a + 0.15)), 3.0, 3.5, z))
    for (tx, ty), w in (((0, R * 1.45), 5.0), ((0, -R * 1.45), 5.0), ((-R * 0.95, 0), 4.0), ((R * 0.95, 0), 4.0)):
        K.merge(bm, K.blade((cx, cy), (cx + tx, cy + ty), w, 7.0, z + 2, w_pow=0.6, h_tip=0.3))
    return bm


@group("divider", (1024, 64))
def g_divider():
    W, H = 1024, 64
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=21.0)
    bm = K.bmesh.new()
    for s in (-1, 1):
        lb = K.lance(30, 506, 0, 4.2, 5.0, 2.0, tip=44)
        if s < 0:
            K.xform(lb, K.S(-1, 1, 1))
        K.merge(bm, lb, 0)
        for x, ln in ((52, 15), (80, 12), (420, 10)):
            for sy in (-1, 1):
                K.merge(bm, K.blade((s * x, sy * 2), (s * (x + 12), sy * (2 + ln)), 3.0, 3.2, 3.0, bend=-s * sy * 2.5),
                        2)
        K.merge(bm, K.rivet(s * 230, 0, 3.6, 5.0), 2)
    K.merge(bm, sigil(0, 0, 18.0, 3.0), 2)
    K.obj(bm, "divider", [ih, iv, ic])
    K.obj(K.gem(0, 0, 5.2, 9.0), "gem", [K.mat_gem("gem", SOUL, 1.5)], smooth=False)
    K.catcher(W, H)
    return {"divider": {}}


@group("divider_small", (512, 40))
def g_divider_small():
    W, H = 512, 40
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=23.0)
    bm = K.bmesh.new()
    for s in (-1, 1):
        lb = K.lance(14, 252, 0, 3.2, 4.0, 2.0, tip=30)
        if s < 0:
            K.xform(lb, K.S(-1, 1, 1))
        K.merge(bm, lb, 0)
    K.merge(bm, boss(0, 0, 14.0, 3.0, rise=3.5), 1)
    for (tx, ty) in ((0, 18), (0, -18)):
        K.merge(bm, K.blade((0, 0), (tx, ty), 4.0, 6.0, 4.0, w_pow=1.0), 1)
    K.obj(bm, "divider", [ih, ic])
    K.obj(K.gem(0, 0, 4.2, 8.5), "gem", [K.mat_gem("gem", SOUL, 1.5)], smooth=False)
    K.catcher(W, H)
    return {"divider_small": {}}


# ----------------------------------------------------------------------------------------------- rings

def ring_profile(w, h, groove=True):
    """Round frame moulding with an optional engraved channel in the middle: (points, per-segment materials)."""
    a = w / 2
    pts = [(a, 0.0), (a, h * 0.45), (a - 1.5, h * 0.8)]
    pts += K.bead(a - 2.0, 2.4, h * 0.8, h, 5)[1:]
    if groove:
        pts += [(1.3, h * 0.72), (0.0, h * 0.62), (-1.3, h * 0.72)]
    pts += K.bead(-2.4, -a + 2.0, h, h * 0.8, 5)[1:]
    pts += [(-a + 1.0, h * 0.5), (-a, 0.0)]
    mis = [0] * (len(pts) - 1)
    if groove:
        i = next(j for j, p in enumerate(pts) if p == (1.3, h * 0.72))
        mis[i - 1] = mis[i] = mis[i + 1] = mis[i + 2] = 1
    return pts, mis


def medallion(gem_col):
    W = H = 256
    K.scene(W, H)
    ic = K.mat_iron("iron", seed=25.0)
    groove = K.mat_groove("groove")
    rc, hole = 102.0, 92.0
    pts, mis = ring_profile(20.0, 9.0)
    path = [(rc * math.cos(2 * math.pi * i / 160), rc * math.sin(2 * math.pi * i / 160), 0.0) for i in range(160)]
    K.obj(K.sweep(path, pts, closed=True, closed_profile=False, mis=mis), "ring", [ic, groove])
    bm = K.bmesh.new()
    for a in (90, 0, 270, 180):
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        L = 126 if a != 270 else 127
        K.merge(bm, K.blade((106 * ca, 106 * sa), (L * ca, L * sa), 9.0, 7.0, 5.0, w_pow=1.0, h_tip=0.2))
        K.merge(bm, K.blade((104 * ca, 104 * sa), (93 * ca, 93 * sa), 5.0, 4.0, 7.0))
    for a in (45, 135, 225, 315):
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        K.merge(bm, K.blade((110 * ca, 110 * sa), (121 * ca, 121 * sa), 4.0, 4.0, 4.0))
        K.merge(bm, K.rivet(102 * ca, 102 * sa, 3.6, 8.2))
    K.obj(bm, "spikes", [ic])
    bz = K.xform(K.ring(13.5, prof_thin(5.0, 4.5), seg=48), K.T(0, -103, 7.0))
    K.obj(bz, "bezel", [ic])
    gm = K.mat_gem("gem", gem_col, 1.5)
    K.obj(K.gem(0, -103, 11.0, 9.0, 9.5, facets=10), "gem", [gm], smooth=False)
    K.obj(K.gem(0, 106, 4.6, 11.0), "gem_top", [gm], smooth=False)
    K.catcher(W, H, hole=hole)


@group("medallion_player", (256, 256))
def g_med_player():
    medallion(SOUL)
    return {"medallion_player": {}}


@group("medallion_engine", (256, 256))
def g_med_engine():
    medallion(EMBER)
    return {"medallion_engine": {}}


@group("node_ring", (192, 192))
def g_node_ring():
    W = H = 192
    K.scene(W, H)
    ic = K.mat_iron("iron", seed=27.0)
    groove = K.mat_groove("groove", strength=2.4)
    rc = 76.0
    pts, mis = ring_profile(22.0, 9.0)
    path = [(rc * math.cos(2 * math.pi * i / 144), rc * math.sin(2 * math.pi * i / 144), 0.0) for i in range(144)]
    K.obj(K.sweep(path, pts, closed=True, closed_profile=False, mis=mis), "ring", [ic, groove])
    bm = K.bmesh.new()
    for i in range(8):
        a = 2 * math.pi * i / 8 + math.pi / 2
        L = 94 if i % 2 == 0 else 91
        K.merge(bm, K.blade((84 * math.cos(a), 84 * math.sin(a)), (L * math.cos(a), L * math.sin(a)),
                            6.0 if i % 2 == 0 else 4.2, 5.0, 4.0, w_pow=1.0))
        b = a + math.pi / 8
        K.merge(bm, K.rivet(rc * math.cos(b), rc * math.sin(b), 2.6, 8.8))
    K.obj(bm, "thorns", [ic])
    K.catcher(W, H, hole=65.0)
    return {"node_ring": {}, "node_ring_available": {"glow": 1.0, "glow_col": SOUL},
            "node_ring_visited": {"rust": 1.0, "dark": 0.3}}


# ----------------------------------------------------------------------------------------------- slots

@group("slot", (128, 128))
def g_slot():
    W = H = 128
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=29.0, dent=11.0)
    c = W / 2 - 15
    K.obj(K.frame(c, c, prof_band(17.0, 6.0, 5.5)), "frame", [ih, iv])
    mk = K.Mask(-c, -c, 2 * c, 2 * c)
    g = c - 16
    mk.stroke([(p[0], p[1]) for p in K.rect_path(g, g, 0, 5)], 2.6, 0, closed=True)
    fill_plate(c, c, K.mat_slate("recess", tone=0.5, alpha=0.96, cracks=0.4, mask=mk, rim=(c, c, 14.0)))
    rv = K.bmesh.new()
    for sx, sy in CORNERS:
        K.merge(rv, K.rivet(sx * c, sy * c, 4.4, 5.2))
    K.obj(rv, "rivets", [ic])
    K.catcher(W, H, rect=(c - 3, c - 3))
    return {"slot": {}, "slot_hover": {"glow": 1.0, "glow_col": SOUL},
            "slot_selected": {"glow": 1.0, "glow_col": EMBER}}


# ----------------------------------------------------------------------------------------------- bars

def end_cap(x, s, hh, mat_i, rivet=True, z=0.0, length=26.0):
    """Pointed iron end cap for horizontal bars, s = +1 right / -1 left, tip at x + s * length."""
    out = [(x - s * 4, -hh), (x + s * (length * 0.55), -hh), (x + s * length, 0), (x + s * (length * 0.55), hh),
           (x - s * 4, hh)]
    bm = K.plate(out, z, z + 3.0, [(1.4, 1.6, mat_i), (2.0, 0.0, mat_i), (1.2, 1.2, mat_i)])
    if rivet:
        K.merge(bm, K.rivet(x + s * 6, 0, 3.4, z + 5.6))
    return bm


@group("bar_frame", (512, 48))
def g_bar_frame():
    W, H = 512, 48
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=31.0, dent=10.0)
    K.obj(K.frame(236, 14, prof_band(8.0, 5.0, 5.2)), "rails", [ih, iv])
    fill_plate(236, 12, K.mat_slate("recess", tone=0.45, alpha=0.97, cracks=0.2))
    bm = K.bmesh.new()
    for s in (-1, 1):
        K.merge(bm, end_cap(s * 236, s, 18.0, 0, z=0.5, length=19.0))
        K.merge(bm, K.blade((s * 240, 10), (s * 250, 21), 3.0, 3.0, 2.0))
        K.merge(bm, K.blade((s * 240, -10), (s * 250, -21), 3.0, 3.0, 2.0))
    K.obj(bm, "caps", [ic])
    K.catcher(W, H, rect=(232, 10))
    return {"bar_frame": {}}


@group("bar_fill", (256, 24))
def g_bar_fill():
    W, H = 256, 24
    K.scene(W, H)
    r = 9.5
    xs = [-126 + d for d in (0, 0.6, 2, 4, 6.5, 9.5)]
    rad = [0.2, r * 0.35, r * 0.63, r * 0.84, r * 0.96, r]
    path = [(x, 0, 0) for x in xs] + [(-x, 0, 0) for x in reversed(xs)]
    radii = rad + list(reversed(rad))
    K.obj(K.tube(path, radii, 0.7, 20), "liquid", [K.mat_liquid("liquid")])
    gold = K.lin8(spec.GOLD)
    return {"bar_fill_soul": {"glow_col": SOUL}, "bar_fill_ember": {"glow_col": EMBER},
            "bar_fill_gold": {"glow_col": gold}}


@group("scroll_track", (32, 256))
def g_scroll_track():
    W, H = 32, 256
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=33.0, dent=9.0)
    K.obj(K.frame(9.5, 108, prof_band(6.0, 4.0, 4.2)), "rails", [ih, iv])
    fill_plate(10, 110, K.mat_slate("recess", tone=0.45, alpha=0.97, cracks=0.2))
    bm = K.bmesh.new()
    for s in (-1, 1):
        cap = end_cap(s * 106, s, 13.0, 0, z=0.5, length=20.0)
        K.xform(cap, K.Rz(90))
        K.merge(bm, cap)
    K.obj(bm, "caps", [ic])
    K.catcher(W, H, rect=(7, 104))
    return {"scroll_track": {}}


@group("scroll_grabber", (32, 128))
def g_scroll_grabber():
    W, H = 32, 128
    K.scene(W, H)
    rim = K.mat_iron("rim", aniso=(1.0, 0.15, 1.0), seed=35.0, dent=9.0)
    groove = K.mat_groove("groove")
    face = K.mat_iron("face", aniso=(1.0, 0.15, 1.0), seed=36.0, tone=0.75, wear=0.3)
    out = [(0, -61), (12, -46), (12, 46), (0, 61), (-12, 46), (-12, -46)]
    steps = [(1.4, 1.6, 0), (2.2, 0.0, 0), (0.9, -1.2, 0), (1.3, 0.0, 2), (0.8, -1.2, 1), (0.8, 1.2, 1)]
    K.obj(K.plate(out, 0.0, 3.0, steps, face_mi=2), "plate", [rim, groove, face])
    rv = K.bmesh.new()
    for s in (-1, 1):
        K.merge(rv, K.rivet(0, s * 40, 3.0, 3.0))
    K.obj(rv, "rivets", [K.mat_iron("rivet", seed=2.0)])
    K.catcher(W, H)
    return {"scroll_grabber": {}, "scroll_grabber_hover": {"glow": 1.0, "glow_col": SOUL}}


@group("slider_track", (512, 32))
def g_slider_track():
    W, H = 512, 32
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=37.0, dent=9.0)
    K.obj(K.frame(234, 7.5, prof_band(5.0, 3.6, 3.6)), "rails", [ih, iv])
    fill_plate(236, 6, K.mat_slate("recess", tone=0.42, alpha=0.97, cracks=0.2))
    bm = K.bmesh.new()
    for s in (-1, 1):
        K.merge(bm, end_cap(s * 238, s, 11.0, 0, rivet=False, z=0.5, length=16.0))
    K.obj(bm, "caps", [ic])
    K.catcher(W, H, rect=(234, 5))
    return {"slider_track": {}}


@group("slider_grabber", (48, 48))
def g_slider_grabber():
    W = H = 48
    K.scene(W, H)
    bone = K.mat_bone("bone", ao=2.5)
    put_skull(0, -1.5, 0.0, 26.0, (bone, K.mat_horn("horn"), K.mat_groove("eyes", strength=3.0)), zscale=0.6)
    K.catcher(W, H)
    return {"slider_grabber": {}, "slider_grabber_hover": {"glow": 1.0, "glow_col": SOUL}}


# ----------------------------------------------------------------------------------------------- small widgets

@group("check", (64, 64))
def g_check():
    W = H = 64
    K.scene(W, H)
    ih, iv, ic = iron_set(seed=39.0, dent=8.0)
    c = 21.0
    K.obj(K.frame(c, c, prof_band(10.0, 5.0, 5.0)), "frame", [ih, iv])
    fill_plate(c, c, K.mat_slate("recess", tone=0.5, alpha=0.96, cracks=0.3))
    pts = [(-10.5, 1.0), (-3.0, -8.0), (11.5, 10.5)]
    path = K.catmull([pts[0], ((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2), pts[1],
                      ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2), pts[2]], 4)
    path = [(x, y, 1.5) for x, y, _ in path]
    n = len(path)
    profs = [[(-w, 0.0), (-w * 0.5, 2.2), (w * 0.5, 2.2), (w, 0.0)]
             for w in (2.2 + 1.4 * math.sin(math.pi * i / (n - 1)) for i in range(n))]
    K.obj(K.sweep(path, profs, closed_profile=False, caps=False), "mark",
          [K.mat_emit("mark_mat", SOUL, 1.7)])
    K.catcher(W, H, rect=(c - 3, c - 3))
    return {"check_off": {"_hide": ["mark"]}, "check_on": {}}


@group("close", (64, 64))
def g_close():
    W = H = 64
    K.scene(W, H)
    rim = K.mat_iron("rim", seed=41.0, dent=8.0)
    groove = K.mat_groove("groove", strength=2.6)
    out = []
    for k in range(4):
        a = math.radians(45 + 90 * k)
        d = Vector((math.cos(a), math.sin(a)))
        p = Vector((-d.y, d.x))
        for q in (d * 5.5 - p * 4.0, d * 27.0 - p * 12.5, d * 24.0, d * 27.0 + p * 12.5, d * 5.5 + p * 4.0):
            out.append((q.x, q.y))
    steps = [(1.2, 1.4, 0), (1.6, 0.0, 0), (0.7, -1.0, 1), (0.7, 1.0, 1)]
    K.obj(K.plate(out, 0.0, 3.0, steps, face_mi=0), "cross", [rim, groove])
    K.obj(K.rivet(0, 0, 5.0, 4.6), "rivet", [K.mat_iron("rivet", seed=3.0)])
    K.catcher(W, H)
    return {"close": {}, "close_hover": {"glow": 1.0, "glow_col": EMBER}}


@group("coin", (128, 128))
def g_coin():
    W = H = 128
    K.scene(W, H)
    gold = K.mat_gold("gold")
    prof = [(57.5, 0.0), (58.0, 4.0), (56.8, 7.0), (53.5, 7.6), (51.0, 6.2), (49.8, 4.6), (0.0, 4.6)]
    K.obj(K.lathe(prof, 96), "coin", [gold])
    bm = K.bmesh.new()
    for i in range(30):
        a = 2 * math.pi * i / 30
        K.merge(bm, K.sphere((45.5 * math.cos(a), 45.5 * math.sin(a), 4.6), 1.7, 1.0, 1.0, 0.8, 10, 5))
    K.obj(bm, "beads", [gold])
    put_skull(0, -2.0, 4.0, 46.0, (K.mat_gold("skull", seed=3.0), K.mat_gold("horn", seed=5.0, tone=0.8),
                                    K.mat_gold("eyes", seed=7.0, tone=0.25)), zscale=0.32)
    K.catcher(W, H)
    return {"coin": {}}


def tex_pts(pts, W=48, H=48):
    return [(x - W / 2, H / 2 - y) for x, y in pts]


@group("cursor", (48, 48))
def g_cursor():
    W = H = 48
    K.scene(W, H)
    rim = K.mat_iron("rim", seed=43.0, dent=6.0)
    bone = K.mat_bone("bone", ao=2.0)
    out = tex_pts([(3, 3), (3, 37.5), (11.5, 30.5), (17, 43.5), (24.5, 40.5), (19, 28), (30, 28)])
    K.obj(K.plate(out, 0.0, 2.0, [(0.9, 1.3, 0), (1.0, 0.0, 0), (0.5, -0.6, 0)], face_mi=1), "arrow", [rim, bone])
    K.catcher(W, H)
    return {"cursor": {}}


@group("cursor_point", (48, 48))
def g_cursor_point():
    W = H = 48
    K.scene(W, H)
    bone = K.mat_bone("bone", ao=2.0)
    ic = K.mat_iron("iron", seed=45.0, dent=6.0)

    def P(x, y, z=3.0):
        return (x - 24, 24 - y, z)
    E = [dict(type='ELLIPSOID', co=P(25.5, 31.5), r=15.0, size=(1.0, 0.92, 0.5))]
    for a, b, r in ((P(9.5, 3.5), P(13, 11), 4.0), (P(13, 11), P(16.5, 18), 4.4), (P(16.5, 18), P(20.5, 24.5), 4.8)):
        mid = tuple((a[i] + b[i]) / 2 for i in range(3))
        d = Vector(b) - Vector(a)
        E.append(dict(type='CAPSULE', co=mid, r=r, size=(d.length / 2, 1, 1), rot=K.quat_x_to(d)))
        E.append(dict(type='BALL', co=b, r=r * 1.22))
    for x, y in ((27.0, 20.5), (31.5, 22.5), (35.0, 26.5)):
        E.append(dict(type='BALL', co=P(x, y, 3.8), r=5.8))
    E.append(dict(type='CAPSULE', co=P(15.0, 31.0), r=4.2, size=(3.4, 1, 1), rot=K.quat_x_to((-1.0, 0.5, 0))))
    hand = K.metaball(E, res=0.25)
    K.obj(hand, "hand", [bone])
    cuff = K.plate([(q[0], q[1]) for q in (P(25, 40), P(38, 33), P(44.5, 43), P(32, 47.5))], 0.0, 4.0,
                   [(0.9, 1.0, 0), (1.2, 0.0, 0), (0.6, -0.8, 0)])
    K.obj(cuff, "cuff", [ic])
    K.catcher(W, H)
    return {"cursor_point": {}}


@group("menu_marker", (64, 64))
def g_menu_marker():
    W = H = 64
    K.scene(W, H)
    ic = K.mat_iron("iron", seed=47.0, dent=7.0)
    bm = K.bmesh.new()
    K.merge(bm, K.blade((-6, 0), (30, 0), 7.0, 6.0, 1.0, w_pow=0.9))
    K.merge(bm, K.blade((-6, 0), (-29, 0), 4.0, 4.0, 1.0))
    for sy in (-1, 1):
        K.merge(bm, K.blade((-2, sy * 3), (-18, sy * 22), 4.2, 4.0, 1.0, bend=sy * 5))
        K.merge(bm, K.blade((8, sy * 3), (2, sy * 14), 2.6, 3.0, 1.0, bend=sy * 2))
    K.obj(bm, "thorns", [ic])
    fl = K.gem(0, 0, 6.5, 6.0, 6.0, facets=12)
    K.xform(fl, K.T(-3, 0, 0) @ K.S(1.55, 0.9, 1.0))
    K.obj(fl, "flame", [K.mat_gem("ember", EMBER, 1.5)], smooth=False)
    K.catcher(W, H)
    return {"menu_marker": {}}


@group("bg_slate", (512, 512))
def g_bg_slate():
    W = H = 512
    K.scene(W, H)
    mk = K.Mask(-W / 2, -H / 2, W, H, wrap=True)
    rng = __import__("random").Random(11)
    for i in range(14):
        x, y = rng.uniform(-W / 2, W / 2), rng.uniform(-H / 2, H / 2)
        for j in range(rng.choice((1, 2, 3))):
            mk.rune(rng.randrange(40), x + j * 15, y, 15, 1.8, k=0.55, rot=rng.uniform(-0.15, 0.15))
    bm = K.bmesh.new()
    s = W / 2 + 24
    bm.faces.new([bm.verts.new((x, y, 0)) for x, y in ((-s, -s), (s, -s), (s, s), (-s, s))])
    K.obj(bm, "slate", [K.mat_slate("slate", tone=0.9, mask=mk, torus=W, alpha=0.93)], shadow=False)
    return {"bg_slate": {}}


# ----------------------------------------------------------------------------------------------- driver

def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    samples = None
    if "--samples" in args:
        i = args.index("--samples")
        samples = int(args[i + 1])
        del args[i:i + 2]
    names = args or [n for n in GROUPS if not n.startswith("test_")]
    K.init_gpu()
    t_all = time.time()
    for name in names:
        size, fn = GROUPS[name]
        t0 = time.time()
        K.clear()
        states = fn()
        sc = K.bpy.context.scene
        if samples:
            sc.cycles.samples = samples
        assert (sc.render.resolution_x, sc.render.resolution_y) == (size[0] * K.SCALE, size[1] * K.SCALE), name
        t1 = time.time()
        for out, st in states.items():
            assert name.startswith("test_") or (out in spec.FILES and tuple(spec.FILES[out]["size"]) == tuple(size)), out
            K.ctrl_apply(st)
            K.render(out)
        K.log(f"{name}: build {t1 - t0:.1f}s, {len(states)} renders {time.time() - t1:.1f}s")
    K.log(f"all done {time.time() - t_all:.1f}s")


main()
