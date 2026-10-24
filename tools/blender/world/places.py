"""The recurring places as board props -> models/props/place_<name>.glb: shop (the Bone Merchant's stall), campfire,
chest (treasure) and shrine (events). The game slams them onto the engine's half of the board.

Contract: one object per glb named like the file, origin at the base centre, front facing Blender -Y (the player),
footprint within 2.6 x 1.6 m so it fits ranks 6-8, slots from PLACE_MATS, empties light_0.. where the game adds
flickering lights (flames, the chest's glow).
Usage: run.sh places.py 900 -- [--only shop]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import common as C  # noqa: E402
import env_kit as K  # noqa: E402
from env_kit import M  # noqa: E402

PLACE_MATS = ["wood", "wood_dead", "iron", "cloth", "gold", "bone", "stone", "stone_dark", "candle_wax",
              "candle_flame", "fire", "board_rune"]
WOOD, CHAR, IRON, CLOTH, GOLD, BONE, STONE, DARK, WAX, FLAME, FIRE, RUNE = range(len(PLACE_MATS))


def box(bm, size, center, mat, bevel=0.0, rz=0.0, rx=0.0, ry=0.0):
    b = C.box(*size, bevel=bevel, seg=1)
    C.merge(bm, b, mat=mat, matrix=M(center, rz, rx, ry))
    b.free()


def rod(bm, a, b, r, mat, seg=6):
    a, b = Vector(a), Vector(b)
    d = b - a
    c = C.lathe([(0.0, 0.0), (r, 0.0), (r, d.length), (0.0, d.length)], seg=seg)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    C.merge(bm, c, mat=mat, matrix=Matrix.Translation(a) @ rot)
    c.free()


def candle(bm, x, y, z, h, r, lights):
    C.merge(bm, C.lathe([(0.0, 0.0), (r, 0.0), (r * 0.97, h), (r * 0.6, h + 0.01), (0.0, h + 0.005)], seg=8),
            mat=WAX, matrix=Matrix.Translation((x, y, z)))
    drip = C.lathe([(0.0, 0.0), (r * 1.6, 0.0), (r * 1.2, 0.02), (0.0, 0.025)], seg=8)
    C.merge(bm, drip, mat=WAX, matrix=Matrix.Translation((x, y, z)))
    fl = C.lathe([(0.0, 0.0), (r * 0.45, 0.012), (r * 0.6, 0.035), (r * 0.4, 0.06), (0.0, 0.085)], seg=6)
    C.merge(bm, fl, mat=FLAME, matrix=Matrix.Translation((x, y, z + h + 0.006)))
    lights.append((x, y, z + h + 0.05))


def coins(bm, rng, x, y, z, n, r=0.055):
    for i in range(n):
        c = C.lathe([(0.0, 0.0), (r, 0.0), (r, 0.012), (0.0, 0.012)], seg=10)
        C.merge(bm, c, mat=GOLD, matrix=M((x + rng.uniform(-0.006, 0.006), y + rng.uniform(-0.006, 0.006),
                                           z + i * 0.013), rng.uniform(0, 6.3)))


def scattered_coins(bm, rng, cx, cy, z, n, spread):
    for i in range(n):
        c = C.lathe([(0.0, 0.0), (0.05, 0.0), (0.05, 0.011), (0.0, 0.011)], seg=10)
        C.merge(bm, c, mat=GOLD, matrix=M((cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread * 0.6, spread * 0.6),
                                           z + 0.004), rng.uniform(0, 6.3), rng.uniform(-0.25, 0.25),
                                          rng.uniform(-0.25, 0.25)))


def skull(bm, rng, loc, rz, s=1.0):
    k = K.skull(rng)
    C.merge(bm, k, mat=BONE, matrix=M(loc, rz, s=s))


def tatters(bm, rng, x0, x1, y, z, n, length):
    """A ragged hem: narrow strips of cloth hanging from y,z between x0 and x1."""
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        L = length * rng.uniform(0.55, 1.15)
        w = (x1 - x0) / n * 0.9
        strip = bmesh.new()
        a = strip.verts.new((-w / 2, 0, 0))
        b = strip.verts.new((w / 2, 0, 0))
        c = strip.verts.new((w * rng.uniform(0.05, 0.3), 0, -L))
        d = strip.verts.new((-w * rng.uniform(0.05, 0.3), 0, -L * rng.uniform(0.7, 0.95)))
        strip.faces.new([a, b, c, d])
        bmesh.ops.solidify(strip, geom=strip.faces[:], thickness=0.012)
        C.merge(bm, strip, mat=CLOTH, matrix=M((x, y, z), 0, rx=rng.uniform(-0.12, 0.05)))


# ----------------------------------------------------------------------------------------------- props

def shop(rng):
    bm = bmesh.new()
    lights = []
    # the counter: planked front, iron straps, a heavy top
    box(bm, (2.3, 0.8, 0.84), (0, 0.05, 0.42), WOOD, bevel=0.025)
    for i in range(10):
        x = -1.035 + i * 0.23
        box(bm, (0.215, 0.035, 0.8), (x, -0.36, 0.42), WOOD, bevel=0.008, ry=rng.uniform(-0.01, 0.01))
    for z in (0.18, 0.66):
        box(bm, (2.36, 0.05, 0.065), (0, -0.39, z), IRON, bevel=0.01)
        for x in (-1.0, -0.33, 0.33, 1.0):
            C.merge(bm, C.uvsphere(0.018, 6, 4), mat=IRON, matrix=Matrix.Translation((x, -0.42, z)))
    for x in (-1.16, 1.16):
        box(bm, (0.08, 0.9, 0.86), (x, 0.05, 0.43), IRON, bevel=0.01)
    box(bm, (2.5, 0.98, 0.075), (0, 0.03, 0.88), WOOD, bevel=0.02)
    # posts and the sloping awning with a ragged hem
    for x in (-1.12, 1.12):
        box(bm, (0.12, 0.12, 2.15), (x, 0.42, 1.075), WOOD, bevel=0.015)
        rod(bm, (x, -0.52, 0.92), (x, -0.52, 1.66), 0.022, IRON)
        C.merge(bm, C.uvsphere(0.04, 8, 5), mat=IRON, matrix=Matrix.Translation((x, -0.52, 1.68)))
    box(bm, (2.42, 0.07, 0.07), (0, 0.42, 2.1), WOOD, bevel=0.01)
    box(bm, (2.42, 0.05, 0.05), (0, -0.52, 1.68), IRON)
    aw = bmesh.new()
    bmesh.ops.create_grid(aw, x_segments=12, y_segments=5, size=1.0)
    half = max(abs(v.co.x) for v in aw.verts)
    for v in aw.verts:
        x, y = v.co.x / half * 1.3, v.co.y / half * 0.54
        sag = 0.06 * math.cos(x / 1.3 * math.pi / 2) * (1 - abs(y) / 0.54) + 0.02 * math.sin(x * 9.0)
        v.co = Vector((x, y, -sag))
    bmesh.ops.solidify(aw, geom=aw.faces[:], thickness=0.02)
    C.merge(bm, aw, mat=CLOTH, matrix=M((0, -0.05, 1.9), 0, rx=0.4))
    tatters(bm, rng, -1.28, 1.28, -0.55, 1.68, 13, 0.3)
    # hanging charms: chains with bones and a skull
    for x, kind in ((-0.75, "skull"), (-0.2, "bone"), (0.45, "bone"), (0.9, "skull")):
        ch = K.hanging_chain(rng, 1.66, 1.3, link=0.05, wire=0.009, hook=False)
        C.merge(bm, ch, mat=IRON, matrix=Matrix.Translation((x, -0.52, 0)))
        if kind == "skull":
            skull(bm, rng, (x, -0.52, 1.13), -math.pi / 2, s=0.8)
        else:
            b = K.long_bone(rng, 0.26)
            C.merge(bm, b, mat=BONE, matrix=M((x, -0.52, 1.22), 0, ry=math.pi / 2))
    # wares on the counter
    top = 0.918
    skull(bm, rng, (-0.72, -0.08, top), -math.pi / 2 + 0.35, s=1.5)
    coins(bm, rng, 0.42, -0.2, top, 5)
    coins(bm, rng, 0.58, -0.08, top, 3)
    coins(bm, rng, 0.5, 0.06, top, 7)
    scattered_coins(bm, rng, 0.2, -0.25, top, 6, 0.18)
    box(bm, (0.42, 0.28, 0.22), (-0.1, 0.18, top + 0.11), WOOD, bevel=0.015)
    box(bm, (0.44, 0.04, 0.24), (-0.1, 0.04, top + 0.11), IRON, bevel=0.005)
    box(bm, (0.06, 0.02, 0.07), (-0.1, 0.02, top + 0.15), GOLD, bevel=0.005)
    # a set of scales
    rod(bm, (0.95, 0.15, top), (0.95, 0.15, top + 0.5), 0.015, IRON)
    rod(bm, (0.72, 0.15, top + 0.5), (1.18, 0.15, top + 0.5), 0.01, IRON)
    for x in (0.72, 1.18):
        rod(bm, (x, 0.15, top + 0.5), (x, 0.15, top + 0.3), 0.004, IRON, seg=4)
        C.merge(bm, C.lathe([(0.0, 0.0), (0.09, 0.025), (0.095, 0.03), (0.0, 0.02)], seg=10), mat=GOLD,
                matrix=Matrix.Translation((x, 0.15, top + 0.27)))
    box(bm, (0.16, 0.16, 0.02), (0.95, 0.15, top + 0.01), IRON, bevel=0.004)
    candle(bm, -1.08, 0.25, top, 0.24, 0.035, lights)
    candle(bm, -0.98, 0.3, top, 0.16, 0.03, lights)
    candle(bm, 1.1, -0.25, top, 0.2, 0.034, lights)
    return bm, lights


def campfire(rng):
    bm = bmesh.new()
    lights = []
    for i in range(11):
        a = i / 11 * 2 * math.pi + rng.uniform(-0.1, 0.1)
        r = 0.56 + rng.uniform(-0.03, 0.04)
        s = rng.uniform(0.11, 0.16)
        C.merge(bm, C.rand_rock(rng, (s * 1.3, s, s * 0.8), sub=1, rough=0.3, flat=0.3), mat=STONE,
                matrix=M((r * math.cos(a), r * math.sin(a), s * 0.35), a + rng.uniform(-0.3, 0.3)))
    bed = C.rand_rock(rng, (0.42, 0.42, 0.06), sub=2, rough=0.25, flat=0.4)
    C.merge(bm, bed, mat=CHAR, matrix=Matrix.Translation((0, 0, 0.02)))
    for i in range(6):
        a = i / 6 * 2 * math.pi + 0.3
        foot = Vector((0.4 * math.cos(a), 0.4 * math.sin(a), 0.03))
        tip = Vector((0.06 * math.cos(a), 0.06 * math.sin(a), 0.52))
        rod(bm, foot, tip, rng.uniform(0.045, 0.06), CHAR if i % 2 else WOOD, seg=7)
    for i, (x, y, h, r) in enumerate(((0, 0, 0.78, 0.2), (0.1, -0.08, 0.55, 0.13), (-0.11, 0.05, 0.6, 0.14),
                                      (0.02, 0.12, 0.48, 0.11))):
        fl = C.lathe([(0.0, 0.0), (r, 0.06), (r * 0.95, h * 0.35), (r * 0.55, h * 0.7), (0.0, h)], seg=9,
                     phase=i * 0.5)
        for v in fl.verts:
            t = v.co.z / h
            v.co.x += 0.05 * math.sin(t * 5 + i) * t
            v.co.y += 0.04 * math.cos(t * 4 + i) * t
        C.merge(bm, fl, mat=FIRE, matrix=Matrix.Translation((x, y, 0.06)))
    lights.append((0, 0, 0.5))
    for x in (-0.68, 0.68):
        rod(bm, (x, 0, 0), (x, 0, 0.82), 0.02, IRON)
        rod(bm, (x, 0, 0.72), (x - 0.06 * (1 if x > 0 else -1), 0, 0.86), 0.015, IRON)
        rod(bm, (x, 0, 0.72), (x + 0.06 * (1 if x > 0 else -1), 0, 0.86), 0.015, IRON)
    rod(bm, (-0.78, 0, 0.8), (0.78, 0, 0.8), 0.014, IRON)
    pot = C.lathe([(0.0, 0.0), (0.1, 0.01), (0.15, 0.08), (0.15, 0.18), (0.12, 0.22), (0.125, 0.235)], seg=12,
                  cap_top=False)
    C.merge(bm, pot, mat=IRON, matrix=Matrix.Translation((0.0, 0, 0.48)))
    rod(bm, (0, 0, 0.71), (0, 0, 0.8), 0.006, IRON, seg=4)
    pile = K.bone_pile(random.Random(9), 3)
    C.merge(bm, pile, mat=BONE, matrix=M((0.75, -0.55, 0), 0.4, s=0.8))
    skull(bm, rng, (-0.78, -0.5, 0), -1.2, s=1.1)
    return bm, lights


def chest(rng):
    bm = bmesh.new()
    lights = []
    w, d, h = 1.05, 0.62, 0.46
    box(bm, (w, d, h), (0, 0, h / 2), WOOD, bevel=0.02)
    for x in (-0.38, 0.0, 0.38):
        box(bm, (0.07, d + 0.03, h + 0.02), (x, 0, h / 2), IRON, bevel=0.008)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(bm, (0.1, 0.1, 0.1), (sx * (w / 2 - 0.04), sy * (d / 2 - 0.04), 0.05), IRON, bevel=0.01)
    box(bm, (0.16, 0.03, 0.18), (0, -d / 2 - 0.02, h - 0.1), GOLD, bevel=0.008)
    # treasure heaped inside, spilling over the front
    heap = C.rand_rock(rng, (w * 0.46, d * 0.42, 0.16), sub=2, rough=0.35, flat=0.5)
    C.merge(bm, heap, mat=GOLD, matrix=Matrix.Translation((0, 0, h - 0.04)))
    scattered_coins(bm, rng, 0, -d / 2 - 0.25, 0, 14, 0.4)
    coins(bm, rng, -0.55, -0.42, 0, 4)
    coins(bm, rng, 0.62, -0.3, 0, 6)
    gem = C.uvsphere(0.05, 6, 4)
    C.merge(bm, gem, mat=RUNE, matrix=Matrix.Translation((0.15, -0.05, h + 0.1)))
    # the arched lid, thrown open on its back hinge
    arc = [(math.cos(a) * d / 2, math.sin(a) * 0.17) for a in [i / 10 * math.pi for i in range(11)]]
    lid = C.prism(arc, -w / 2, w / 2, bevel=0.01)
    C.transform(lid, Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
    for x in (-0.38, 0.0, 0.38):
        band = C.prism([(math.cos(a) * (d / 2 + 0.015), math.sin(a) * 0.185) for a in [i / 10 * math.pi for i in range(11)]],
                       -0.035, 0.035)
        C.transform(band, Matrix.Rotation(math.pi / 2, 4, 'Y') @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
        C.merge(lid, band, mat=IRON, matrix=Matrix.Translation((x, 0, 0)))
    hinge = Matrix.Translation((0, d / 2, h)) @ Matrix.Rotation(-1.95, 4, 'X') @ Matrix.Translation((0, -d / 2, 0))
    C.merge(bm, lid, matrix=hinge)
    lights.append((0, 0, h + 0.25))
    skull(bm, rng, (0.68, 0.22, 0), 2.6, s=1.2)
    b = K.long_bone(rng, 0.4)
    C.merge(bm, b, mat=BONE, matrix=M((-0.7, 0.15, 0.0), 0.8))
    return bm, lights


def shrine(rng):
    bm = bmesh.new()
    lights = []
    box(bm, (1.6, 1.1, 0.16), (0, 0.1, 0.08), DARK, bevel=0.02)
    box(bm, (1.25, 0.85, 0.14), (0, 0.15, 0.23), STONE, bevel=0.02)
    out = C.pointed_arch(0.95, k=1.0, n=10, leg=1.05, closed=True)
    slab = C.prism([(x, z) for x, z in out], -0.11, 0.11, bevel=0.015)
    C.transform(slab, Matrix.Rotation(math.pi / 2, 4, 'X'))
    C.displace(slab, 0.012, 3.0, seed=rng.randint(0, 999))
    C.merge(bm, slab, mat=STONE, matrix=Matrix.Translation((0, 0.38, 0.3 + 1.05)))
    sig = C.torus(0.2, 0.018, seg=24, rseg=4)
    C.transform(sig, Matrix.Rotation(math.pi / 2, 4, 'X'))
    C.merge(bm, sig, mat=RUNE, matrix=Matrix.Translation((0, 0.265, 1.6)))
    for a in (0.0, math.pi / 3, -math.pi / 3):
        box(bm, (0.03, 0.02, 0.5), (0, 0.262, 1.6), RUNE, ry=a)
    # lectern with an open book
    rod(bm, (0, -0.25, 0.3), (0, -0.25, 0.86), 0.05, DARK, seg=8)
    box(bm, (0.5, 0.36, 0.05), (0, -0.25, 0.9), DARK, bevel=0.01, rx=-0.45)
    for sx in (-1, 1):
        box(bm, (0.22, 0.3, 0.025), (sx * 0.115, -0.25, 0.94), BONE, bevel=0.004, rx=-0.45, ry=sx * 0.12)
    box(bm, (0.48, 0.33, 0.012), (0, -0.25, 0.925), CLOTH, rx=-0.45)
    tatters(bm, rng, -0.1, 0.06, -0.38, 0.86, 2, 0.28)
    for x, h in ((-0.52, 0.32), (-0.42, 0.22), (0.5, 0.28), (0.58, 0.18)):
        candle(bm, x, 0.0, 0.3, h, 0.035, lights)
    skull(bm, rng, (-0.55, -0.45, 0.16), -1.4, s=1.1)
    skull(bm, rng, (0.6, -0.42, 0.16), -1.9, s=0.95)
    return bm, lights


PROPS = {"shop": shop, "campfire": campfire, "chest": chest, "shrine": shrine}


def main():
    args = C.script_args()
    only = args[args.index("--only") + 1] if "--only" in args else None
    for name, fn in PROPS.items():
        if only and name != only:
            continue
        C.reset()
        bm, lights = fn(random.Random(hash(name) & 0xFFFF))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        obj = C.bm_to_obj(bm, "place_" + name, PLACE_MATS)
        C.finish(obj, sharp_deg=46)
        xs = [v.co.x for v in obj.data.vertices]
        ys = [v.co.y for v in obj.data.vertices]
        zs = [v.co.z for v in obj.data.vertices]
        C.log("place_%s" % name, C.tris(obj), "tris", "x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (
            min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
        fl = C.bm_to_obj(C.box(10, 10, 0.1, center=(0, 0, -0.05)), "_floor", ["stone"])
        C.bake_ao([obj], samples=32, distance=0.25)
        C.bpy.data.objects.remove(fl)
        emp = [C.empty("light_%d" % i, p, size=0.05) for i, p in enumerate(lights)]
        C.export_glb(os.path.join(C.MODELS, "props", "place_%s.glb" % name), [obj] + emp)


if __name__ == "__main__":
    main()
