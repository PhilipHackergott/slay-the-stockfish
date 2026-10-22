"""Floating cathedral ruin around the altar -> models/env/environment.glb.

Floor island top at z=-1.25; altar footprint (10.5 m square) + 1.5 m ring + candelabra spots kept clear.
Hero backdrop (rose window) on +Y. Moon behind-left of the rose window, low (moon_dir empty, -Z = light direction).
Tall dressing stays out of the moon-shadow corridor toward the board so the squares stay readable.
"""
import math
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import common as C  # noqa: E402
import env_kit as K  # noqa: E402
from env_kit import M  # noqa: E402

FLOOR = -1.25
CLEAR = 5.25 + 1.5           # half size of altar footprint + ring
ORBIT_R, ORBIT_Z = 14.0, 7.0   # menu orbit camera radius / height
CANDLE_SPOTS = [(sx * 5.85, sy * 5.85) for sx in (-1, 1) for sy in (-1, 1)]
MOON_AZ = math.radians(50)   # left of +Y
MOON_EL = math.radians(23)
MOON = Vector((-math.sin(MOON_AZ) * math.cos(MOON_EL), math.cos(MOON_AZ) * math.cos(MOON_EL), math.sin(MOON_EL)))


def face_origin(x, y):
    """Yaw so a prop's local -Y front faces the board centre."""
    return math.atan2(-x, y)


def in_clear(x, y, margin=0.0):
    if max(abs(x), abs(y)) < CLEAR + margin:
        return True
    return any(math.hypot(x - cx, y - cy) < 0.8 + margin for cx, cy in CANDLE_SPOTS)


class Group:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()

    def add(self, bm, matrix=None):
        C.merge(self.bm, bm, matrix=matrix)


def raycast_top(bvh_list, x, y, z_from=60.0):
    best = None
    for bvh in bvh_list:
        hit = bvh.ray_cast(Vector((x, y, z_from)), Vector((0, 0, -1)))
        if hit[0] is not None and (best is None or hit[0].z > best.z):
            best = hit[0]
    return best


def build():
    rng = random.Random(9001)
    t0 = time.time()
    G = {n: Group(n) for n in ("env_floor", "env_arches", "env_pillars", "env_rosewindow", "env_trees", "env_chains",
                               "env_crows", "env_graves", "env_far")}
    perches = []

    # ---------------------------------------------------------------- main island
    def clear_tiles(x, y):
        return max(abs(x), abs(y)) < 4.85

    def flat(x, y):
        return in_clear(x, y, 0.3)

    floor, rock, inside = K.island(rng, 14.5, 16.5, 13.0, tile=0.56, clear=clear_tiles, flat=flat, cy=2.5,
                                   z_top=FLOOR, n_edge=240, spikes=11, border=(4.9, 6.45))
    G["env_floor"].add(floor)
    G["env_floor"].add(rock)
    C.log("island", round(time.time() - t0, 1), "s")

    def on_island(x, y, m=1.2):
        return inside(x, y, m)

    # ---------------------------------------------------------------- floating chunks
    chunks = [((-22, 8, -3.5), 4.0, 3.2, 6.0, "pillar"), ((20, 19, -2.0), 3.6, 3.0, 5.0, "grave_tree"),
              ((24, -7, -8.0), 5.0, 4.0, 8.0, None), ((-18, -18, -9.0), 3.0, 2.6, 4.5, None),
              ((6, 28, -6.0), 4.5, 3.5, 7.0, "pier"), ((-26, 24, 1.5), 2.6, 2.2, 4.0, "grave"),
              ((14, -21, -13.0), 2.5, 2.2, 4.0, None), ((-7, -26, -15.0), 3.6, 3.0, 5.0, None),
              ((-30, -4, -12.0), 3.0, 2.6, 4.0, None)]
    for (x, y, z), rx, ry, depth, dress in chunks:
        f, r, _ = K.island(rng, rx, ry, depth, tile=0.55, cx=x, cy=y, z_top=z, n_edge=64, spikes=3, edge_noise=0.2)
        G["env_floor"].add(f)
        G["env_floor"].add(r)
        if dress == "pillar":
            p, top = K.broken_pillar(rng, 2.6, scale=0.85)
            G["env_pillars"].add(p, M((x + 0.5, y, z)))
        elif dress in ("grave", "grave_tree"):
            G["env_graves"].add(K.gravestone(rng, "celtic" if dress == "grave" else "gothic"),
                                M((x - 0.6, y + 0.3, z - 0.05), rng.uniform(0, 6.3), rx=0.12))
            if dress == "grave_tree":
                G["env_trees"].add(K.dead_tree(rng, 2.8, depth=3), M((x + 1.0, y - 0.4, z)))
        elif dress == "pier":
            p, top = K.broken_pillar(rng, 1.6, scale=0.9)
            G["env_pillars"].add(p, M((x, y, z), 0.4))
            G["env_pillars"].add(K.rubble(rng, 8, 2.0), M((x, y, z)))
    for (x, y, z), s in (((-16, 14, -4), 1.3), ((17, 6, -6), 1.0), ((-14, -12, -7), 1.5), ((3, -19, -9), 1.2),
                         ((21, 30, 3), 1.4), ((-20, 30, -8), 1.1), ((-35, 12, -2), 1.6)):
        _, r, _ = K.island(rng, s, s * 0.8, s * 2.6, cx=x, cy=y, z_top=z, n_edge=32, spikes=2, tiles_on=False,
                           edge_noise=0.3)
        G["env_floor"].add(r)
    C.log("chunks", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- rose window (hero backdrop, +Y)
    rx, ry = -2.0, 16.6
    rw, rp = K.rose_window(rng)
    m = M((rx, ry, FLOOR), face_origin(rx, ry))
    G["env_rosewindow"].add(rw, m)
    perches += [m @ p for p in rp]

    # ---------------------------------------------------------------- arches
    arch_specs = [
        # (x, y, bays, span, spring, broken_right, scale)
        (6.6, 11.9, 2, 3.0, 3.2, 3, 1.0),
        (-13.0, 0.4, 1, 3.0, 3.4, 0, 1.0),
        (12.9, -2.8, 1, 2.8, 3.0, 4, 0.95),
        (-10.6, -9.9, 3, 2.0, 2.0, 2, 0.8),
        (9.8, -11.0, 1, 2.4, 2.4, 3, 0.85),
    ]
    for x, y, bays, span, spring, br, sc in arch_specs:
        a, ap = K.arch_fragment(rng, bays=bays, span=span, spring=spring, broken_right=br, scale=sc,
                                thick=0.88 * sc)
        m = M((x, y, FLOOR), face_origin(x, y))
        G["env_arches"].add(a, m)
        perches += [m @ p for p in ap]
        G["env_arches"].add(K.rubble(rng, 16, 2.6, size=(0.15, 0.5),
                                     avoid=lambda px, py, m=m: in_clear(*(m @ Vector((px, py, 0))).xy, 0.4)), m)
        if br:
            for i in range(2):
                d = K.fallen_drum(rng, 0.3 * sc, 0.5)
                G["env_arches"].add(d, m @ M((x * 0 + bays * 1.6 + rng.uniform(0.3, 1.5), rng.uniform(-1.8, -0.6), 0),
                                             rng.uniform(0, 6.3)))
    C.log("arches+rose", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- pillars
    pillar_specs = [(-10.6, -1.6, 4.8), (-9.0, -5.6, 2.4), (-8.4, -10.0, 5.6), (8.6, -8.2, 4.4), (-5.8, 10.2, 2.8),
                    (2.4, 9.2, 1.4), (-7.4, 16.2, 6.0), (12.8, 12.0, 5.4), (10.0, 4.6, 1.8)]
    pillar_tops = []
    for x, y, h in pillar_specs:
        p, top = K.broken_pillar(rng, h, scale=rng.uniform(0.85, 0.95))
        m = M((x, y, FLOOR), rng.uniform(0, 6.3))
        G["env_pillars"].add(p, m)
        pillar_tops.append(m @ top)
        G["env_pillars"].add(K.rubble(rng, 12, 1.9, size=(0.12, 0.42),
                                      avoid=lambda px, py, m=m: in_clear(*(m @ Vector((px, py, 0))).xy, 0.4)), m)
    # fallen drums beside the stub and a fallen pillar lying at the front right
    for i in range(3):
        G["env_pillars"].add(K.fallen_drum(rng, 0.34, 0.55), M((3.6 + i * 0.75, 8.4 + rng.uniform(-0.3, 0.3), FLOOR),
                                                               0.5 + rng.uniform(-0.3, 0.3)))
    for i in range(5):
        G["env_pillars"].add(K.fallen_drum(rng, 0.36, 0.6),
                             M((4.2 + i * 0.66, -11.6 + i * 0.12 + rng.uniform(-0.05, 0.05), FLOOR - 0.05),
                               0.17 + rng.uniform(-0.06, 0.06)))
    C.log("pillars", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- graves + bones
    grave_specs = [(8.3, -4.4, "round"), (9.5, -2.0, "gothic"), (8.5, 0.5, "cross"), (10.3, 1.6, "slab"),
                   (9.0, 2.8, "celtic"), (11.2, -0.6, "round"), (10.8, -4.6, "gothic"),
                   (-8.6, 7.6, "gothic"), (-9.9, 8.9, "round"), (-7.6, 9.1, "cross"), (-10.7, 5.8, "celtic"),
                   (-5.6, -11.4, "round"), (-11.6, -3.4, "slab"), (4.5, 13.6, "gothic"), (0.6, 12.6, "round"),
                   (-8.7, -0.6, "gothic"), (-8.2, 1.9, "celtic"), (-9.6, -1.9, "round")]
    for x, y, kind in grave_specs:
        yaw = face_origin(x, y) + rng.uniform(-0.35, 0.35)
        G["env_graves"].add(K.gravestone(rng, kind),
                            M((x, y, FLOOR - 0.06), yaw, rx=rng.uniform(-0.18, 0.12), ry=rng.uniform(-0.14, 0.14)))
    # tomb pinnacles flanking the board in the game view; low enough to stay under the orbit sightlines and
    # placed so their moon shadows fall past the board
    tomb_perches = []
    for x, y, h in ((-7.7, -2.2, 3.0), (7.7, -2.0, 3.0)):
        tb, perch = K.tomb_pinnacle(rng, h)
        m = M((x, y, FLOOR - 0.05), face_origin(x, y) + rng.uniform(-0.15, 0.15),
              rx=rng.uniform(-0.03, 0.03), ry=rng.uniform(-0.03, 0.03))
        G["env_graves"].add(tb, m)
        tomb_perches.append(m @ perch)
    for x, y in ((8.9, -3.1), (-8.8, 8.2), (-7.2, -8.7), (1.8, 14.0), (11.4, 3.6), (-12.2, 2.6), (7.6, 9.8)):
        G["env_graves"].add(K.bone_pile(rng, rng.randint(2, 4)), M((x, y, FLOOR), rng.uniform(0, 6.3)))
    for i in range(10):
        while True:
            a = rng.uniform(0, 2 * math.pi)
            r = rng.uniform(7.5, 13.5)
            x, y = r * math.cos(a), 2.5 + r * math.sin(a) * 1.1
            if on_island(x, y) and not in_clear(x, y, 0.4) and not (abs(x) < 4.7 and y < -4.6):
                break
        G["env_graves"].add(K.skull(rng) if i % 2 else K.long_bone(rng),
                            M((x, y, FLOOR - 0.01), rng.uniform(0, 6.3), rx=rng.uniform(-0.3, 0.3)))
    C.log("graves", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- trees
    for x, y, h, sp, depth in ((10.9, 7.9, 7.4, 1.0, 4), (-12.2, -6.2, 5.6, 1.1, 4), (13.0, -7.2, 4.0, 1.2, 3)):
        G["env_trees"].add(K.dead_tree(rng, h, spread=sp, depth=depth), M((x, y, FLOOR), rng.uniform(0, 6.3)))
    C.log("trees", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- chains from above
    # inside the menu orbit radius a chain must end above every orbit-cam sightline to the board
    for x, y, bottom, hook in ((-6.5, 10.5, 4.2, True), (3.2, 16.9, 6.0, False), (-9.6, 2.6, 2.4, True),
                               (9.2, 1.6, 1.6, True), (-2.8, 18.9, 8.2, True), (10.6, 14.0, 3.8, True),
                               (-8.6, -6.9, 3.6, False), (7.2, -5.9, 2.9, True), (-7.2, -1.2, 3.8, True),
                               (7.3, 0.6, 2.8, False)):
        r = math.hypot(x, y)
        if r < ORBIT_R + 0.5:
            bottom = max(bottom, ORBIT_Z * (r + 4.65) / (ORBIT_R + 4.65) + 1.0)
        G["env_chains"].add(K.hanging_chain(rng, 22.0, bottom, hook=hook), M((x, y, 0), rng.uniform(0, 6.3)))
    C.log("chains", round(time.time() - t0, 1), "s")

    # ---------------------------------------------------------------- crows on real tops
    bvhs = [BVHTree.FromBMesh(G[n].bm) for n in ("env_pillars", "env_arches", "env_rosewindow")]
    crow_spots = [pillar_tops[2], pillar_tops[3], pillar_tops[0], pillar_tops[7]] + perches[:1] + perches[1:2]
    poses = ["perch", "perch", "spread", "perch", "perch", "perch"]
    placed = 0
    for p in tomb_perches:
        G["env_crows"].add(K.crow(rng, "perch", head_turn=rng.uniform(-0.6, 0.6)),
                           M((p.x, p.y, p.z - 0.01), math.atan2(-p.y, -p.x) + rng.uniform(-0.5, 0.5), s=1.15))
        placed += 1
    for spot, pose in zip(crow_spots, poses):
        hit = raycast_top(bvhs, spot.x, spot.y)
        if hit is None or hit.z < FLOOR + 1.0:
            continue
        yaw = math.atan2(-spot.y, -spot.x) + rng.uniform(-0.8, 0.8)
        G["env_crows"].add(K.crow(rng, pose, head_turn=rng.uniform(-0.6, 0.6)),
                           M((hit.x, hit.y, hit.z - 0.01), yaw, s=1.15))
        placed += 1
        if placed >= 5:
            break
    C.log("crows placed", placed)

    # ---------------------------------------------------------------- far backdrop
    far_specs = [((-30, 55, 2), "cathedral", 9, 12), ((12, 70, -4), "spire", 6, 8), ((45, 48, -8), "towers", 8, 10),
                 ((-58, 25, -2), "broken", 6, 7), ((62, 5, -10), "spire", 5, 7), ((-50, -25, -12), "broken", 5, 5),
                 ((35, 85, 6), "spire", 5, 6), ((-15, 88, 8), "towers", 7, 9), ((55, -35, -15), None, 6, 7),
                 ((-75, 55, 0), "spire", 6, 8), ((80, 40, -6), "broken", 7, 8), ((-85, 0, -14), None, 8, 6),
                 ((12, -62, -6), "spire", 6, 8), ((-32, -56, -10), "towers", 7, 8), ((42, -72, -4), "broken", 6, 7),
                 ((-72, -42, -6), "spire", 5, 7)]
    for (x, y, z), kind, r, h in far_specs:
        g = G["env_far"]
        yaw = rng.uniform(0, 6.3)
        _, rk, _ = K.island(rng, r, r * 0.85, r * rng.uniform(2.2, 3.2), cx=x, cy=y, z_top=z, n_edge=28, spikes=2,
                            tiles_on=False, edge_noise=0.25)
        g.add(rk)
        if kind == "cathedral":
            g.add(K.far_cathedral(rng, 14, h), M((x, y, z), face_origin(x, y) + math.pi / 2))
        elif kind == "spire":
            g.add(K.far_tower(rng, h * 2.4, r * 0.5, spire=True), M((x, y, z), yaw))
        elif kind == "towers":
            g.add(K.far_tower(rng, h * 2.6, r * 0.42, spire=True), M((x - r * 0.35, y, z), yaw))
            g.add(K.far_tower(rng, h * 1.8, r * 0.36, spire=False, broken=True), M((x + r * 0.4, y + 1, z), yaw))
        elif kind == "broken":
            g.add(K.far_tower(rng, h * 2.0, r * 0.45, spire=False, broken=True), M((x, y, z), yaw))
    C.log("far", round(time.time() - t0, 1), "s")

    # moss on upward stone faces of the ruins (world-space patches)
    for n in ("env_arches", "env_pillars", "env_rosewindow"):
        K.world_moss(G[n].bm, Matrix.Identity(4), thresh=0.88, scale=0.5, cut=0.12)
    return G


def strip_unused(obj):
    me = obj.data
    used = sorted({p.material_index for p in me.polygons})
    names = [me.materials[i].name for i in used]
    remap = {old: new for new, old in enumerate(used)}
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for n in names:
        me.materials.append(C.material(n))
    for p, i in zip(me.polygons, idx):
        p.material_index = i


def main():
    C.reset()
    t0 = time.time()
    G = build()
    objs = []
    for name, g in G.items():
        if not g.bm.faces:
            continue
        o = C.bm_to_obj(g.bm, name, C.ENV_MATS)
        strip_unused(o)
        C.finish(o, sharp_deg=42 if name not in ("env_trees", "env_crows") else 70)
        objs.append(o)
        C.log(name, C.tris(o), "tris", [m.name for m in o.data.materials])
    C.log("env total tris", sum(C.tris(o) for o in objs), round(time.time() - t0, 1), "s")
    # occluders for the bake: the altar/board and candelabras
    occ = []
    board = os.path.join(C.MODELS, "board", "board.glb")
    if os.path.exists(board):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=board)
        occ = [o for o in bpy.data.objects if o not in before]
    far = [o for o in objs if o.name == "env_far"]
    near = [o for o in objs if o.name != "env_far"]
    C.bake_ao(near, samples=24, distance=1.6)
    C.bake_ao(far, samples=8, distance=4.0)
    for o in occ:
        bpy.data.objects.remove(o)
    C.log("baked", round(time.time() - t0, 1), "s")
    q = MOON.to_track_quat('Z', 'Y')
    moon = C.empty("moon_dir", MOON * 40.0, quat=q, size=3.0)
    C.export_glb(os.path.join(C.MODELS, "env", "environment.glb"), objs + [moon])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(C.BUILD, "environment.blend"))
    C.log("done", round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    main()
