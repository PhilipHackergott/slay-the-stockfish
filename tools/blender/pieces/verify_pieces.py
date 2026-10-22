"""Contract check for models/pieces/*.glb: re-import into a fresh scene and read the raw glTF.

Blender --background --factory-startup --python verify_pieces.py   (exit code 1 on any failure)
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import anims  # noqa: E402
import common as C  # noqa: E402

CLIPS = anims.DURATIONS
REQUIRED_MATS = {"piece_body", "piece_glow"}
ALLOWED_MATS = {"piece_body", "piece_trim", "piece_glow"}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    _magic, _ver, _length = struct.unpack_from("<III", data, 0)
    jlen, _jtype = struct.unpack_from("<II", data, 12)
    gl = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _btype = struct.unpack_from("<II", data, off)
    return gl, data[off + 8:off + 8 + blen]


def accessor(gl, blob, idx):
    acc = gl["accessors"][idx]
    view = gl["bufferViews"][acc["bufferView"]]
    n = COMPONENTS[acc["type"]]
    stride = view.get("byteStride", 4 * n)
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [struct.unpack_from("<%df" % n, blob, base + i * stride) for i in range(acc["count"])]


def quat_angle(q):
    return math.degrees(2 * math.acos(max(-1.0, min(1.0, abs(q[3])))))


def pose(gl, blob, anim, which):
    """translation, rotation angle (deg), scale at the first (0) or last (-1) key, glTF Y-up."""
    out = {}
    for ch in anim["channels"]:
        smp = anim["samplers"][ch["sampler"]]
        vals = accessor(gl, blob, smp["output"])
        out[ch["target"]["path"]] = vals[which]
    return out


def near(a, b, tol):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def expected_ends(clip, h):
    rest = ((0, 0, 0), 0.0, (1, 1, 1))
    return {
        "move": (rest, rest),
        "leap": (rest, rest),
        "capture": (rest, ((0, -h, 0), None, (0.6, 0.6, 0.6))),
        "drop": (((0, 2.2, 0), 90.0, (1, 1, 1)), rest),
        "spawn": (((0, -h, 0), 0.0, (0.8, 0.8, 0.8)), rest),
    }[clip]


def check_glb(name, path, rows):
    gl, blob = read_glb(path)
    ok = True

    def row(check, passed, detail):
        nonlocal ok
        ok &= bool(passed)
        rows.append((name, check, "PASS" if passed else "FAIL", detail))

    mesh_nodes = [n for n in gl["nodes"] if "mesh" in n]
    row("glb: one mesh node", len(mesh_nodes) == 1 and len(gl["meshes"]) == 1,
        "%d nodes, %d meshes" % (len(mesh_nodes), len(gl["meshes"])))
    node = mesh_nodes[0]
    row("glb: node/mesh name", node.get("name") == name and gl["meshes"][0].get("name") == name,
        "%s / %s" % (node.get("name"), gl["meshes"][0].get("name")))
    rest = node.get("translation", [0, 0, 0]), node.get("rotation", [0, 0, 0, 1]), node.get("scale", [1, 1, 1])
    row("glb: node at rest", near(rest[0], (0, 0, 0), 1e-5) and near(rest[1], (0, 0, 0, 1), 1e-5)
        and near(rest[2], (1, 1, 1), 1e-5), "T%s R%s S%s" % tuple(rest))
    mats = [m["name"] for m in gl.get("materials", [])]
    row("glb: material names", REQUIRED_MATS <= set(mats) and set(mats) <= ALLOWED_MATS, ",".join(mats))
    attrs = set()
    for prim in gl["meshes"][0]["primitives"]:
        attrs |= set(prim["attributes"])
    row("glb: attributes", {"POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0"} <= attrs, ",".join(sorted(attrs)))
    names = sorted(a["name"] for a in gl.get("animations", []))
    row("glb: animation names", names == sorted(CLIPS), ",".join(names))
    h = C.HEIGHTS[name]
    for anim in gl.get("animations", []):
        clip = anim["name"]
        if clip not in CLIPS:
            continue
        paths = sorted(ch["target"]["path"] for ch in anim["channels"])
        t_end = max(accessor(gl, blob, s["input"])[-1][0] for s in anim["samplers"])
        t0 = min(accessor(gl, blob, s["input"])[0][0] for s in anim["samplers"])
        first, last = pose(gl, blob, anim, 0), pose(gl, blob, anim, -1)
        exp0, exp1 = expected_ends(clip, h)
        good = paths == ["rotation", "scale", "translation"] and abs(t0) < 1e-6 and abs(t_end - CLIPS[clip]) < 1e-3
        for got, exp in ((first, exp0), (last, exp1)):
            good &= near(got["translation"], exp[0], 2e-3)
            good &= exp[1] is None or abs(quat_angle(got["rotation"]) - exp[1]) < 0.5
            good &= near(got["scale"], exp[2], 2e-3)
        row("anim %-7s" % clip, good, "%.3fs  %s  start T%s end T%s S%s" % (
            t_end, "/".join(paths), tuple(round(v, 3) for v in first["translation"]),
            tuple(round(v, 3) for v in last["translation"]), tuple(round(v, 2) for v in last["scale"])))
    return ok


def check_import(name, path, rows):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    ok = True

    def row(check, passed, detail):
        nonlocal ok
        ok &= bool(passed)
        rows.append((name, check, "PASS" if passed else "FAIL", detail))

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    row("import: one mesh object", len(meshes) == 1 and len(bpy.data.objects) == 1,
        "%d objects, %d meshes" % (len(bpy.data.objects), len(meshes)))
    ob = meshes[0]
    row("import: object name", ob.name == name, ob.name)
    mats = {s.material.name.split(".")[0] for s in ob.material_slots if s.material}
    row("import: materials", REQUIRED_MATS <= mats <= ALLOWED_MATS, ",".join(sorted(mats)))
    tracks = sorted(t.name for t in ob.animation_data.nla_tracks) if ob.animation_data else []
    row("import: NLA tracks", tracks == sorted(CLIPS), ",".join(tracks))
    # The importer leaves the object posed at the first frame of an action; the node rest
    # transform is checked as identity in check_glb, so measure in mesh space.
    me = ob.data
    vs = [v.co for v in me.vertices]
    zmin = min(v.z for v in vs)
    zmax = max(v.z for v in vs)
    h = zmax - zmin
    target = C.HEIGHTS[name]
    row("import: height", abs(h - target) <= 0.05 * target and abs(zmin) < 1e-3,
        "%.3f m (target %.2f, min z %.4f)" % (h, target, zmin))
    low = [v for v in vs if v.z < 0.06]
    dia = 2 * max(math.hypot(v.x, v.y) for v in low)
    row("import: base diameter", 0.70 <= dia <= 0.78, "%.3f m" % dia)
    bottom = [v for v in vs if v.z < 0.002]
    cx = (min(v.x for v in bottom) + max(v.x for v in bottom)) / 2
    cy = (min(v.y for v in bottom) + max(v.y for v in bottom)) / 2
    row("import: origin bottom centre", abs(cx) < 0.003 and abs(cy) < 0.003, "bottom face centre (%.4f, %.4f)" % (cx, cy))
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    row("import: triangles", 3000 <= tris <= 15000, str(tris))
    row("import: uv + colour", len(me.uv_layers) > 0 and len(me.color_attributes) > 0,
        "uv %s, colour %s" % ([u.name for u in me.uv_layers], [c.name for c in me.color_attributes]))
    return ok


def main():
    rows = []
    ok = True
    for name in C.PIECES:
        path = os.path.join(C.MODELS, name + ".glb")
        if not os.path.exists(path):
            rows.append((name, "file", "FAIL", path))
            ok = False
            continue
        ok &= check_glb(name, path, rows)
        ok &= check_import(name, path, rows)
    w = max(len(r[1]) for r in rows)
    print("\nVERIFY TABLE")
    for r in rows:
        print("%-7s %-*s %s  %s" % (r[0], w, r[1], r[2], r[3]))
    print("VERIFY %s (%d checks, %d failed)" % ("OK" if ok else "FAILED", len(rows),
                                                sum(r[2] == "FAIL" for r in rows)))
    with open(os.path.join(C.BUILD, "verify.txt"), "w") as fh:
        for r in rows:
            fh.write("%-7s %-*s %s  %s\n" % (r[0], w, r[1], r[2], r[3]))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
