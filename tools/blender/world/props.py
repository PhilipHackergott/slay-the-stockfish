"""Prop line-up render (like the prop sheet): arch, pillar, rose window, chain, candelabra, tree, gravestones, crow.

Usage: run.sh props.py 600 -- [--fast] [--only rose]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common as C  # noqa: E402
import env_kit as K  # noqa: E402
import preview as P  # noqa: E402
from env_kit import M  # noqa: E402


def add(bm, name, matrix):
    C.transform(bm, matrix)
    o = C.bm_to_obj(bm, name, C.ENV_MATS)
    C.finish(o, sharp_deg=42, uv=False)
    return o


def main():
    args = C.script_args()
    fast = "--fast" in args
    only = args[args.index("--only") + 1] if "--only" in args else None
    C.reset()
    rng = random.Random(77)
    s = 0.36  # the rose window is shown at reduced scale so it fits the sheet
    items = []
    if only in (None, "rose"):
        rw, _ = K.rose_window(rng)
        items.append(add(rw, "rose", M((0, 0, 0), 0, s=s if only is None else 1.0)))
    if only is None:
        a, _ = K.arch_fragment(rng, bays=1, span=3.0, spring=3.2, broken_right=0)
        items.append(add(a, "arch", M((-6.5, 0, 0), 0, s=0.5)))
        p, _ = K.broken_pillar(rng, 4.2, 0.9)
        items.append(add(p, "pillar", M((-3.6, 0, 0), 0.3, s=0.5)))
        items.append(add(K.rubble(rng, 14, 1.5, size=(0.12, 0.4)), "rubble", M((-3.6, 0, 0), 0, s=0.5)))
        items.append(add(K.hanging_chain(rng, 3.6, 0.9, hook=True), "chain", M((3.3, 0, 0), 0, s=0.8)))
        t = K.dead_tree(random.Random(5), 6.0, depth=4)
        items.append(add(t, "tree", M((6.0, 0.5, 0), 0, s=0.45)))
        for i, kind in enumerate(("round", "gothic", "celtic", "cross", "slab")):
            g = K.gravestone(rng, kind)
            items.append(add(g, "grave", M((-6.6 + i * 1.05, -3.4, 0), rng.uniform(-0.15, 0.15),
                                           rx=rng.uniform(-0.1, 0.1), s=0.8)))
        items.append(add(K.bone_pile(rng, 4), "bones", M((-1.2, -3.4, 0), 0, s=1.0)))
        c = K.crow(rng, "perch", 0.3)
        items.append(add(c, "crow", M((3.4, -3.2, 0), -0.6, s=2.2)))
        c2 = K.crow(rng, "spread", -0.3)
        items.append(add(c2, "crow2", M((5.0, -3.2, 0), 0.5, s=2.2)))
        cand = P.import_glb(P.GLB_CANDLE)
        for o in cand:
            if o.parent is None:
                o.location = (0.5, -3.0, 0)
                o.scale = (0.9, 0.9, 0.9)
        flames = [o for o in cand if o.name.startswith("flame_")]
    else:
        flames = []
    # ground slab
    gnd = C.bm_to_obj(C.box(40, 40, 0.1, center=(0, 0, -0.05)), "_ground", ["stone_dark"])
    C.bake_ao(items + [gnd], samples=16, distance=0.8)
    P.build_materials()
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.065, 0.1, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    key_d = bpy.data.lights.new("key", 'SUN')
    key_d.energy = 2.2
    key_d.color = (0.75, 0.78, 1.0)
    key = bpy.data.objects.new("key", key_d)
    key.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(key)
    bpy.context.view_layer.update()
    for f in flames:
        ld = bpy.data.lights.new("c", 'POINT')
        ld.energy = 6
        ld.color = (1.0, 0.55, 0.2)
        lo = bpy.data.objects.new("c", ld)
        lo.location = f.matrix_world.translation
        sc.collection.objects.link(lo)
    P.render_settings(fast)
    sc.view_settings.exposure = 0.3
    if only == "rose":
        cam = P.camera("cam", (3, -16, 5), (0, 0, 5.5), 50)
        out = "props_rose.png"
    else:
        cam = P.camera("cam", (0.0, -14.5, 6.2), (0.0, -1.0, 1.3), 34)
        out = "props.png"
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.render.resolution_percentage = 50 if fast else 100
    sc.render.filepath = os.path.join(C.BUILD, out)
    bpy.ops.render.render(write_still=True)
    C.log("rendered", sc.render.filepath)


if __name__ == "__main__":
    main()
