"""Builders for the promotion-tree and fairy/legendary pieces (ids and heights in common.FAIRY / HEIGHTS).

Every piece reuses a standard piece's base (plinth, bell, collar, head) from build_pieces.py and adds a
distinct head, crown or accessory from accessories.py. Same contract as the six: metres, Z up, origin at
the bottom centre, front -Y, slots piece_body / piece_trim / piece_glow, everything inside radius 0.42.
Run through build_pieces.py (--only <id>).
"""
import math

import bmesh
import numpy as np
from mathutils import Matrix, Vector

import accessories as A
import build_pieces as B
import common as C
import organic as O
from common import BODY, GLOW, TRIM, Profile

D = math.radians
SEGS = B.SEGS
RIGHT = -1.0  # the piece faces -y, so its right hand is at -x


def body(p, name, phase=0.0, bevel=0.005, segs=SEGS):
    return C.harden(C.lathe(p, name, segs, phase=phase), bevel=bevel)


# ---------------------------------------------------------------- pawn family

def skull_head(skull_top, extras=None, scale=B.SKULL_SCALE, tilt=B.SKULL_TILT, tris=5000):
    """Pawn skull (+ skull-frame extras) placed like the pawn's, the skull top at skull_top."""
    skull, eyes = B.skull_local(tris)
    more = extras() if extras else []
    objs = [skull] + eyes + more
    B.place_skull(objs, skull_top, measure=[skull], scale=scale, tilt=tilt)
    return objs


def pawn_body(name, skull_top, scale=B.SKULL_SCALE, min_dz=-0.03):
    """Pawn base whose neck is stretched so the skull (top at skull_top) sits on it like on the pawn."""
    dz = max(min_dz, skull_top - 0.31 * scale - 0.478)
    p = B.pawn_profile(dz)
    rad = p.radius_fn()
    return body(p, name + "_body"), rad


def pawn_gems(rad, name):
    return C.gem_set(rad, 0.255, 0.018, 0.028, name + "_low", B.around(4, D(45)))


def wing_pair(make, root, span, up):
    """Right wing from make() placed with wing_frame(root, span, up) and its mirror image."""
    w = make()
    A.transform(w, A.wing_frame(root, span, up))
    return A.mirrored(w)


def build_shieldbearer():
    base, rad = pawn_body("shieldbearer", 0.90)
    parts = [base] + skull_head(0.90) + pawn_gems(rad, "shieldbearer")
    shield = A.kite_shield("sb_shield", 0.170, 0.44, sigil="cross")
    for o in shield:
        A.curve_onto(o, 0.52, -0.012)
        o.data.transform(Matrix.Translation((0, -0.345, 0.115)) @ Matrix.Rotation(D(-9), 4, 'X'))
    strap = A.tube("sb_strap", A.bez3((-0.15, -0.27, 0.52), (-0.12, -0.05, 0.64), (0.12, 0.10, 0.50),
                                      (0.15, -0.27, 0.52), 16), [0.011] * 17, segs=6, mat=TRIM, caps=True)
    return parts + shield + [strap]


def build_sergeant():
    base, rad = pawn_body("sergeant", 0.825)
    parts = [base] + skull_head(0.825, lambda: A.nasal_helm("sg_helm", apex=0.375), tris=3800) + pawn_gems(rad, "sergeant")
    shield = A.kite_shield("sg_shield", 0.14, 0.36, sigil="chevron")
    for o in shield:
        A.curve_onto(o, 0.45, -0.012)
        o.data.transform(Matrix.Rotation(D(-RIGHT * 40), 4, 'Z') @ Matrix.Translation((0, -0.335, 0.125)) @
                         Matrix.Rotation(D(-8), 4, 'X'))
    sword = A.sword("sg_sword", 0.44, half_w=0.032, grip=0.075, guard=0.08)
    A.transform(sword, Matrix.Translation((RIGHT * 0.275, -0.15, 0.32)) @ Matrix.Rotation(D(-6 * RIGHT), 4, 'Y') @
                Matrix.Rotation(D(-6), 4, 'X'))
    return parts + shield + sword


HOOD_SCALE = 1.08


def daggers_x(name, centre, lean, length=0.20, spread=D(40)):
    """Two daggers crossed in an X (pommels low), front frame at `centre`, leaning back by `lean`."""
    out = []
    for k, sx in enumerate((-1, 1)):
        d = A.sword("%s%d" % (name, k), length, half_w=0.024, grip=0.06, guard=0.055)
        A.transform(d, Matrix.Translation(centre) @ Matrix.Rotation(lean, 4, 'X') @
                    Matrix.Rotation(spread * sx, 4, 'Y') @ Matrix.Translation((0, -0.012 * k, -0.06)))
        out += d
    return out


def surface_y(obs, z, sign, x=0.0):
    """y where a horizontal ray from the front (sign -1) or back (+1) first meets any of obs at height z."""
    ys = []
    for ob in obs if isinstance(obs, (list, tuple)) else [obs]:
        loc, _n, _i, _d = C.bvh(ob).ray_cast(Vector((x, sign * 1.0, z)), Vector((0, -sign, 0)))
        if loc is not None:
            ys.append(loc.y)
    return max(ys) if sign > 0 else min(ys)


def build_skirmisher():
    s = HOOD_SCALE
    hood = lambda: [A.hood("sk_hood", peak=(0.0, 0.10, 0.47), crown=0.36)]  # noqa: E731
    base, rad = pawn_body("skirmisher", 0.745, s)
    head = skull_head(0.745, hood, scale=s, tris=3600)
    parts = [base] + head + pawn_gems(rad, "skirmisher")
    zf, zb = 0.30, 0.43
    parts += daggers_x("sk_dagger", (0.0, surface_y([base, head[-1]], zf, -1) - 0.010, zf), D(-16), length=0.26,
                       spread=D(44))
    # the same X sheathed on the back, hilts up over the shoulders, so it reads from the player's side too
    back = daggers_x("sk_back", (0.0, 0.0, 0.0), D(18), length=0.22, spread=D(34))
    A.transform(back, Matrix.Translation((0, surface_y(head[-1], zb, 1) + 0.014, zb)) @
                Matrix.Rotation(math.pi, 4, 'X'))
    return parts + back


def build_outrider():
    s = HOOD_SCALE
    hood = lambda: [A.hood("or_hood", crown=0.355, folds=6, target=2200)]  # noqa: E731
    base, rad = pawn_body("outrider", 0.765, s)
    parts = [base] + skull_head(0.765, hood, scale=s, tris=3600) + pawn_gems(rad, "outrider")
    _h, crest = A.knight_on(0.27, (0.0, 0.03, 0.76), target=1000, mane=False)
    for f in crest[0].data.polygons:
        f.material_index = TRIM
    parts.append(crest[0])

    def wing():
        w = A.plate_wing("or_wing", 0.20, n=5, f_len=(0.08, 0.16), sweep=(D(15), D(60)), thick=0.010, arm_r=0.014,
                         spacing=0.03, edge=0.011, gem=True)
        w.append(C.cone("or_spur", (0.0, -0.02, -0.01), (-0.08, -0.02, -0.05), 0.018, segs=8, mat=TRIM))
        return w
    parts += wing_pair(wing, (0.16, 0.02, 0.49), (0.45, 0.15, 0.88), (-0.9, 0.0, 0.45))
    return parts


def spear(name, x, y, z0, z_head, length, half_w, lean=0.0):
    """Upright spear (shaft, ferrule, socket, glowing binding, leaf head) at (x, y), leaning toward the piece."""
    parts = [A.shaft(name + "_shaft", z0, z_head, r=0.0135),
             A.collar_ring(name + "_ferrule", z0, 0.018, h=0.03),
             A.collar_ring(name + "_socket", z_head - 0.03, 0.019, h=0.035),
             C.uv_sphere(name + "_bind", (0, 0, z_head - 0.065), (0.022, 0.022, 0.016), segs=10, rings=6, mat=GLOW),
             A.collar_ring(name + "_grip", 0.44, 0.018, h=0.05)]
    hd = A.leaf_head(name + "_head", length, half_w)
    hd.data.transform(Matrix.Translation((0, 0, z_head)))
    parts.append(hd)
    m = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(lean, 4, Vector((-y, x, 0)).normalized())
    return A.transform(parts, m), m


def build_spearman():
    base, rad = pawn_body("spearman", 0.90)
    parts = [base] + skull_head(0.90) + pawn_gems(rad, "spearman")
    sp, _m = spear("spear", RIGHT * 0.305, -0.11, 0.10, 0.97, 0.18, 0.036, lean=D(-2.5))
    return parts + sp


def build_pikeman():
    base, rad = pawn_body("pikeman", 0.87)
    parts = [base] + skull_head(0.87, lambda: A.kettle_hat("pk_hat"), tris=4200) + pawn_gems(rad, "pikeman")
    parts += C.gem_set(rad, 0.255, 0.018, 0.028, "pikeman_back", [C.FRONT + math.pi])
    pk, m = spear("pike", RIGHT * 0.31, -0.10, 0.10, 1.10, 0.20, 0.022, lean=D(-2.0))
    hook = A.tube("pike_hook", A.bez3((0, 0, 1.07), (0.0, -0.06, 1.10), (0.0, -0.10, 1.07), (0.0, -0.10, 1.02), 8),
                  [0.016, 0.014, 0.012, 0.010, 0.008, 0.006, 0.005, 0.003, 0.0], segs=6, mat=TRIM, flat=0.45,
                  ref=(1, 0, 0))
    hook.data.transform(m)
    spike = C.cone("pike_spike", (0.0, 0.0, 1.06), (0.0, 0.07, 1.09), 0.012, segs=6, mat=TRIM)
    spike.data.transform(m)
    return parts + pk + [hook, spike]


def build_commoner():
    base, rad = pawn_body("commoner", 0.925)
    parts = [base] + skull_head(0.925, lambda: A.circlet("cm_crown", r=0.150, z=0.20, n=8, blade_h=0.085))
    return parts + pawn_gems(rad, "commoner")


def cross_sigil(name, a=0.020, b=0.072, f=0.014):
    """Orthogonal cross in the front frame centred at the origin: glowing inlay in a silver frame."""
    def plus(a, b):
        return [(-a, -b), (a, -b), (a, -a), (b, -a), (b, a), (a, a), (a, b), (-a, b), (-a, a), (-b, a), (-b, -a),
                (-a, -a)]
    sig = C.prism(plus(a, b), -0.010, 0.03, name + "_sigil", GLOW, GLOW, GLOW)
    frame = C.ring_prism(plus(a + f, b + f), plus(a, b), -0.016, 0.03, name + "_frame")
    C.harden(frame, bevel=0.003, segments=1, angle=40)
    return [sig, frame]


def badge(parts, ob, z, sign=-1, tilt=0.0, sink=0.004):
    """Seat front-frame parts (centred at the origin) on ob's front (sign -1) or back (+1) at height z,
    their top leaning in toward the axis by tilt to follow the surface."""
    y = surface_y(ob, z, sign)
    m = Matrix.Translation((0, y + sign * -sink, z)) @ Matrix.Rotation(-tilt, 4, 'X')
    if sign > 0:
        m = Matrix.Translation((0, y - sink, z)) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Rotation(-tilt, 4, 'X')
    return A.transform(parts, m)


def build_wazir():
    p = B.plinth(0.37)
    B.lower_body(p, 0.330, 0.284)
    p.bez((0.282, 0.25), (0.262, 0.30), (0.245, 0.33), n=6)
    p.to(0.250, 0.334)
    p.bead(0.010, 0.024)
    p.to(0.236, 0.362)
    p.bez((0.22, 0.40), (0.19, 0.43), (0.17, 0.45), n=5)
    p.to(0.0, 0.452)
    rad = p.radius_fn()
    parts = [body(p, "wazir_body")]
    hood = lambda: [A.hood("wz_hood", hem=0.30, crown=0.39, folds=8, fold_depth=0.06,  # noqa: E731
                           opening=((0.0, -0.215, 0.115), (0.118, 0.13, 0.15)), target=2800)]
    head = skull_head(0.745, hood, scale=1.0, tilt=D(-14), tris=3600)
    parts += head
    parts += badge(cross_sigil("wz_0", b=0.060), [parts[0], head[-1]], 0.335, -1, tilt=D(14))
    parts += badge(cross_sigil("wz_1"), [parts[0], head[-1]], 0.40, 1, tilt=D(22))
    parts += C.gem_set(rad, 0.232, 0.016, 0.026, "wz_side", (0.0, math.pi))
    return parts


# ---------------------------------------------------------------- knight family

def head_crown(head, name, centre, normal, n=7, blade_h=0.07, half_w=0.022, tilt=D(14), band=0.016,
               reach=0.25, front_cross=0.0, thick=0.018):
    """Crown hugging a (knight-frame) head: a silver strap in the plane (centre, normal) and blades with
    glowing gems standing on it, raycast onto the head; front_cross > 0 puts the king's cross in front."""
    centre = Vector(centre)
    normal = Vector(normal).normalized()
    strap = C.surface_band(head, centre, normal, band, 0.020, name + "_band",
                           keep=lambda c: (c - centre).length < reach and c.z < centre.z + 0.06)
    bm = bmesh.new()
    bm.from_mesh(strap.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if abs((v.co - centre).dot(normal)) > band + 0.03],
                     context='VERTS')  # solidify spikes where the strap clips an ear
    bm.to_mesh(strap.data)
    bm.free()
    parts = [strap]
    tree = C.bvh(head)
    e1 = Vector((1, 0, 0))
    e1 = (e1 - normal * e1.dot(normal)).normalized()
    e2 = normal.cross(e1)
    for k in range(n):
        a = -math.pi / 2 + 2 * math.pi * k / n  # k = 0 faces the front (-y)
        d = (e1 * math.cos(a) + e2 * math.sin(a)).normalized()
        hit, _nn = C.surface_hit(tree, centre + d * 0.5, -d)
        up = (normal * math.cos(tilt) + d * math.sin(tilt)).normalized()
        foot = hit + d * 0.008 - normal * band * 0.6
        if k == 0 and front_cross:
            parts += [A.place(o, foot - normal * 0.03 * front_cross, up, d)
                      for o in A.cross("%s_x" % name, front_cross, segments=1)]
            continue
        bl = B.blade("%s_blade%d" % (name, k), half_w, blade_h, thick, pinch=0.5)
        A.place(bl, foot, up, d)
        g = C.gem(0.0, blade_h * 0.34, half_w * 0.45, blade_h * 0.17, "%s_gem%d" % (name, k), proud=0.008,
                  back=0.006)
        g.data.transform(Matrix.Translation((0.0, -thick / 2, 0.0)))
        A.place(g, foot, up, d)
        parts += [bl, g]
    return parts


def centaur_profile():
    p = B.plinth(0.37)
    B.lower_body(p, 0.325, 0.276)
    p.bez((0.272, 0.245), (0.25, 0.28), (0.236, 0.298), n=6)
    p.to(0.241, 0.30, TRIM)
    p.bead(0.010, 0.024, mat=TRIM)
    p.to(0.230, 0.328)
    p.bez((0.21, 0.37), (0.188, 0.41), (0.186, 0.465), n=6)
    B.collar(p, 0.465, 0.236, 0.212, 0.220, 0.200)
    p.to(0.0, p.cur[1] + 0.002)
    return p


def build_centaur():
    p = centaur_profile()
    rad = p.radius_fn()
    parts = [body(p, "centaur_body")]
    crown = lambda head: head_crown(head, "ct_crown", (0, -0.04, 0.965), (0, -0.22, 1.0), n=7,  # noqa: E731
                                    blade_h=0.13, half_w=0.030, front_cross=0.62)
    _h, head = A.knight_on(0.88, (0, 0.0, 0.52), target=3800, bridle=dict(headpiece=False, cheeks=False),
                           extra=crown)
    parts += head
    parts += C.gem_set(rad, 0.252, 0.02, 0.032, "centaur_low", B.around(4))
    return parts


def build_archbishop():
    p = B.bishop_profile()
    rad = p.radius_fn()
    mitre = C.lathe(p, "archbishop_body", SEGS)
    C.boolean(mitre, C.wrap(B.bent_box(-0.014, 0.014, 0.58, 0.84, -0.12, 0.03, "ab_slit", nx=3), rad))
    v = [(0.0, 0.80), (0.20, 1.20), (-0.20, 1.20)]
    cut = C.prism(v, -0.5, 0.5, "ab_split", GLOW, GLOW, GLOW)
    cut.data.transform(Matrix.Rotation(D(90), 4, 'Z'))  # the split runs front to back
    C.boolean(mitre, cut)
    C.harden(mitre, bevel=0.004)
    parts = [mitre]
    parts += B.bishop_bands(mitre, rad, crest_keep=lambda c: c.z < 0.80 and c.y > 0.0 and c.z > 0.53)
    _h, head = A.knight_on(0.60, (0, 0.03, 0.80), target=3800, bridle=dict(cheeks=False))
    parts += head
    parts += C.gem_set(rad, 0.27, 0.016, 0.05, "archbishop_low", B.around(2))
    return parts


def build_chancellor():
    p = A.stretch(B.rook_profile(), 0.40, 0.70, -0.07)
    rad = p.radius_fn()
    tower = C.lathe(p, "chancellor_body", SEGS, phase=math.pi / SEGS)
    window = (0.058, 0.36, 0.52)
    B.rook_cuts(tower, top=0.93, window=window, slits=False)
    C.harden(tower, bevel=0.005)
    parts = [tower] + B.rook_window_frame(rad, window, "chancellor")
    _h, head = A.knight_on(0.57, (0, 0.035, 0.81), target=3500, bridle=dict(cheeks=False))
    return parts + head


def queen_neck():
    p = B.queen_lower()
    return A.close_top(p, 0.140, p.cur[1])


def build_amazon():
    p = queen_neck()
    rad = p.radius_fn()
    parts = [body(p, "amazon_body")]

    def coronet(head):
        out = head_crown(head, "am_coronet", (0, -0.04, 0.965), (0, -0.22, 1.0), n=5, blade_h=0.12,
                         half_w=0.028)
        mk = lambda: A.plate_wing("am_wing", 0.22, n=5, f_len=(0.07, 0.19), sweep=(D(12), D(66)),  # noqa: E731
                                  thick=0.012, arm_r=0.016, spacing=0.034, edge=0.012)
        out += wing_pair(mk, (0.085, 0.0, 0.97), (0.55, 0.30, 0.78), (-0.6, 0.0, 0.8))
        return out

    _h, head = A.knight_on(0.71, (0, 0.0, 0.858), target=3200, bridle=dict(headpiece=False, cheeks=False),
                           extra=coronet)
    parts += head
    parts += C.gem_set(rad, 0.45, 0.026, 0.046, "amazon_low", B.around(4))
    return parts


def build_knibis():
    p = B.knight_base_profile()
    rad = p.radius_fn()
    parts = [body(p, "knibis_body")]

    def mitre(head):
        mp = Profile(0.0, 0.0)
        mp.to(0.100, 0.0, TRIM)
        mp.up(0.026, TRIM)
        mp.to(0.096, 0.028)
        mp.bez((0.122, 0.07), (0.085, 0.14), (0.006, 0.168), n=10)
        mp.to(0.0, 0.170)
        mrad = mp.radius_fn()
        cap = C.lathe(mp, "kb_mitre", 28)
        for phi in (C.FRONT, C.FRONT + math.pi):
            C.boolean(cap, C.wrap(B.bent_box(-0.012, 0.012, 0.040, 0.15, -0.08, 0.025, "kb_slit", nx=3), mrad, phi))
        C.harden(cap, bevel=0.003)
        fin = B.finial("kb_finial", 0.163, 0.018, 0.022, 0.009)
        out = [cap, fin]
        for k, phi in enumerate(B.around(4, D(45))):
            g = C.gem(0.0, 0.013, 0.014, 0.010, "kb_gem%d" % k, proud=0.010, back=0.004)
            out.append(C.wrap(g, lambda z: 0.100, phi))
        A.transform(out, Matrix.Translation((0, -0.045, 0.952)) @ Matrix.Rotation(D(-12), 4, 'X'))
        return out

    _h, head = A.knight_on(1.0, (0, 0, 0.335), target=4400, ears=False, bridle=dict(cheeks=False), extra=mitre)
    parts += head
    parts += C.gem_set(rad, 0.252, 0.02, 0.032, "knibis_low", B.around(4))
    return parts


def build_kniroo():
    p = B.plinth(0.37)
    B.lower_body(p, 0.325, 0.276)
    p.bez((0.272, 0.245), (0.25, 0.28), (0.236, 0.298), n=6)
    p.to(0.241, 0.30, TRIM)
    p.bead(0.010, 0.024, mat=TRIM)
    p.to(0.232, 0.328)
    p.to(0.228, 0.345)
    p.bez((0.236, 0.36), (0.262, 0.37), (0.266, 0.40), n=5)
    p.to(0.268, 0.50)
    p.to(0.258, 0.508)
    p.to(0.226, 0.508)
    p.to(0.218, 0.50)
    p.to(0.218, 0.45)
    p.to(0.0, 0.448)
    rad = p.radius_fn()
    tower = C.lathe(p, "kniroo_body", SEGS, phase=math.pi / SEGS)
    for k, phi in enumerate(B.around(6, D(30))):
        notch = C.box("kr_notch%d" % k, (0.0, -0.25, 0.508), (0.09, 0.16, 0.085))
        notch.data.transform(Matrix.Rotation(phi + math.pi / 2, 4, 'Z'))
        C.boolean(tower, notch)
    for k, phi in enumerate(B.around(6)):
        C.boolean(tower, B.window_cutter(0.014, 0.385, 0.43, -0.235, "kr_slit%d" % k, phi))
    C.harden(tower, bevel=0.005)
    parts = [tower]
    _h, head = A.knight_on(1.0, (0, 0, 0.385), target=4200, bridle=dict(headpiece=False, cheeks=False))
    parts += head
    parts += C.gem_set(rad, 0.252, 0.018, 0.028, "kniroo_low", B.around(4, D(45)))
    return parts


# ---------------------------------------------------------------- bishop / rook family

def fin(name, base, axis, length, chord, thick=0.014, rake=0.45, mat=TRIM):
    """Thin triangular spine in the yz plane on `base`, its point along `axis` raked toward the back/bottom."""
    base = Vector(base)
    ax = Vector(axis).normalized()
    t = Vector((0.0, ax.z, -ax.y))
    a, b = base - t * chord / 2, base + t * chord / 2
    tip = base + ax * length + t * chord * rake
    bm = bmesh.new()
    loops = [[bm.verts.new(p + Vector((sx * thick / 2, 0, 0))) for p in (a, b, tip)] for sx in (-1, 1)]
    bm.faces.new(loops[0])
    bm.faces.new(list(reversed(loops[1])))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((loops[0][i], loops[1][i], loops[1][j], loops[0][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.material_index = mat
    return C.obj_from_bm(bm, name, smooth=False)


def profile_normal(rad, z, e=0.004):
    """Outward normal (radial, z) of a lathe silhouette at height z."""
    dr = (rad(z + e) - rad(z - e)) / (2 * e)
    n = Vector((1.0, -dr))
    return n.normalized()


def build_dragon_horse():
    p = B.bishop_profile()
    rad = p.radius_fn()
    head = C.lathe(p, "dragon_horse_body", SEGS)
    B.bishop_visor(head, rad)
    C.harden(head, bevel=0.004)
    parts = [head] + B.bishop_bands(head, rad)
    g = C.gem(0.0, 0.985, 0.016, 0.028, "dh_crest_gem", proud=0.012, back=0.004)
    parts.append(C.wrap(g, lambda z: rad(z) + 0.010))
    parts += C.gem_set(rad, 0.27, 0.016, 0.05, "dragon_horse_low", B.around(2))
    # spined crest over the mitre, growing toward the crown and running down the back
    spines = [(-1, 1.02, 0.045), (-1, 1.07, 0.06), (0, 1.121, 0.085), (1, 1.07, 0.085), (1, 1.00, 0.08),
              (1, 0.92, 0.075), (1, 0.83, 0.065), (1, 0.74, 0.055), (1, 0.65, 0.045)]
    for k, (side, z, ln) in enumerate(spines):
        if side == 0:
            base, ax = Vector((0, 0, z - 0.004)), Vector((0, 0.25, 1))
        else:
            nr, nz = profile_normal(rad, z)
            base = Vector((0, side * (rad(z) - 0.004), z))
            ax = Vector((0, side * nr, nz))
        parts.append(fin("dh_spine%d" % k, base, ax, ln, ln * 0.8))
    # curling dragon horns from the sides of the mitre
    for sx in (-1, 1):
        parts.append(A.horn("dh_horn", [(sx * 0.135, 0.02, 0.88), (sx * 0.29, 0.05, 0.94),
                                         (sx * 0.31, 0.16, 1.14), (sx * 0.19, 0.17, 1.25)],
                            0.052, n=22, ridges=6, ridge_depth=0.12))
        g = C.gem(0.0, 0.0, 0.012, 0.018, "dh_horn_gem", proud=0.010, back=0.004)
        A.place(g, (sx * 0.150, -0.045, 0.905), (0, 0, 1), (sx * 0.5, -1, 0))
        parts.append(g)
    return parts


def build_dragon_king():
    dz = 0.04
    p = A.stretch(B.rook_profile(), 0.40, 0.70, dz)
    rad = p.radius_fn()
    top = 1.0 + dz
    tower = C.lathe(p, "dragon_king_body", SEGS, phase=math.pi / SEGS)
    window = (0.064, 0.40, 0.40 + 0.20 * (1 + dz / 0.30))
    B.rook_cuts(tower, top=top, window=window, slits=False)
    C.harden(tower, bevel=0.005)
    parts = [tower] + B.rook_window_frame(rad, window, "dragon_king")
    for k, phi in enumerate(B.around(6, D(30))):
        d = Vector((math.cos(phi), math.sin(phi), 0.0))
        parts.append(B.pyramid("dk_spike%d" % k, d * 0.252 + Vector((0, 0, top - 0.01)), d * 0.38 + Vector((0, 0, 1)),
                               0.05, 0.05, 0.125))
    wr = lambda z: 0.300 + 0.075 * max(0.0, (0.80 - z) / 0.45)  # noqa: E731
    wing = A.bat_wing("dk_wing", (0.05, top + 0.065), [(-0.11, 0.40), (-0.03, 0.33), (0.06, 0.35), (0.13, 0.44)],
                      (-0.03, 0.80), wr, math.pi / 2 + D(42), claw=0.06, scallop=0.075)
    parts += A.mirrored(wing)
    return parts


def build_aiwok():
    p = B.rook_profile()
    rad = p.radius_fn()
    tower = C.lathe(p, "aiwok_body", SEGS, phase=math.pi / SEGS)
    B.rook_cuts(tower, notches=False)
    C.harden(tower, bevel=0.005)
    parts = [tower] + B.rook_window_frame(rad, name="aiwok")
    parts += B.crown_ring("aw_crown", 8, 0.258, 0.99, D(14), 0.040, 0.125, 0.026, gem_size=(0.011, 0.022),
                          phase=D(22.5), pinch=0.5)
    _h, head = A.knight_on(0.60, (0, 0.035, 0.905), target=3400, bridle=dict(headpiece=False, cheeks=False))
    parts += head
    for k, phi in enumerate(B.around(4, D(45))):
        d = Vector((math.cos(phi), math.sin(phi), 0.0))
        parts.append(B.pyramid("aw_spike%d" % k, d * (rad(0.57) - 0.015) + Vector((0, 0, 0.57)),
                               d * 0.85 + Vector((0, 0, 0.55)), 0.07, 0.07, 0.20))
    parts += C.gem_set(rad, 0.47, 0.014, 0.024, "aw_spikegem", B.around(4, D(45)))
    return parts


# ---------------------------------------------------------------- queen family

def stretched_z(z, z0, z1, dz):
    if z > z1:
        return z + dz
    if z > z0:
        return z0 + (z - z0) * (1.0 + dz / (z1 - z0))
    return z


def queen_parts(name, dz=0.0, crown=True, finial=True, low_phase=0.0):
    """The queen (body, crown ring, gems, finial) with its waist stretched by dz; returns (parts, rad)."""
    p = B.queen_bowl(B.queen_lower())
    if dz:
        A.stretch(p, 0.36, 0.74, dz)
    rad = p.radius_fn()
    parts = [body(p, name + "_body")]
    if crown:
        parts += B.crown_ring(name + "_crown", 8, 0.222, 1.15 + dz, D(16), 0.048, 0.19, 0.028,
                              gem_size=(0.013, 0.026), pinch=0.62)
    parts += C.gem_set(rad, stretched_z(0.45, 0.36, 0.74, dz), 0.026, 0.046, name + "_low", B.around(4, low_phase))
    parts += C.gem_set(rad, 1.05 + dz, 0.016, 0.028, name + "_crowngem", B.around(8, D(22.5)))
    if finial:
        parts.append(B.finial(name + "_finial", 1.195 + dz, 0.045, 0.17, 0.026))
    return parts, rad


def raised_wings(name, root, length, out=D(14), lean=D(10), toe=0.0, **kw):
    """A pair of raised (addorsed) wings behind the shoulders: plate_wing with its arm standing up from
    root (leaning out by `out`, back by `lean`), feathers fanning outward; faces to the front and back."""
    w = A.plate_wing(name, length, **kw)
    A.transform(w, Matrix.Translation(root) @ Matrix.Rotation(toe, 4, 'Z') @ Matrix.Rotation(-lean, 4, 'X') @
                Matrix.Rotation(-(math.pi / 2 - out), 4, 'Y'))
    return A.mirrored(w)


def build_leaping_queen():
    dz = 0.04
    parts, rad = queen_parts("leaping_queen", dz)
    parts += raised_wings("lq_wing", (0.10, 0.09, 0.86 + dz), 0.42, out=D(12), lean=D(9), n=7,
                          f_len=(0.08, 0.22), sweep=(D(15), D(62)), droop=0.0, lift=-0.03, thick=0.012,
                          arm_r=0.018, spacing=0.03, edge=0.012)
    return parts


def build_maharani():
    p = B.queen_bowl(B.queen_lower())
    rad = p.radius_fn()
    parts = [body(p, "maharani_body", segs=32)]
    parts += B.crown_ring("mh_crown", 8, 0.222, 1.15, D(13), 0.046, 0.25, 0.028, gem_size=(0.014, 0.030),
                          pinch=0.55)
    parts += B.crown_ring("mh_inner", 4, 0.165, 1.13, D(6), 0.032, 0.17, 0.022, phase=D(45), pinch=0.5)
    parts += C.gem_set(rad, 0.45, 0.026, 0.046, "maharani_low", B.around(4, D(45)))
    parts += C.gem_set(rad, 1.05, 0.016, 0.028, "maharani_crowngem", B.around(8, D(22.5)))
    parts.append(B.finial("mh_spire", 1.195, 0.05, 0.24, 0.028))
    parts.append(C.uv_sphere("mh_spire_gem", (0, 0, 1.36), (0.022, 0.022, 0.03), segs=12, rings=8, mat=GLOW))
    parts += raised_wings("mh_wing", (0.10, 0.11, 0.84), 0.32, out=D(22), lean=D(12), n=5,
                          f_len=(0.06, 0.18), sweep=(D(15), D(60)), droop=0.0, lift=-0.025, thick=0.011,
                          arm_r=0.016, spacing=0.032, edge=0.012, coverts=0)
    # knight-head brooch on the breast: silver head on a glowing disc in a silver ring
    zb = 0.55
    nr, nz = profile_normal(rad, zb)
    n = Vector((0.0, -nr, nz))
    y = -rad(zb)
    disc = C.uv_sphere("mh_brooch_disc", (0, 0, 0), (0.064, 0.064, 0.012), segs=20, rings=8, mat=GLOW)
    ring = A.ring("mh_brooch_ring", 0.068, 0.012, segs=24, minor_segs=8)
    for o in (disc, ring):
        A.place(o, (0.0, y - 0.004, zb), n, (0, 0, 1))
    _h, kh = A.knight_on(0.15, (0, 0, 0), target=700, mane=False)
    for f in kh[0].data.polygons:
        f.material_index = TRIM
    A.transform(kh, Matrix.Translation((0.0, y - 0.036, zb)) @ Matrix.Rotation(-math.atan2(nz, nr), 4, 'X') @
                Matrix.Translation((0, 0, -0.062)))
    return parts + [disc, ring] + kh


def build_siege_queen():
    dz = 0.04
    parts, rad = queen_parts("siege_queen", dz)
    zc = 0.765 + dz
    for sx in (-1, 1):
        d = Vector((sx * 0.20, -0.72, 0.66)).normalized()
        base = Vector((sx * 0.205, 0.085, zc + 0.12))
        b = A.place(A.barrel("sq_barrel", 0.33, 0.058, 0.046, 0.030, rings=(0.25, 0.62), flare=1.25, segs=14),
                    base, d)
        mount = C.box("sq_mount", (sx * 0.200, 0.05, zc + 0.075), (0.085, 0.13, 0.05), TRIM)
        C.harden(mount, bevel=0.006, segments=1)
        trunnion = A.tube("sq_trunnion", [base + d * 0.11 + Vector((-0.08, 0, 0)), base + d * 0.11 + Vector((0.08, 0, 0))],
                          [0.021, 0.021], segs=10, mat=TRIM)
        touch = C.uv_sphere("sq_touch", base + d * 0.03 + Vector((0, 0.0, 0.058)), (0.016, 0.016, 0.013), segs=10,
                            rings=6, mat=GLOW)
        parts += [b, mount, trunnion, touch]
    return parts


def build_bombard():
    dz = 0.06
    parts, rad = queen_parts("bombard", dz, crown=False, finial=False)
    zr = 1.13 + dz
    for k, phi in enumerate(B.around(6, D(30))):
        m = A.barrel("bb_mortar%d" % k, 0.18, 0.054, 0.050, 0.034, rings=(), flare=1.22, knob=False, segs=14)
        B.place_around(m, phi, 0.168, zr, D(20))
        parts.append(m)
    zt = 1.205 + dz
    pp = Profile(0.0, zt - 0.02)
    pp.to(0.06, zt - 0.02, TRIM)
    pp.bez((0.05, zt + 0.02), (0.03, zt + 0.04), (0.032, zt + 0.07), n=5, mat=TRIM)
    pp.to(0.045, zt + 0.075, TRIM)
    pp.to(0.0, zt + 0.08, TRIM)
    parts.append(C.harden(C.lathe(pp, "bb_pedestal", 20), bevel=0.003, segments=1, angle=40))
    zb = zt + 0.12
    parts.append(C.uv_sphere("bb_bomb", (0, 0, zb), (0.074, 0.074, 0.072), segs=18, rings=10))
    parts.append(A.ring("bb_bomb_band", 0.074, 0.009, (0, 0, zb), segs=20))
    parts.append(A.collar_ring("bb_fuse_cap", zb + 0.072, 0.022, h=0.022))
    parts.append(C.cone("bb_fuse", (0, 0, zb + 0.09), (0.012, -0.01, zb + 0.15), 0.008, segs=6, mat=TRIM))
    parts.append(C.uv_sphere("bb_spark", (0.014, -0.012, zb + 0.17), (0.022, 0.022, 0.03), segs=12, rings=8,
                             mat=GLOW))
    return parts


# ---------------------------------------------------------------- king family

def king_parts(name, dz=0.0, crown=(0.105, D(11)), low_phase=0.0, crown_gems=B.around(4, D(22.5))):
    p = B.king_bowl(B.king_lower())
    if dz:
        A.stretch(p, 0.37, 0.83, dz)
    rad = p.radius_fn()
    parts = [body(p, name + "_body")]
    if crown:
        h, tilt = crown
        parts += B.crown_ring(name + "_crown", 8, 0.236, 1.226 + dz, tilt, 0.036, h, 0.026, pinch=0.5,
                              gem_size=(0.011, 0.024) if h > 0.11 else None)
    parts += C.gem_set(rad, stretched_z(0.50, 0.37, 0.83, dz), 0.026, 0.046, name + "_low", B.around(4, low_phase))
    parts += C.gem_set(rad, 1.12 + dz, 0.020, 0.034, name + "_crowngem", crown_gems)
    return parts, rad


def build_warlord():
    parts, rad = king_parts("warlord", crown=(0.08, D(11)))
    hp = Profile(0.0, 1.19)
    hp.to(0.205, 1.19, TRIM)
    hp.up(0.034, TRIM)
    hp.to(0.196, 1.228)
    hp.bez((0.200, 1.32), (0.125, 1.41), (0.0, 1.43), n=10)
    hrad = hp.radius_fn()
    helm = C.harden(C.lathe(hp, "wl_helm", 32), bevel=0.003, segments=1, angle=35)
    parts += [helm] + A.ribs(helm, "wl_rib", B.around(4, D(45)), 1.235)
    for phi in (C.FRONT, C.FRONT + math.pi):
        g = C.gem(0.0, 1.30, 0.020, 0.034, "wl_helm_gem", proud=0.012, back=0.004)
        parts.append(C.wrap(g, lambda z: hrad(z) + 0.004, phi))
    for sx in (-1, 1):
        parts.append(A.horn("wl_horn", [(sx * 0.15, 0.0, 1.29), (sx * 0.31, -0.02, 1.31), (sx * 0.35, -0.03, 1.49),
                                         (sx * 0.26, -0.02, 1.645)], 0.05, n=22, ridges=6, ridge_depth=0.12))
    _h, kh = A.knight_on(0.24, (0, 0.012, 1.40), target=1000, mane=False)
    for f in kh[0].data.polygons:
        f.material_index = TRIM
    return parts + kh


def build_conqueror():
    dz = 0.03
    parts, rad = king_parts("conqueror", dz, crown=(0.15, D(15)))
    parts.append(B.finial("cq_finial", 1.27 + dz, 0.05, 0.13, 0.024))
    for sx in (-1, 1):
        parts.append(A.horn("cq_horn", [(sx * 0.19, 0.02, 1.10 + dz), (sx * 0.37, 0.04, 1.15 + dz),
                                         (sx * 0.40, -0.02, 1.42 + dz), (sx * 0.29, -0.09, 1.67)],
                            0.062, n=20, ridges=7, ridge_depth=0.12))
    # spiked pauldrons on the collar
    zc = 0.845 + dz
    for sx in (-1, 1):
        parts.append(C.uv_sphere("cq_pauldron", (sx * 0.185, 0.0, zc + 0.065), (0.105, 0.125, 0.075), segs=16,
                                 rings=8, mat=TRIM))
        for k, (dx, dy, dzz) in enumerate(((0.75, -0.35, 0.6), (0.85, 0.0, 0.55), (0.75, 0.35, 0.6))):
            d = Vector((sx * dx, dy, dzz)).normalized()
            c = Vector((sx * 0.185, 0.0, zc + 0.065))
            base = c + Vector((d.x * 0.090, d.y * 0.105, d.z * 0.060))
            parts.append(C.cone("cq_spike", base, base + d * (0.10 if k == 1 else 0.075), 0.022, segs=8, mat=TRIM))
        g = C.gem(0.0, 0.0, 0.016, 0.022, "cq_pauldron_gem", proud=0.012, back=0.004)
        A.place(g, (sx * 0.185, -0.12, zc + 0.07), (0, 0, 1), (0, -1, 0))
        parts.append(g)
    # short cape down the back, tattered hem, glowing sigil
    z0, z1 = 0.40, zc + 0.07
    hem = [(-0.24, z0 + 0.05), (-0.17, z0), (-0.12, z0 + 0.06), (-0.06, z0 - 0.01), (0.0, z0 + 0.05),
           (0.06, z0 - 0.01), (0.12, z0 + 0.06), (0.17, z0), (0.24, z0 + 0.05)]
    outline = hem + [(0.20, z1), (-0.20, z1)]
    cape = A.plate(outline, 0.008, "cq_cape", spacing=0.032, r_edge=0.010, pillow=0.003)
    cr = lambda z: max(rad(z), 0.17 + 0.13 * max(0.0, (0.80 - z) / 0.40)) + 0.022  # noqa: E731
    C.wrap(cape, cr, math.pi / 2)
    parts.append(cape)
    sig = cross_sigil("cq_cape_x", a=0.016, b=0.055, f=0.012)
    A.transform(sig, Matrix.Translation((0, -0.010, 0.62)))
    for o in sig:
        C.wrap(o, lambda z: cr(z) + 0.008, math.pi / 2)
    return parts + sig


def face_shield(name, phi, radius, z, tilt):
    """Upright silver face on the crown rim (in place of a blade): shield-shaped mask, brow bar, nose,
    glowing eyes and mouth, leaning out like the blades."""
    outline = []
    for i in range(20):
        t = math.pi * i / 19
        outline.append((0.062 * math.cos(t), 0.115 + 0.05 * math.sin(t)))
    outline += [(-0.060, 0.07), (-0.045, 0.025), (0.0, 0.0), (0.045, 0.025), (0.060, 0.07)]
    outline.reverse()
    mask = A.plate(outline, 0.011, name, spacing=0.014, r_edge=0.009, pillow=0.004, mat=TRIM)
    parts = [mask]
    for sx in (-1, 1):
        parts.append(C.gem(sx * 0.026, 0.098, 0.019, 0.011, name + "_eye", proud=0.022, back=0.0))
    parts.append(C.gem(0.0, 0.040, 0.020, 0.007, name + "_mouth", proud=0.019, back=0.0))
    brow = C.box(name + "_brow", (0.0, -0.012, 0.118), (0.10, 0.016, 0.014), TRIM)
    C.harden(brow, bevel=0.004, segments=1)
    parts += [brow, B.pyramid(name + "_nose", (0.0, -0.010, 0.088), (0, -0.35, -1), 0.022, 0.012, 0.032)]
    for o in parts:
        B.place_around(o, phi, radius, z, tilt)
    return parts


def build_regent():
    parts, rad = king_parts("regent", crown=None, low_phase=D(45), crown_gems=B.around(2, D(90)))
    for k in range(8):
        phi = C.FRONT + 2 * math.pi * k / 8
        if k % 4 == 0:
            parts += face_shield("rg_face%d" % k, phi, 0.236, 1.212, D(11))
        else:
            b = B.blade("regent_crown_blade%d" % k, 0.036, 0.105, 0.026, pinch=0.5)
            parts.append(B.place_around(b, phi, 0.236, 1.226, D(11)))
    parts.append(B.finial("rg_orb", 1.27, 0.045, 0.06, 0.022))
    parts.append(A.shaft("rg_stem", 1.36, 1.57, r=0.012, mat=TRIM))
    zh = 1.545
    for k, sy in enumerate((-1, 1)):
        parts.append(A.ring("rg_halo%d" % k, 0.135, 0.011, (0, sy * 0.02, zh), (0, sy * 0.62, 0.78), segs=36,
                            minor_segs=8, mat=GLOW))
    parts.append(C.uv_sphere("rg_core", (0, 0, zh), (0.024, 0.024, 0.024), segs=12, rings=8, mat=GLOW))
    return parts


# ---------------------------------------------------------------- siege

def carriage(name):
    """Plinth, deck, two cheeks with the trunnion seat, two wheels; returns (parts, rad)."""
    p = B.plinth(0.37)
    B.lower_body(p, 0.325, 0.276)
    p.to(0.262, p.cur[1] + 0.010)
    p.to(0.0, p.cur[1] + 0.010)
    deck = p.cur[1]
    rad = p.radius_fn()
    parts = [body(p, name + "_body")]
    parts += C.gem_set(rad, 0.15, 0.016, 0.022, name + "_low", B.around(4, D(45)), frame=0.012)
    cheek = [(0.22, deck - 0.01), (0.22, 0.34), (0.12, 0.42), (0.02, 0.50), (-0.03, 0.585), (-0.09, 0.585),
             (-0.15, 0.50), (-0.15, deck - 0.01)]
    for sx in (-1, 1):
        ob = C.prism([(-y, z) for y, z in cheek], 0.088, 0.124, name + "_cheek")
        ob.data.transform(Matrix.Rotation(-math.pi / 2, 4, 'Z'))
        if sx < 0:
            A.mirror_x(ob)
        C.harden(ob, bevel=0.006, segments=1)
        parts.append(ob)
        g = C.gem(0.0, 0.0, 0.016, 0.024, name + "_cheek_gem", proud=0.010, back=0.004)
        A.place(g, (sx * 0.125, -0.06, 0.40), (0, 0, 1), (sx, 0, 0))
        parts.append(g)
        # wheel: silver rim, spokes, hub with a glowing cap
        c = Vector((sx * 0.172, 0.04, 0.355))
        parts.append(A.ring(name + "_wheel", 0.118, 0.016, c, (1, 0, 0), segs=28, minor_segs=8, flat=1.3))
        for j in range(6):
            a = 2 * math.pi * j / 6 + 0.3
            d = Vector((0, math.cos(a), math.sin(a)))
            parts.append(A.tube(name + "_spoke", [c + d * 0.03, c + d * 0.108], [0.011, 0.009], segs=6))
        parts.append(A.lathe_on(_hub(), name + "_hub", c, (sx, 0, 0), segs=16))
    return parts, rad, deck


def _hub():
    p = Profile(0.0, -0.022)
    p.to(0.036, -0.022, TRIM)
    p.to(0.036, 0.012, TRIM)
    p.to(0.024, 0.022, TRIM)
    p.to(0.016, 0.022, GLOW)
    p.to(0.0, 0.026, GLOW)
    return p


def cannon_barrel(name, elev=D(40), trunnion=(0.0, -0.06, 0.55)):
    d = Vector((0.0, -math.cos(elev), math.sin(elev)))
    t = Vector(trunnion)
    base = t - d * 0.25
    b = A.place(A.barrel(name, 0.62, 0.085, 0.064, 0.042, rings=(0.2, 0.56), flare=1.3), base, d, (0, 0, 1))
    axle = A.tube(name + "_trunnion", [t + Vector((-0.13, 0, 0)), t + Vector((0.13, 0, 0))], [0.026, 0.026],
                  segs=12, mat=TRIM)
    touch = C.uv_sphere(name + "_touch", base + d * 0.06 + Vector((0, 0, 0.085)), (0.016, 0.016, 0.014), segs=10,
                        rings=6, mat=GLOW)
    return [b, axle, touch]


def build_cannon():
    parts, rad, deck = carriage("cannon")
    return parts + cannon_barrel("cn_barrel")


def build_banner():
    parts, rad, deck = carriage("banner")
    parts += cannon_barrel("bn_barrel")
    yp = 0.245
    pole = A.shaft("bn_pole", deck - 0.01, 1.15, r=0.015)
    pole.data.transform(Matrix.Translation((0, yp, 0)))
    parts += [pole, A.collar_ring("bn_socket", deck + 0.02, 0.024, h=0.05)]
    parts[-1].data.transform(Matrix.Translation((0, yp, 0)))
    head = A.leaf_head("bn_tip", 0.075, 0.022)
    head.data.transform(Matrix.Translation((0, yp, 1.14)))
    parts.append(head)
    zt = 1.08
    parts.append(A.tube("bn_bar", [Vector((-0.175, yp - 0.012, zt)), Vector((0.175, yp - 0.012, zt))],
                        [0.011, 0.011], segs=8, mat=TRIM))
    for sx in (-1, 1):
        parts.append(C.uv_sphere("bn_bar_knob", (sx * 0.18, yp - 0.012, zt), (0.018, 0.018, 0.018), segs=10,
                                 rings=6, mat=TRIM))
    zb = 0.66
    outline = [(-0.16, zt - 0.01), (-0.16, zb + 0.07), (-0.125, zb), (-0.085, zb + 0.09), (-0.035, zb + 0.015),
               (0.0, zb + 0.08), (0.04, zb + 0.005), (0.085, zb + 0.085), (0.125, zb + 0.01), (0.16, zb + 0.075),
               (0.16, zt - 0.01)]
    flag = A.plate(list(reversed(outline)), 0.008, "bn_flag", spacing=0.022, r_edge=0.009, pillow=0.003)
    for v in flag.data.vertices:
        v.co.y += yp - 0.03 + 0.018 * math.sin(v.co.x * 14.0) - 0.04 * (zt - v.co.z)
    parts.append(flag)
    for k, (sy, front) in enumerate(((-1, (0, -1, 0)), (1, (0, 1, 0)))):
        zc = 0.90
        yc = yp - 0.03 + 0.018 * math.sin(0.0) - 0.04 * (zt - zc) + sy * 0.009
        g = C.gem(0.0, 0.0, 0.042, 0.062, "bn_sigil%d" % k, proud=0.010, back=0.002)
        fr = C.ring_prism(C.resample(C.diamond(0, 0, 0.056, 0.080), 2), C.resample(C.diamond(0, 0, 0.042, 0.062), 2),
                          -0.006, 0.004, "bn_sigil_frame%d" % k)
        for o in (g, fr):
            A.place(o, (0, yc, zc), (0, 0, 1), front)
        parts += [g, fr]
    return parts


# ---------------------------------------------------------------- the nightmare

SKULL_OUTLINE = [  # (y, z) horse skull in the knight frame, front = -y
    (-0.095, 0.335), (-0.115, 0.46), (-0.100, 0.56), (-0.130, 0.615), (-0.210, 0.635), (-0.300, 0.648),
    (-0.385, 0.665), (-0.420, 0.695), (-0.405, 0.735), (-0.335, 0.795), (-0.235, 0.885), (-0.150, 0.960),
    (-0.055, 1.005), (0.035, 0.995), (0.100, 0.935), (0.120, 0.850), (0.100, 0.770), (0.105, 0.620),
    (0.118, 0.470), (0.120, 0.335),
]


def skull_width(y, z):
    w = 0.112 * np.ones_like(y)
    w *= 1.0 - 0.55 * O.smoothstep(-0.14, -0.40, y)                                  # long narrow muzzle
    w *= 1.0 - 0.30 * O.smoothstep(0.72, 0.60, z) * O.smoothstep(-0.13, -0.24, y)     # thin lower jaw
    w += 0.034 * O.gauss(y + 0.115, z - 0.835, 0.055)                                 # cheekbones
    w += 0.022 * O.gauss(y + 0.175, z - 0.935, 0.03)                                  # brow ridge
    w -= 0.030 * O.gauss(y - 0.02, z - 0.80, 0.06)                                    # temple hollow
    w *= 1.0 - 0.30 * O.smoothstep(0.55, 0.40, z)                                     # neck vertebra
    return w


def horse_skull(target=4200):
    """Horse skull in the knight frame (neck base z 0.335): deep glowing orbits, a glowing open maw and
    nasal slit, teeth. Returns (skull, extras)."""
    skull = O.inflate(SKULL_OUTLINE, skull_width, "nm_skull", r_edge=0.04, pillow=0.012)
    C.remesh(skull, 0.0055)
    C.smooth(skull, 0.5, 3)
    tree = C.bvh(skull)
    extras = []
    cuts = []
    for sx in (-1, 1):
        hit, n = C.surface_hit(tree, (sx * 0.5, -0.155, 0.885), (-sx, 0, 0))
        cuts.append(C.uv_sphere("nm_orbit", hit - n * 0.006, (0.048, 0.056, 0.044), segs=20, rings=12, mat=GLOW))
        extras.append(C.uv_sphere("nm_eye", hit - n * 0.040, (0.024, 0.028, 0.022), segs=12, rings=8, mat=GLOW))
    maw = C.prism([(-0.16, 0.700), (-0.48, 0.648), (-0.48, 0.775)], -0.2, 0.2, "nm_maw", GLOW, GLOW, GLOW)
    maw.data.transform(Matrix.Rotation(math.pi / 2, 4, 'Z'))
    cuts.append(maw)
    nasal = C.uv_sphere("nm_nasal", (0.0, -0.315, 0.815), (0.022, 0.075, 0.02), segs=16, rings=8, mat=GLOW)
    nasal.data.transform(Matrix.Translation((0, -0.315, 0.815)) @ Matrix.Rotation(D(-38), 4, 'X') @
                         Matrix.Translation((0, 0.315, -0.815)))
    cuts.append(nasal)
    for c in cuts:
        C.boolean(skull, c)
    C.decimate(skull, target)
    C.soften(skull, 70)
    tree = C.bvh(skull)
    for sx in (-1, 1):
        for yy in (-0.37, -0.32, -0.27, -0.22):
            zt = 0.700 + (yy + 0.16) / -0.32 * 0.075
            loc, _n, _i, _d = tree.ray_cast(Vector((sx * 0.2, yy, zt + 0.012)), Vector((-sx, 0, 0)))
            if loc is not None:
                extras.append(B.pyramid("nm_tooth", (loc.x - sx * 0.012, yy, zt + 0.006), (0, 0, -1), 0.016, 0.018,
                                        0.032, mat=BODY))
    return skull, extras


def build_nightmare():
    p = queen_neck()
    rad = p.radius_fn()
    parts = [body(p, "nightmare_body")]
    parts += C.gem_set(rad, 0.45, 0.026, 0.046, "nightmare_low", B.around(4))
    parts += B.crown_ring("nm_collar", 9, 0.165, 0.805, D(52), 0.022, 0.11, 0.022, pinch=0.45)
    skull, extras = horse_skull(3800)
    kparts = [skull] + extras
    for k, ((y, z), (dy, dz), ln) in enumerate(B.KNIGHT_MANE):
        nrm = Vector((0, dy, dz)).normalized()
        base = Vector((0, y - 0.05 - 0.03 * nrm.y, z - 0.03 * nrm.z))
        kparts.append(fin("nm_vertebra%d" % k, base, nrm, ln * 1.2 + 0.03, 0.06, thick=0.018, rake=0.3, mat=BODY))
    for sx in (-1, 1):
        kparts.append(A.horn("nm_horn", [(sx * 0.055, 0.0, 0.975), (sx * 0.17, 0.10, 1.12), (sx * 0.26, 0.27, 1.24),
                                         (sx * 0.25, 0.44, 1.38)], 0.042, n=24, ridges=7, ridge_depth=0.14,
                             mat=GLOW))
        kparts.append(A.horn("nm_ram", [(sx * 0.085, -0.07, 0.925), (sx * 0.21, -0.05, 0.96),
                                        (sx * 0.25, -0.14, 0.88), (sx * 0.20, -0.20, 0.79)], 0.036, n=16,
                             ridges=4, ridge_depth=0.14))
    m = Matrix.Translation((0, 0.02, 0.835)) @ Matrix.Scale(0.74, 4) @ Matrix.Translation((0, 0, -0.335))
    A.transform(kparts, m)
    return parts + kparts


BUILDERS = {
    "shieldbearer": build_shieldbearer, "sergeant": build_sergeant, "skirmisher": build_skirmisher,
    "outrider": build_outrider, "spearman": build_spearman, "pikeman": build_pikeman,
    "commoner": build_commoner, "wazir": build_wazir,
    "centaur": build_centaur, "archbishop": build_archbishop, "chancellor": build_chancellor,
    "amazon": build_amazon, "knibis": build_knibis, "kniroo": build_kniroo,
    "dragon_horse": build_dragon_horse, "dragon_king": build_dragon_king, "aiwok": build_aiwok,
    "leaping_queen": build_leaping_queen, "maharani": build_maharani, "siege_queen": build_siege_queen,
    "bombard": build_bombard, "warlord": build_warlord, "conqueror": build_conqueror, "regent": build_regent,
    "cannon": build_cannon, "banner": build_banner, "nightmare": build_nightmare,
}
