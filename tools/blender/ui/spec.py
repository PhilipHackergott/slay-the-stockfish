"""UI kit contract: files, sizes, nine-slice margins, content padding, post steps.

Pure Python, shared by build_ui.py (Blender renders the raw 2x images), post.py (Pillow: downscale, glow, states,
kit.json) and compose.py (sheet + mock). Margins/content are [left, top, right, bottom] in texture pixels.
Every file is rendered under its own name unless `raw` names another render (derived files).
"""

SOUL = (0x6f, 0xb8, 0xff)
EMBER = (0xff, 0x7a, 0x33)
GOLD = (0xf0, 0xc0, 0x60)

FILES = {}


def add(name, size, margin=(0, 0, 0, 0), content=(0, 0, 0, 0), raw=None, post=(), **extra):
    FILES[name] = dict(file=name + ".png", size=list(size), margin=list(margin), content=list(content),
                       raw=raw or name, post=list(post), extra=extra)


def m4(v):
    return (v, v, v, v)


# ---- frames and panels
add("panel", (512, 512), m4(104), m4(72), post=[("selfbloom", 0.55, 0.5, 4)])
add("modal", (1024, 1024), m4(176), m4(112), post=[("selfbloom", 0.55, 0.5, 5)])
add("modal_crest", (384, 160), post=[("selfbloom", 0.55, 0.6, 5)])
add("title_plaque", (768, 128), (112, 50, 112, 50), (104, 30, 104, 30), post=[("selfbloom", 0.55, 0.5, 4)])
add("tooltip", (256, 256), m4(26), (20, 16, 20, 16))

# ---- reward card (bone frame); the glow halo stays inside the 12 px padding
CARD = dict(margin=m4(72), content=m4(58))
add("card", (384, 544), **CARD)
add("card_hover", (384, 544), **CARD, post=[("bloom", "card", 0.85, 3, 6), ("halo", SOUL, 9, 0.6)])
add("card_pressed", (384, 544), **CARD, post=[("bloom", "card", 0.85, 3, 6), ("halo", EMBER, 9, 0.6)])
add("card_disabled", (384, 544), **CARD, post=[("desat", 0.85, 0.38)])

# ---- buttons
BTN = dict(margin=(60, 30, 60, 30), content=(64, 16, 64, 16))
for pre in ("button", "button_primary"):
    add(pre + "_normal", (384, 96), **BTN, post=[("selfbloom", 0.7, 0.4, 4)] if pre == "button_primary" else [])
    add(pre + "_hover", (384, 96), **BTN, post=[("bloom", pre + "_normal", 1.0, 2, 7)])
    add(pre + "_pressed", (384, 96), **BTN, post=[("bloom", pre + "_normal", 1.0, 2, 7)])
    add(pre + "_disabled", (384, 96), **BTN, post=[("desat", 0.8, 0.3)])

# ---- ornaments
add("divider", (1024, 64), post=[("selfbloom", 0.55, 0.6, 4)])
add("divider_small", (512, 40), post=[("selfbloom", 0.55, 0.6, 3)])

# ---- portraits and map
MED = dict(content=m4(36), hole_radius=92)
add("medallion_player", (256, 256), **MED, post=[("selfbloom", 0.5, 0.8, 5), ("hole", 92)])
add("medallion_engine", (256, 256), **MED, post=[("selfbloom", 0.5, 0.8, 5), ("hole", 92)])
RING = dict(content=m4(31), hole_radius=65)
add("node_ring", (192, 192), **RING, post=[("hole", 65)])
add("node_ring_available", (192, 192), **RING, post=[("bloom", "node_ring", 1.2, 3, 9), ("hole", 65)])
add("node_ring_visited", (192, 192), **RING, post=[("desat", 0.7, 0.35), ("hole", 65)])

# ---- slots
SLOT = dict(margin=m4(32), content=m4(24))
add("slot", (128, 128), **SLOT)
add("slot_hover", (128, 128), **SLOT, post=[("bloom", "slot", 1.0, 2, 6)])
add("slot_selected", (128, 128), **SLOT, post=[("bloom", "slot", 1.0, 2, 6)])

# ---- bars and scrolling
add("bar_frame", (512, 48), (28, 16, 28, 16), (24, 14, 24, 14))
for c in ("soul", "ember", "gold"):
    add("bar_fill_" + c, (256, 24), (12, 0, 12, 0), post=[("selfbloom", 0.35, 0.7, 3)])
add("scroll_track", (32, 256), (10, 24, 10, 24), (8, 16, 8, 16))
add("scroll_grabber", (32, 128), (10, 30, 10, 30), (8, 20, 8, 20))
add("scroll_grabber_hover", (32, 128), (10, 30, 10, 30), (8, 20, 8, 20),
    post=[("bloom", "scroll_grabber", 1.0, 2, 5)])
add("slider_track", (512, 32), (26, 10, 26, 10), (24, 12, 24, 12))
add("slider_grabber", (48, 48))
add("slider_grabber_hover", (48, 48), post=[("bloom", "slider_grabber", 1.2, 2, 5)])

# ---- small widgets
add("check_off", (64, 64), content=m4(16))
add("check_on", (64, 64), content=m4(16), post=[("bloom", "check_off", 1.2, 2, 6)])
add("close", (64, 64), content=m4(16))
add("close_hover", (64, 64), content=m4(16), post=[("bloom", "close", 0.9, 2, 5)])
add("coin", (128, 128), post=[("selfbloom", 0.8, 0.3, 3)])
add("coin_small", (48, 48), raw="coin", post=[("resize", 48, 48)])
add("cursor", (48, 48), hotspot=[3, 3])
add("cursor_point", (48, 48), hotspot=[8, 2])
add("menu_marker", (64, 64), post=[("selfbloom", 0.45, 1.0, 4)])

# ---- tileable fill
add("bg_slate", (512, 512), tile=True)
