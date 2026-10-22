"""Board + rim + altar -> models/board/board.glb.

Contract: 8x8 squares of 1.0 m, top of the squares at z=0, a1 (dark) centred at (-3.5,-3.5); objects board_tiles,
board_rim, altar; empties candelabra_0..3 on the floor (z=-1.25).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402

RNG = random.Random(1307)
H = 4.0            # half size of the 8x8 field
TILE = 0.985       # 1.0 m squares with a 1.5 cm hairline gap
TILE_T = 0.08
FLOOR = -1.25
GAME_CAM = Vector((0, -11, 9.5))

TILE_MATS = ["board_light", "board_dark", "board_rune"]
RIM_MATS = ["board_rim", "board_trim"]
ALTAR_MATS = ["stone", "stone_dark"]

# Elder-futhark-like glyphs in a unit square, as stroke segments.
RUNES = [
    [((-0.2, -0.5), (-0.2, 0.5)), ((-0.2, 0.1), (0.25, 0.45)), ((-0.2, -0.2), (0.25, 0.15))],
    [((-0.25, -0.5), (-0.25, 0.5)), ((-0.25, 0.5), (0.25, 0.2)), ((0.25, 0.2), (0.25, -0.5))],
    [((-0.15, -0.5), (-0.15, 0.5)), ((-0.15, 0.3), (0.25, 0.0)), ((0.25, 0.0), (-0.15, -0.3))],
    [((-0.2, -0.5), (-0.2, 0.5)), ((-0.2, 0.5), (0.2, 0.25)), ((0.2, 0.25), (-0.2, 0.0)), ((-0.2, 0.0), (0.25, -0.5))],
    [((0.2, 0.45), (-0.2, 0.0)), ((-0.2, 0.0), (0.2, -0.45))],
    [((-0.3, -0.45), (0.3, 0.45)), ((-0.3, 0.45), (0.3, -0.45))],
    [((-0.25, -0.5), (-0.25, 0.5)), ((0.25, -0.5), (0.25, 0.5)), ((-0.25, 0.2), (0.25, -0.2))],
    [((0, -0.5), (0, 0.5)), ((-0.25, 0.2), (0.25, -0.1))],
    [((-0.05, 0.45), (-0.3, 0.15)), ((-0.3, 0.15), (-0.05, -0.15)), ((0.05, 0.15), (0.3, -0.15)), ((0.3, -0.15), (0.05, -0.45))],
    [((0, -0.5), (0, 0.5)), ((0, 0.5), (0.25, 0.3)), ((0, -0.5), (-0.25, -0.3))],
    [((0, -0.5), (0, 0.5)), ((0, 0.1), (-0.3, 0.45)), ((0, 0.1), (0.3, 0.45))],
    [((0.2, 0.5), (-0.2, 0.15)), ((-0.2, 0.15), (0.2, -0.15)), ((0.2, -0.15), (-0.2, -0.5))],
    [((0, -0.5), (0, 0.5)), ((0, 0.5), (-0.3, 0.15)), ((0, 0.5), (0.3, 0.15))],
    [((-0.2, -0.5), (-0.2, 0.5)), ((-0.2, 0.5), (0.2, 0.25)), ((0.2, 0.25), (-0.2, 0.0)), ((-0.2, 0.0), (0.2, -0.25)),
     ((0.2, -0.25), (-0.2, -0.5))],
    [((-0.25, -0.5), (-0.25, 0.5)), ((0.25, -0.5), (0.25, 0.5)), ((-0.25, 0.5), (0.25, 0.05)), ((0.25, 0.5), (-0.25, 0.05))],
    [((0, 0.5), (-0.25, 0.2)), ((-0.25, 0.2), (0, -0.1)), ((0, -0.1), (0.25, 0.2)), ((0.25, 0.2), (0, 0.5)),
     ((0, -0.1), (-0.3, -0.5)), ((0, -0.1), (0.3, -0.5))],
    [((-0.3, -0.4), (-0.3, 0.4)), ((0.3, -0.4), (0.3, 0.4)), ((-0.3, 0.4), (0.3, -0.4)), ((-0.3, -0.4), (0.3, 0.4))],
]


def rot_z(k):
    return Matrix.Rotation(k * math.pi / 2, 4, 'Z')


def trap_rib(pts2, w, d, z0, closed=True, bm=None):
    """Small raised rib on a horizontal surface at z0 (4-point trapezoid profile)."""
    prof = [(-w / 2, 0), (-w * 0.28, d), (w * 0.28, d), (w / 2, 0)]
    path = [Vector((x, y, z0)) for x, y in pts2]
    return C.sweep(path, prof, up=(0, 0, 1), closed=closed, closed_profile=False, caps=False, bm=bm)


def wall_rib(pts2, w, d, y0, closed=True, bm=None):
    """Raised rib on a wall facing -Y at y=y0, drawn in (x, z)."""
    prof = [(-w / 2, 0), (-w * 0.28, d), (w * 0.28, d), (w / 2, 0)]
    path = [Vector((x, y0, z)) for x, z in pts2]
    return C.sweep(path, prof, up=(0, -1, 0), closed=closed, closed_profile=False, caps=False, bm=bm)


# ----------------------------------------------------------------------------------------------- tiles

def build_tiles():
    bm = bmesh.new()
    cut = bmesh.new()
    h = TILE / 2
    rune_count = 0
    for f in range(8):
        for r in range(8):
            cx, cy = f - 3.5, r - 3.5
            dark = (f + r) % 2 == 0
            outline = []
            for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                if RNG.random() < 0.12:  # chipped corner (points in CCW order)
                    c = RNG.uniform(0.018, 0.04)
                    a = (sx * h, sy * h)
                    if sx * sy > 0:
                        outline += [(a[0], a[1] - sy * c), (a[0] - sx * c, a[1])]
                    else:
                        outline += [(a[0] - sx * c, a[1]), (a[0], a[1] - sy * c)]
                else:
                    outline.append((sx * h, sy * h))
            t = C.prism(outline, -TILE_T, 0.0, bevel=0.007, seg=2, bevel_top_only=True)
            C.merge(bm, t, mat=1 if dark else 0, matrix=Matrix.Translation((cx, cy, 0)))
            t.free()
            if RNG.random() < 0.42:
                rune_count += 1
                glyph = RNG.choice(RUNES)
                s = RNG.uniform(0.30, 0.36)
                ang = RNG.choice((0.0, math.pi)) + RNG.uniform(-0.12, 0.12)
                m = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(ang, 4, 'Z')
                w = 0.022
                for (x0, y0), (x1, y1) in glyph:
                    p0, p1 = Vector((x0 * s, y0 * s)), Vector((x1 * s, y1 * s))
                    d = p1 - p0
                    L = d.length + w
                    a = math.atan2(d.y, d.x)
                    mid = (p0 + p1) / 2
                    st = C.box(L, w, 0.024, center=(0, 0, 0.008))
                    C.merge(cut, st, mat=2, matrix=m @ Matrix.Translation((mid.x, mid.y, 0)) @ Matrix.Rotation(a, 4, 'Z'))
                    st.free()
                if RNG.random() < 0.45:  # enclosing ring
                    ring_r = s * 0.78
                    prof = [(-w / 2, -0.004), (w / 2, -0.004), (w / 2, 0.02), (-w / 2, 0.02)]
                    path = [Vector((ring_r * math.cos(2 * math.pi * i / 28), ring_r * math.sin(2 * math.pi * i / 28), 0))
                            for i in range(28)]
                    rg = C.sweep(path, prof, up=(0, 0, 1), closed=True, closed_profile=True)
                    C.merge(cut, rg, mat=2, matrix=m)
                    rg.free()
    for f_ in bm.faces:
        f_.normal_update()
    # recess the cutter bottom so grooves are 4 mm deep
    for v in cut.verts:
        if v.co.z < 0:
            v.co.z = -0.004
    bmesh.ops.recalc_face_normals(cut, faces=cut.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out = C.boolean(bm, cut, 'DIFFERENCE', self_inter=True, mats=TILE_MATS)
    C.log("runes on", rune_count, "squares")
    return C.bm_to_obj(out, "board_tiles", TILE_MATS)


# ----------------------------------------------------------------------------------------------- rim

SQUARE = [Vector((-H, -H, 0)), Vector((H, -H, 0)), Vector((H, H, 0)), Vector((-H, H, 0))]


def ring_sweep(profile, mat, bm):
    """Sweep a (u outward, z) profile around the field edge (closed, mitred)."""
    s = C.sweep(SQUARE, profile, up=(0, 0, 1), closed=True, closed_profile=False, caps=False)
    C.merge(bm, s, mat=mat)
    s.free()


def vesica(cx, cy, length, width, n=8):
    """Pointed oval along x."""
    half = length / 2
    R = (half * half + (width / 2) ** 2) / width
    pts = []
    a = math.asin(half / R)
    for i in range(n + 1):
        t = -a + 2 * a * i / n
        pts.append((cx + R * math.sin(t), cy + (R * math.cos(t) - (R - width / 2))))
    for i in range(1, n):
        t = a - 2 * a * i / n
        pts.append((cx + R * math.sin(t), cy - (R * math.cos(t) - (R - width / 2))))
    return pts


def rim_panel(bm_rim, kind, s0):
    """One carved 1 m panel on the south side band, along x from s0 to s0+1."""
    zc = 0.035
    uc = -(H + 0.305)          # panel centre line (y)
    cx = s0 + 0.5
    w, d = 0.02, 0.032
    x0, x1 = s0 + 0.02, s0 + 0.98
    y0, y1 = -(H + 0.49), -(H + 0.12)
    frame = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    trap_rib(frame, 0.028, d, zc, bm=bm_rim)
    if kind == 0:
        trap_rib(C.circle_pts(0.118, 24, cx, uc), w, d, zc, bm=bm_rim)
        trap_rib([(cx + x, uc + y) for x, y in C.foil(4, 0.045, 0.05, n=24, rot=math.pi / 4)], w * 0.9, d * 0.9, zc,
                 bm=bm_rim)
        for sgn in (-1, 1):
            trap_rib(vesica(cx + sgn * 0.3, uc, 0.24, 0.12, n=6), w, d, zc, bm=bm_rim)
            trap_rib(C.circle_pts(0.022, 6, cx + sgn * 0.3, uc), w * 0.8, d * 0.8, zc, bm=bm_rim)
    else:
        for sgn in (-1, 1):
            trap_rib(C.circle_pts(0.1, 20, cx + sgn * 0.075, uc), w, d, zc, bm=bm_rim)
            trap_rib([(cx + sgn * 0.33 + x, uc + y) for x, y in C.foil(4, 0.035, 0.04, n=16)], w * 0.9, d * 0.9, zc,
                     bm=bm_rim)
        trap_rib([(cx - 0.42, uc), (cx - 0.26, uc)], w * 0.8, d * 0.7, zc, closed=False, bm=bm_rim)
        trap_rib([(cx + 0.26, uc), (cx + 0.42, uc)], w * 0.8, d * 0.7, zc, closed=False, bm=bm_rim)


def corner_block(bm, mi_rim, mi_trim):
    """Corner block at (+,+) corner; rotated copies are made by the caller."""
    c = H + 0.335
    blk = C.box(0.69, 0.69, 0.23, bevel=0.012, seg=1, center=(c, c, 0.05 - 0.115))
    for f in blk.faces:
        f.material_index = mi_trim if (f.normal.z > 0.9 and f.calc_center_median().z > 0.04) else mi_rim
    C.merge(bm, blk)
    blk.free()
    z = 0.05
    sq = 0.27
    trap_rib([(c - sq, c - sq), (c + sq, c - sq), (c + sq, c + sq), (c - sq, c + sq)], 0.035, 0.028, z, bm=bm)
    dia = 0.25
    trap_rib([(c, c - dia), (c + dia, c), (c, c + dia), (c - dia, c)], 0.024, 0.026, z, bm=bm)
    trap_rib(C.circle_pts(0.16, 24, c, c), 0.022, 0.027, z, bm=bm)
    trap_rib([(c + x, c + y) for x, y in C.foil(4, 0.05, 0.055, n=24)], 0.02, 0.025, z, bm=bm)
    # set new faces (ribs) to rim material, then iron studs
    for f in bm.faces:
        if f.material_index not in (mi_rim, mi_trim):
            f.material_index = mi_rim
    stud = C.lathe([(0.0, z), (0.05, z), (0.05, z + 0.012), (0.0, 0.08)], seg=4, cap_bottom=False, cap_top=False,
                   phase=math.pi / 4)
    C.merge(bm, stud, mat=mi_trim, matrix=Matrix.Translation((c, c, 0)))
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        st = C.lathe([(0.0, z), (0.022, z), (0.0, 0.072)], seg=4, cap_bottom=False, cap_top=False)
        C.merge(bm, st, mat=mi_trim, matrix=Matrix.Translation((c + sx * sq, c + sy * sq, 0)))


def build_rim():
    bm = bmesh.new()
    RIM, TRIM = 0, 1
    # inner iron bead (rises above the squares)
    ring_sweep([(-0.006, -0.09), (-0.006, 0.03), (0.008, 0.046), (0.032, 0.05), (0.052, 0.044), (0.062, 0.03)], TRIM, bm)
    # inner stone moulding
    ring_sweep([(0.062, 0.03), (0.062, 0.058), (0.074, 0.074), (0.098, 0.076), (0.11, 0.062), (0.112, 0.035)], RIM, bm)
    # recessed panel floor (dark), outer moulding and drop to the cornice
    ring_sweep([(0.112, 0.035), (0.50, 0.035)], TRIM, bm)
    ring_sweep([(0.50, 0.035), (0.50, 0.06), (0.515, 0.075), (0.59, 0.077), (0.608, 0.07), (0.62, 0.052),
                (0.622, 0.025), (0.63, 0.0), (0.648, -0.022), (0.662, -0.05), (0.665, -0.12), (0.655, -0.15),
                (0.64, -0.162)], RIM, bm)
    # backing plate under the squares (seen through the hairline gaps)
    plate = C.box(2 * H + 0.02, 2 * H + 0.02, 0.09, center=(0, 0, -0.125))
    C.merge(bm, plate, mat=TRIM)
    # carved panels: 8 per side, alternating motifs, built on the south side and rotated
    side = bmesh.new()
    for i in range(8):
        rim_panel(side, i % 2, -H + i)
    for f in side.faces:
        f.material_index = RIM
    for k in range(4):
        C.merge(bm, side, matrix=rot_z(k))
    # dentil course on the outer face
    dent = bmesh.new()
    n_d = 64
    for i in range(n_d):
        C.merge(dent, C.box(0.05, 0.022, 0.055, center=(-H + (i + 0.5) * 2 * H / n_d, -(H + 0.672), -0.085)), mat=RIM)
    for k in range(4):
        C.merge(bm, dent, matrix=rot_z(k))
    # corner blocks
    cb = bmesh.new()
    corner_block(cb, RIM, TRIM)
    for k in range(4):
        C.merge(bm, cb, matrix=rot_z(k))
    return C.bm_to_obj(bm, "board_rim", RIM_MATS)


# ----------------------------------------------------------------------------------------------- altar

BODY = H + 0.44           # recessed body face
SCREEN = H + 0.50         # arcade screen front face
Z_TOP = -0.33
Z_BOT = -1.03
NBAY = 12
BAY = 2 * H / NBAY
OPEN_W = 0.40
SILL = -0.98
APEX = -0.42


def lancet(w, apex, sill, k=1.0, n=6):
    ah = C.arch_height(w, k)
    spring = apex - ah
    pts = C.pointed_arch(w, k, n=n, leg=spring - sill)
    return [(x, y + spring) for x, y in pts]


def altar_side():
    """Arcade screen + tracery for the south face (y<0), x in [-H, H]."""
    STONE, DARK = 0, 1
    bm = bmesh.new()
    # screen slab with lancet openings
    slab = C.box(2 * H, SCREEN - BODY + 0.02, Z_TOP - Z_BOT, center=(0, -(BODY + SCREEN) / 2 + 0.01, (Z_TOP + Z_BOT) / 2))
    cutter = bmesh.new()
    for i in range(NBAY):
        cx = -H + BAY * (i + 0.5)
        outline = [(cx + x, z) for x, z in lancet(OPEN_W, APEX, SILL)]
        # prism through the slab along y (outline in x,z)
        pr = C.prism(outline, -0.5, 0.5)
        C.merge(cutter, pr, matrix=Matrix.Translation((0, -(BODY + SCREEN) / 2, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        pr.free()
    set_all = C.set_mat
    set_all(slab, STONE)
    set_all(cutter, STONE)
    scr = C.boolean(slab, cutter, 'DIFFERENCE', mats=ALTAR_MATS)
    C.merge(bm, scr)
    y_face = -SCREEN
    y_back = -BODY
    for i in range(NBAY):
        cx = -H + BAY * (i + 0.5)
        out = lancet(OPEN_W, APEX, SILL)
        arch_only = [(cx + x, z) for x, z in out[1:-1]]
        wall_rib(arch_only, 0.045, 0.035, y_face, closed=False, bm=bm)
        hood = [(cx + x * 1.22, APEX - (APEX - z) * 1.0 + 0.05) for x, z in out[1:-1]]
        wall_rib(hood, 0.03, 0.025, y_face, closed=False, bm=bm)
        # blind tracery on the recessed body face: mullion, two sub-lancets, oculus
        sub_w = OPEN_W * 0.40
        spring = APEX - C.arch_height(OPEN_W)
        sub_apex = spring + 0.06
        for sgn in (-1, 1):
            sl = [(cx + sgn * sub_w * 0.56 + x, z) for x, z in lancet(sub_w, sub_apex, SILL + 0.02, n=4)]
            wall_rib(sl, 0.022, 0.03, y_back, closed=True, bm=bm)
        wall_rib(C.circle_pts(0.058, 12, cx, sub_apex + 0.075), 0.02, 0.03, y_back, bm=bm)
        wall_rib([(cx + x, sub_apex + 0.075 + y) for x, y in C.foil(3, 0.02, 0.026, n=12, rot=math.pi / 2)],
                 0.014, 0.022, y_back, bm=bm)
        # colonnette on the pier to the left of the opening (plus one at the far right end)
        for px in ([cx - BAY / 2] + ([cx + BAY / 2] if i == NBAY - 1 else [])):
            if abs(px) > H - 0.05:
                continue
            spring_z = APEX - C.arch_height(OPEN_W)
            col = C.lathe([(0.0, Z_BOT + 0.0), (0.06, Z_BOT), (0.06, Z_BOT + 0.05), (0.045, Z_BOT + 0.075),
                           (0.034, Z_BOT + 0.09), (0.03, spring_z - 0.07), (0.04, spring_z - 0.05),
                           (0.055, spring_z - 0.02), (0.062, spring_z - 0.02), (0.062, spring_z), (0.0, spring_z)],
                          seg=8, phase=math.pi / 8)
            C.merge(bm, col, mat=STONE, matrix=Matrix.Translation((px, y_face - 0.005, 0)))
            col.free()
    # body back face
    back = C.box(2 * H, 0.04, Z_TOP - Z_BOT, center=(0, y_back + 0.02, (Z_TOP + Z_BOT) / 2))
    C.merge(bm, back, mat=DARK)
    for f in bm.faces:
        if f.material_index > 1:
            f.material_index = STONE
    return bm


def pilaster(bm):
    """Corner pier at (+,+): carved on its two outer faces."""
    STONE = 0
    c0, c1 = H - 0.02, H + 0.62
    cx = (c0 + c1) / 2
    p = C.box(c1 - c0, c1 - c0, Z_TOP - Z_BOT, bevel=0.015, center=(cx, cx, (Z_TOP + Z_BOT) / 2))
    C.merge(bm, p, mat=STONE)
    cap = C.box(c1 - c0 + 0.06, c1 - c0 + 0.06, 0.06, bevel=0.012, center=(cx, cx, Z_TOP - 0.05))
    C.merge(bm, cap, mat=STONE)
    base = C.box(c1 - c0 + 0.06, c1 - c0 + 0.06, 0.08, bevel=0.015, center=(cx, cx, Z_BOT + 0.04))
    C.merge(bm, base, mat=STONE)
    # carved lancet panel + quatrefoil on both outer faces (built on a -Y face, rotated into place)
    face = bmesh.new()
    pw = 0.42
    out = lancet(pw, Z_TOP - 0.1, Z_BOT + 0.12, k=1.0, n=6)
    wall_rib(out, 0.035, 0.03, 0.0, bm=face)
    wall_rib(C.circle_pts(0.12, 16, 0, Z_TOP - 0.1 - 0.26), 0.025, 0.03, 0.0, bm=face)
    wall_rib([(x, Z_TOP - 0.36 + y) for x, y in C.foil(4, 0.045, 0.05, n=16)], 0.02, 0.025, 0.0, bm=face)
    wall_rib([(0, Z_BOT + 0.14), (0, Z_TOP - 0.52)], 0.03, 0.028, 0.0, closed=False, bm=face)
    # face toward +X at x=c1 (rotate -Y face by +90 deg) and toward +Y at y=c1 (180 deg)
    C.merge(bm, face, mat=STONE, matrix=Matrix.Translation((c1, cx, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
    C.merge(bm, face, mat=STONE, matrix=Matrix.Translation((cx, c1, 0)) @ Matrix.Rotation(math.pi, 4, 'Z'))
    # small pyramid finial knob at the pier's outer corner
    return bm


def plinth(bm):
    """Two courses of individual worn blocks."""
    STONE, DARK = 0, 1
    courses = [(H + 0.75, -1.15, -1.03, STONE), (H + 1.0, FLOOR - 0.02, -1.15, DARK)]
    for half, z0, z1, mi in courses:
        for k in range(4):
            # south side run from -half to half (corners owned by the run that starts there)
            x = -half
            while x < half - 1e-3:
                L = RNG.uniform(0.9, 1.45)
                if half - (x + L) < 0.5:
                    L = half - x
                gap = 0.012
                depth = half - (H + 0.25)
                bx = C.box(L - gap, depth - gap, (z1 - z0) + RNG.uniform(-0.004, 0.004), bevel=0.018, seg=2,
                           center=(x + L / 2, -half + depth / 2, (z0 + z1) / 2))
                C.displace(bx, 0.006, 3.0, seed=RNG.randint(0, 999))
                ang = RNG.uniform(-0.004, 0.004)
                C.merge(bm, bx, mat=mi, matrix=rot_z(k) @ Matrix.Rotation(ang, 4, 'Z'))
                bx.free()
                x += L
    # fill core so no gaps show through
    core = C.box(2 * (H + 0.25), 2 * (H + 0.25), 1.15 - 0.33, center=(0, 0, -(1.15 + 0.33) / 2 - 0.02))
    C.merge(bm, core, mat=DARK)


def build_altar():
    bm = bmesh.new()
    STONE, DARK = 0, 1
    # cornice (moulded, stepping in from the rim to the body)
    prof = [(0.645, -0.15), (0.64, -0.17), (0.615, -0.19), (0.59, -0.215), (0.575, -0.245), (0.572, -0.26),
            (0.585, -0.27), (0.59, -0.29), (0.58, -0.31), (0.56, -0.325), (0.44, -0.335)]
    s = C.sweep(SQUARE, prof, up=(0, 0, 1), closed=True, closed_profile=False, caps=False)
    C.merge(bm, s, mat=STONE)
    side = altar_side()
    for k in range(4):
        C.merge(bm, side, matrix=rot_z(k))
    pl = bmesh.new()
    pilaster(pl)
    for k in range(4):
        C.merge(bm, pl, matrix=rot_z(k))
    plinth(bm)
    return C.bm_to_obj(bm, "altar", ALTAR_MATS)


def candelabra_empties():
    out = []
    d = H + 1.0 + 1.2 / math.sqrt(2)
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        p = Vector((sx * d, sy * d, FLOOR))
        v = GAME_CAM - p
        yaw = math.atan2(v.y, v.x) + math.pi / 2  # candelabra arms (local X) broadside to the game camera
        out.append(C.empty("candelabra_%d" % i, p, rot=(0, 0, yaw)))
    return out


def main():
    C.reset()
    tiles = build_tiles()
    rim = build_rim()
    altar = build_altar()
    objs = [tiles, rim, altar]
    for o, ang in ((tiles, 30), (rim, 38), (altar, 38)):
        C.finish(o, sharp_deg=ang)
        C.log(o.name, C.tris(o), "tris", [m.name for m in o.data.materials])
    C.log("board total tris", sum(C.tris(o) for o in objs))
    # temporary floor so the plinth gets contact occlusion
    fl = C.bm_to_obj(C.box(40, 40, 0.1, center=(0, 0, FLOOR - 0.05)), "_floor", ["stone"])
    C.bake_ao(objs, samples=48, distance=0.6)
    C.bpy.data.objects.remove(fl)
    emp = candelabra_empties()
    C.export_glb(os.path.join(C.MODELS, "board", "board.glb"), objs + emp)
    C.bpy.ops.wm.save_as_mainfile(filepath=os.path.join(C.BUILD, "board.blend"))


if __name__ == "__main__":
    main()
