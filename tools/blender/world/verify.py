"""Re-import the three world glbs in fresh scenes, print their contents and assert the asset contract.

run.sh verify.py 300            exit code 1 if any check fails
"""
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

GLB_BOARD = os.path.join(C.MODELS, "board", "board.glb")
GLB_CANDLE = os.path.join(C.MODELS, "props", "candelabra.glb")
GLB_ENV = os.path.join(C.MODELS, "env", "environment.glb")
FLOOR = -1.25
GAME_CAM = Vector((0, -11, 9.5))
ORBIT_R, ORBIT_Z = 14.0, 7.0
BUDGET = {"board": 80000, "candelabra": 8000, "environment": 450000}
BOARD_SLOTS = {"board_tiles": ["board_light", "board_dark", "board_rune"], "board_rim": ["board_rim", "board_trim"],
               "altar": ["stone", "stone_dark"]}

failures = []


def check(ok, msg):
    print(("  PASS " if ok else "  FAIL ") + msg)
    if not ok:
        failures.append(msg)


def load(path):
    C.reset()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    return [o for o in bpy.data.objects if o not in before]


def world_verts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def bbox(o):
    vs = world_verts(o)
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def has_ao(o):
    """glTF stores the 'ao' attribute as unnamed COLOR_0; the importer calls it 'Color'."""
    ca = o.data.color_attributes
    a = ca.active_color
    if a is None or len(a.data) == 0:
        return False
    vals = [d.color[0] for d in a.data]
    return min(vals) < 0.8 and max(vals) > 0.5


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def fmt(v):
    return "(" + ", ".join(f"{c:7.3f}" for c in v) + ")"


def godot(v):
    return Vector((v.x, v.z, -v.y))


def report(objs, label):
    print(f"\n=== {label}")
    total = 0
    for o in sorted(objs, key=lambda o: (o.type != 'MESH', o.name)):
        if o.type == 'MESH':
            lo, hi = bbox(o)
            n = tris(o)
            total += n
            attrs = [a.name for a in o.data.color_attributes]
            act = o.data.color_attributes.active_color.name if o.data.color_attributes.active_color else None
            print(f"  MESH  {o.name:16s} tris {n:7d}  bbox {fmt(lo)} .. {fmt(hi)}")
            print(f"        slots {[m.name for m in o.data.materials]}  colour attrs {attrs} active {act}")
        elif o.type == 'EMPTY':
            p = o.matrix_world.translation
            print(f"  EMPTY {o.name:16s} blender {fmt(p)}  godot {fmt(godot(p))}")
    print(f"  total tris {total}")
    return total


def bvh_of(objs):
    verts, polys = [], []
    for o in objs:
        if o.type != 'MESH':
            continue
        base = len(verts)
        verts += world_verts(o)
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys) if polys else None


def top_faces_in(o, x0, x1, y0, y1, z=0.0):
    mw = o.matrix_world
    out = []
    for p in o.data.polygons:
        c = mw @ p.center
        n = (mw.to_3x3() @ p.normal).normalized()
        if n.z > 0.99 and abs(c.z - z) < 1e-4 and x0 < c.x < x1 and y0 < c.y < y1:
            out.append(p)
    return out


# ------------------------------------------------------------------------------------------------ board

def verify_board():
    objs = load(GLB_BOARD)
    total = report(objs, "board.glb")
    by = {o.name: o for o in objs}
    check(all(n in by and by[n].type == 'MESH' for n in BOARD_SLOTS), "objects board_tiles, board_rim, altar present")
    for n, slots in BOARD_SLOTS.items():
        if n in by:
            check([m.name for m in by[n].data.materials] == slots, f"{n} slots == {slots}")
            ca = by[n].data.color_attributes
            check(has_ao(by[n]), f"{n} active vertex colour (COLOR_0 = baked 'ao') carries occlusion")
    tiles, rim, altar = by.get("board_tiles"), by.get("board_rim"), by.get("altar")
    if tiles:
        lo, hi = bbox(tiles)
        check(abs(hi.z) < 1e-4, f"board_tiles top z = {hi.z:.5f} (== 0)")
        check(abs(lo.x + 4) < 0.02 and abs(hi.x - 4) < 0.02 and abs(lo.y + 4) < 0.02 and abs(hi.y - 4) < 0.02,
              f"board_tiles spans x {lo.x:.3f}..{hi.x:.3f}, y {lo.y:.3f}..{hi.y:.3f} (8 x 1.0 m)")
        mats = tiles.data.materials
        bad = []
        for f in range(8):
            for r in range(8):
                cx, cy = -3.5 + f, -3.5 + r
                faces = top_faces_in(tiles, cx - 0.5, cx + 0.5, cy - 0.5, cy + 0.5)
                if not faces:
                    bad.append((f, r, "no top face"))
                    continue
                xs = [tiles.matrix_world @ tiles.data.vertices[i].co for p in faces for i in p.vertices]
                bx = (min(v.x for v in xs) + max(v.x for v in xs)) / 2
                byy = (min(v.y for v in xs) + max(v.y for v in xs)) / 2
                want = "board_dark" if (f + r) % 2 == 0 else "board_light"
                names = {mats[p.material_index].name for p in faces}
                if abs(bx - cx) > 0.01 or abs(byy - cy) > 0.01 or names != {want}:
                    bad.append((f, r, round(bx, 3), round(byy, 3), names))
                if f == 0 and r == 0:
                    check(abs(bx + 3.5) < 0.01 and abs(byy + 3.5) < 0.01,
                          f"a1 top-face centre ({bx:.4f}, {byy:.4f}) == (-3.5, -3.5)")
                    check(names == {"board_dark"}, f"a1 is dark ({sorted(names)})")
        check(not bad, f"all 64 squares centred on the 1 m grid with alternating colours {bad[:3]}")
        nr = len({(math.floor((tiles.matrix_world @ p.center).x + 4), math.floor((tiles.matrix_world @ p.center).y + 4))
                  for p in tiles.data.polygons if mats[p.material_index].name == "board_rune"})
        print(f"  info: rune faces present on ~{nr} squares")
    if rim:
        lo, hi = bbox(rim)
        width = hi.x - 4.0
        check(0.04 <= hi.z <= 0.08, f"board_rim top z = {hi.z:.3f} (0.04..0.08)")
        check(0.55 <= width <= 0.70, f"board_rim width = {width:.3f} m (0.55..0.70)")
    if altar:
        lo, hi = bbox(altar)
        check(abs(lo.z - FLOOR) < 0.03, f"altar bottom z = {lo.z:.3f} (== {FLOOR})")
        print(f"  info: altar footprint {hi.x - lo.x:.2f} x {hi.y - lo.y:.2f} m")
    emp = sorted([o for o in objs if o.type == 'EMPTY' and o.name.startswith("candelabra_")], key=lambda o: o.name)
    check([o.name for o in emp] == [f"candelabra_{i}" for i in range(4)], "empties candelabra_0..3")
    if altar:
        alo, ahi = bbox(altar)
    for o in emp:
        p = o.matrix_world.translation
        corner = Vector((math.copysign(ahi.x, p.x), math.copysign(ahi.y, p.y), FLOOR)) if altar else p
        d = (p.xy - corner.xy).length
        diag = (p.x * corner.x > 0) and (p.y * corner.y > 0) and abs(abs(p.x) - abs(p.y)) < 0.05
        check(abs(p.z - FLOOR) < 1e-3 and 0.9 < d < 1.5 and diag,
              f"{o.name} on floor, {d:.2f} m diagonally outside the altar corner")
    check(total <= BUDGET["board"], f"board+altar tris {total} <= {BUDGET['board']}")
    return [(o.name, o.matrix_world.copy()) for o in emp]


# ------------------------------------------------------------------------------------------------ candelabra

def verify_candelabra():
    objs = load(GLB_CANDLE)
    total = report(objs, "candelabra.glb")
    meshes = [o for o in objs if o.type == 'MESH']
    check([o.name for o in meshes] == ["candelabra"], "one mesh object 'candelabra'")
    flames = {}
    if meshes:
        o = meshes[0]
        check([m.name for m in o.data.materials] == ["iron", "candle_wax", "candle_flame"],
              "slots == ['iron', 'candle_wax', 'candle_flame']")
        ca = o.data.color_attributes
        check(has_ao(o), "active vertex colour (COLOR_0 = baked 'ao') carries occlusion")
        lo, hi = bbox(o)
        feet = [v for v in world_verts(o) if v.z < lo.z + 0.03]
        fc = sum((v for v in feet), Vector()) / len(feet)
        check(abs(lo.z) < 0.01 and fc.xy.length < 0.05,
              f"origin at bottom centre (min z {lo.z:.3f}, feet centroid {fc.x:.3f}, {fc.y:.3f})")
        check(1.8 <= hi.z <= 2.3, f"height {hi.z:.3f} m (~2.0)")
    emp = sorted([o for o in objs if o.type == 'EMPTY' and o.name.startswith("flame_")], key=lambda o: o.name)
    check([o.name for o in emp] == ["flame_0", "flame_1", "flame_2"], "empties flame_0..2")
    for o in emp:
        z = o.matrix_world.translation.z + FLOOR
        check(0.6 <= z <= 0.9, f"{o.name} sits {z:.3f} m above the board when on the floor (0.6..0.9)")
    check(total <= BUDGET["candelabra"], f"candelabra tris {total} <= {BUDGET['candelabra']}")
    return objs


# ------------------------------------------------------------------------------------------------ environment

def verify_environment(spots):
    objs = load(GLB_ENV)
    total = report(objs, "environment.glb")
    meshes = [o for o in objs if o.type == 'MESH']
    allowed = set(C.ENV_MATS)
    for o in meshes:
        names = [m.name for m in o.data.materials]
        check(set(names) <= allowed, f"{o.name} slots {names} within the allowed set")
        ca = o.data.color_attributes
        check(has_ao(o), f"{o.name} active vertex colour (COLOR_0 = baked 'ao') carries occlusion")
    check(total <= BUDGET["environment"], f"environment tris {total} <= {BUDGET['environment']}")

    floor = next((o for o in meshes if o.name == "env_floor"), None)
    if floor:
        lo, hi = bbox(floor)
        print(f"  info: env_floor extent {hi.x - lo.x:.1f} x {hi.y - lo.y:.1f} m, depth {FLOOR - lo.z:.1f} m")
    # clear zone: altar footprint + 1.5 m ring
    clear = 5.25 + 1.5
    intr = []
    for o in meshes:
        for v in world_verts(o):
            if abs(v.x) < clear and abs(v.y) < clear and v.z > FLOOR + 1e-4:
                intr.append((o.name, round(v.x, 2), round(v.y, 2), round(v.z, 4)))
    check(not intr, f"nothing above the floor plane z = {FLOOR} inside |x|,|y| < {clear} m "
                    f"(altar footprint + 1.5 m ring; {len(intr)} verts) {intr[:3]}")
    if floor:
        ring = [v.z for v in world_verts(floor) if abs(v.x) < clear and abs(v.y) < clear and v.z > FLOOR - 0.02]
        print(f"  info: floor tile tops in the clear zone z {min(ring):.4f} .. {max(ring):.4f}")
    bvh = bvh_of(meshes)
    for name, mw in spots:
        p = mw.translation
        hit = bvh.ray_cast(Vector((p.x, p.y, FLOOR + 3.0)), Vector((0, 0, -1)), 6.0) if bvh else (None,)
        ok = hit[0] is not None and abs(hit[0].z - FLOOR) < 0.02
        crowd = [v for o in meshes if o.name != "env_floor" for v in world_verts(o)
                 if (v.xy - p.xy).length < 0.7 and v.z < FLOOR + 2.4]
        check(ok and not crowd, f"{name} spot: floor at z = {hit[0].z if hit[0] else None}, "
                                f"nothing within 0.7 m ({len(crowd)} verts)")

    moon = next((o for o in objs if o.type == 'EMPTY' and o.name.startswith("moon_dir")), None)
    check(moon is not None, "empty moon_dir present")
    light = None
    if moon:
        light = (moon.matrix_world.to_3x3() @ Vector((0, 0, -1))).normalized()
        to_moon = -light
        el = math.degrees(math.asin(to_moon.z))
        az = math.degrees(math.atan2(-to_moon.x, to_moon.y))
        print(f"  info: moon_dir -Z = {fmt(light)}; moon elevation {el:.1f} deg, {az:.1f} deg left of +Y")
        check(light.z < 0 and to_moon.y > 0 and to_moon.x < 0 and el < 35,
              "moon low, behind-left of the rose window (+Y side, -X) as seen from the game camera")
    return objs, meshes, bvh, light


def place_candelabras(spots):
    out = []
    for name, mw in spots:
        new = load_into(GLB_CANDLE)
        for o in new:
            if o.parent is None:
                o.matrix_world = mw @ o.matrix_world
        out += new
    bpy.context.view_layer.update()
    return [o for o in out if o.type == 'MESH']


def load_into(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def visibility(meshes, spots, light):
    print("\n=== game camera / moon checks (environment + 4 candelabras)")
    cands = place_candelabras(spots)
    bvh = bvh_of(meshes + cands)
    blocked, samples = [], 0
    for f in range(8):
        for r in range(8):
            for dx, dy in ((0, 0), (-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)):
                p = Vector((-3.5 + f + dx, -3.5 + r + dy, 0.0))
                d = p - GAME_CAM
                hit = bvh.ray_cast(GAME_CAM, d.normalized(), d.length - 0.01)
                samples += 1
                if hit[0] is not None:
                    blocked.append((f, r))
    check(not blocked, f"game camera sees all 64 squares unobstructed ({samples} rays, {len(blocked)} blocked)")
    # menu orbit: 24 positions on r=14, h=7, rays to the 64 square centres
    env_only = bvh_of(meshes)
    ob = oe = 0
    total = 0
    for k in range(24):
        a = 2 * math.pi * k / 24
        cam = Vector((ORBIT_R * math.cos(a), ORBIT_R * math.sin(a), ORBIT_Z))
        for f in range(8):
            for r in range(8):
                p = Vector((-3.5 + f, -3.5 + r, 0.0))
                d = p - cam
                total += 1
                if bvh.ray_cast(cam, d.normalized(), d.length - 0.01)[0] is not None:
                    ob += 1
                    if env_only.ray_cast(cam, d.normalized(), d.length - 0.01)[0] is not None:
                        oe += 1
    print(f"  info: menu orbit (24 stops, r={ORBIT_R}, h={ORBIT_Z}): {ob}/{total} square-centre rays blocked "
          f"({100.0 * ob / total:.1f} %; {oe} by the environment, {ob - oe} by the candelabras)")
    if light is not None:
        shaded = 0
        for f in range(8):
            for r in range(8):
                p = Vector((-3.5 + f, -3.5 + r, 0.01))
                if bvh.ray_cast(p, -light, 200.0)[0] is not None:
                    shaded += 1
        print(f"  info: {shaded}/64 square centres in moon shadow from the environment/candelabras")


def main():
    spots = verify_board()
    verify_candelabra()
    objs, meshes, bvh, light = verify_environment(spots)
    visibility(meshes, spots, light)
    print("\n=== RESULT:", "ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILED")
    for f in failures:
        print("  -", f)
    sys.stdout.flush()
    if failures:
        os._exit(1)


if __name__ == "__main__":
    main()
