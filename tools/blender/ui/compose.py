"""Kit previews from the final textures in assets/ui/kit.

python compose.py                 -> build/ui/kit_sheet.png and build/ui/mock_reward.png
python compose.py preview a b ... -> build/ui/preview.png (those files over a dark background, 1:1)
Nine-slicing here works like Godot's StyleBoxTexture (stretch, linear filter) in premultiplied space.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
KIT = os.path.join(ROOT, "assets", "ui", "kit")
OUT = os.path.join(ROOT, "build", "ui")
FONTS = os.path.join(ROOT, "assets", "fonts")
BG = (13, 12, 16, 255)
BONE_TXT = (226, 208, 172)
DIM_TXT = (168, 156, 140)
GOLD_TXT = (240, 196, 104)


def tex(name):
    return Image.open(os.path.join(KIT, spec.FILES[name]["file"])).convert("RGBA")


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def pm(im):
    a = np.asarray(im.convert("RGBA"), np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def unpm(a):
    al = np.clip(a[..., 3:4], 0, 1)
    rgb = np.where(al > 1e-4, a[..., :3] / np.maximum(al, 1e-4), 0.0)
    return Image.fromarray((np.concatenate([np.clip(rgb, 0, 1), al], 2) * 255 + 0.5).astype(np.uint8), "RGBA")


def resize(a, w, h, flt=Image.BILINEAR):
    if a.shape[1] == w and a.shape[0] == h:
        return a
    ch = [np.asarray(Image.fromarray(a[..., c], "F").resize((w, h), flt), np.float32) for c in range(4)]
    return np.stack(ch, 2)


def nine(name, w, h):
    """Premultiplied nine-slice of a kit texture to w x h (corners 1:1, edges and centre stretched)."""
    a = pm(tex(name))
    H, W = a.shape[:2]
    l, t, r, b = spec.FILES[name]["margin"]
    xs = [(0, l, l), (l, W - r, w - l - r), (W - r, W, r)]
    ys = [(0, t, t), (t, H - b, h - t - b), (H - b, H, b)]
    out = np.zeros((h, w, 4), np.float32)
    dy = 0
    for y0, y1, dh in ys:
        dx = 0
        for x0, x1, dw in xs:
            if dw > 0 and dh > 0 and x1 > x0 and y1 > y0:
                out[dy:dy + dh, dx:dx + dw] = resize(a[y0:y1, x0:x1], dw, dh)
            dx += dw
        dy += dh
    return out


class Canvas:
    def __init__(self, w, h, bg=BG):
        self.a = np.zeros((h, w, 4), np.float32)
        self.a[...] = np.array(bg, np.float32) / 255.0

    def put(self, src, x, y):
        """Premultiplied over; src is an array or a PIL image."""
        if isinstance(src, Image.Image):
            src = pm(src)
        x, y = int(round(x)), int(round(y))
        h, w = src.shape[:2]
        H, W = self.a.shape[:2]
        sx0, sy0 = max(0, -x), max(0, -y)
        dx0, dy0 = max(0, x), max(0, y)
        dx1, dy1 = min(W, x + w), min(H, y + h)
        if dx1 <= dx0 or dy1 <= dy0:
            return
        s = src[sy0:sy0 + dy1 - dy0, sx0:sx0 + dx1 - dx0]
        d = self.a[dy0:dy1, dx0:dx1]
        self.a[dy0:dy1, dx0:dx1] = s + d * (1.0 - s[..., 3:4])

    def put_c(self, src, cx, cy):
        h, w = (src.shape[:2] if not isinstance(src, Image.Image) else (src.height, src.width))
        self.put(src, cx - w / 2, cy - h / 2)

    def text(self, xy, s, fnt, fill, anchor="la", shadow=True, glow=None):
        W, H = self.a.shape[1], self.a.shape[0]
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        if glow:
            g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(g).text(xy, s, font=fnt, fill=glow, anchor=anchor)
            self.put(g.filter(ImageFilter.GaussianBlur(6)), 0, 0)
        if shadow:
            sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(sh).text((xy[0] + 1, xy[1] + 2), s, font=fnt, fill=(0, 0, 0, 220), anchor=anchor)
            self.put(sh.filter(ImageFilter.GaussianBlur(1.5)), 0, 0)
        d.text(xy, s, font=fnt, fill=fill, anchor=anchor)
        self.put(layer, 0, 0)

    def save(self, path):
        unpm(self.a).convert("RGB").save(path)


def scaled(name, w, h=None, flt=Image.LANCZOS):
    im = tex(name)
    h = h or round(im.height * w / im.width)
    return pm(im.resize((w, h), flt))


def portrait(medal, piece, size, tint):
    """Medallion `medal` scaled to `size` with a portrait inside its hole."""
    hole = spec.FILES[medal]["extra"]["hole_radius"] * size / spec.FILES[medal]["size"][0]
    yy, xx = np.mgrid[0:size, 0:size]
    rr = np.hypot(xx + 0.5 - size / 2, yy + 0.5 - size / 2)
    disc = np.zeros((size, size, 4), np.float32)
    k = np.clip(1 - rr / (hole + 2), 0, 1)
    col = np.array(tint, np.float32) / 255.0
    disc[..., :3] = (0.03 + col[None, None, :] * 0.22 * k[..., None] ** 1.5)
    disc[..., 3] = 1.0
    p = Image.open(os.path.join(ROOT, "art", "portraits", piece + ".png")).convert("RGBA")
    c = p.width * 0.19
    p = p.crop((c, c * 0.7, p.width - c, p.height - c * 1.3)).resize((size, size), Image.LANCZOS)
    pa = pm(p)
    out = pa + disc * (1 - pa[..., 3:4])
    out *= np.clip(hole + 2 - rr, 0, 1)[..., None]
    ring = pm(tex(medal).resize((size, size), Image.LANCZOS))
    return ring + out * (1 - ring[..., 3:4])


def background(W, H):
    im = Image.open(os.path.join(ROOT, "build", "shots", "final_title.png")).convert("RGB")
    s = max(W / im.width, H / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    im = im.crop(((im.width - W) // 2, (im.height - H) // 2, (im.width - W) // 2 + W, (im.height - H) // 2 + H))
    im = im.filter(ImageFilter.GaussianBlur(7))
    a = np.asarray(im, np.float32) / 255.0
    yy, xx = np.mgrid[0:H, 0:W]
    v = 1 - 0.55 * np.clip(np.hypot((xx - W / 2) / (W * 0.62), (yy - H / 2) / (H * 0.62)), 0, 1) ** 2
    a = a * 0.42 * v[..., None]
    out = np.ones((H, W, 4), np.float32)
    out[..., :3] = a
    return out


def mock_reward():
    W, H = 1920, 1080
    cv = Canvas(W, H)
    cv.a = background(W, H)
    cinzel = lambda s: font("Cinzel.ttf", s)
    garamond = lambda s: font("EBGaramond.ttf", s)

    # HUD: opponent top left, coins top right
    cv.put(nine("panel", 420, 150), 120, 18)
    cv.put_c(portrait("medallion_engine", "engine_queen", 150, (255, 122, 51)), 96, 93)
    cv.text((196, 52), "THE BLACK QUEEN", cinzel(24), BONE_TXT)
    cv.put(nine("bar_frame", 236, 34), 190, 92)
    cl, _, cr, _ = spec.FILES["bar_frame"]["content"]
    cv.put(nine("bar_fill_ember", round((236 - cl - cr) * 0.62), 20), 190 + cl, 99)
    cv.text((436, 109), "31", garamond(22), DIM_TXT, anchor="lm")
    cv.put(nine("panel", 250, 112), W - 272, 18)
    cv.put_c(scaled("coin", 64), W - 210, 74)
    cv.text((W - 166, 74), "42", cinzel(42), GOLD_TXT, anchor="lm")

    # modal
    mw, mh = 1180, 830
    mx, my = (W - mw) // 2, 150
    cv.put(nine("modal", mw, mh), mx, my)
    cv.put(nine("title_plaque", 640, 104), W / 2 - 320, my + 60)
    cv.text((W / 2, my + 112), "SPOILS OF VICTORY", cinzel(40), BONE_TXT, anchor="mm")
    cv.put_c(pm(tex("modal_crest")), W / 2, my - 8)
    cv.text((W / 2, my + 188), "Claim one piece for your army", garamond(26), DIM_TXT, anchor="mm")
    cv.put_c(pm(tex("divider_small")), W / 2, my + 222)

    cards = [("player_rook", "ROOK", "Fortress", "Slides along ranks and files. Holds 2 souls.", 18),
             ("player_knight", "KNIGHT", "Charger", "Leaps over pieces. First strike deals +1.", 15),
             ("player_bishop", "BISHOP", "Zealot", "Diagonal lines. Heals adjacent allies by 1.", 12)]
    cw, ch, gap = 300, 420, 28
    cy = my + 248
    x0 = W / 2 - (3 * cw + 2 * gap) / 2
    for i, (piece, name, kind, desc, cost) in enumerate(cards):
        x = x0 + i * (cw + gap)
        state = "card_hover" if i == 1 else "card"
        cv.put(nine(state, cw, ch), x, cy)
        cv.put_c(portrait("medallion_player", piece, 164, (111, 184, 255)), x + cw / 2, cy + 112)
        cv.text((x + cw / 2, cy + 218), name, cinzel(30), BONE_TXT, anchor="mm",
                glow=(111, 184, 255, 150) if i == 1 else None)
        cv.text((x + cw / 2, cy + 248), kind, garamond(20), (150, 172, 196) if i == 1 else DIM_TXT, anchor="mm")
        words, lines, cur = desc.split(), [], ""
        for w_ in words:
            if garamond(20).getlength(cur + " " + w_) > cw - 90 and cur:
                lines.append(cur)
                cur = w_
            else:
                cur = (cur + " " + w_).strip()
        lines.append(cur)
        for j, ln in enumerate(lines):
            cv.text((x + cw / 2, cy + 280 + j * 24), ln, garamond(20), (196, 186, 170), anchor="mm")
        cv.put_c(pm(tex("coin_small")), x + cw / 2 - 22, cy + ch - 62)
        cv.text((x + cw / 2 + 6, cy + ch - 62), str(cost), cinzel(26), GOLD_TXT, anchor="lm")

    by = my + mh - 168
    cv.put(nine("button_primary_hover", 300, 72), W / 2 - 316, by)
    cv.text((W / 2 - 166, by + 36), "RECRUIT", cinzel(28), (250, 226, 200), anchor="mm")
    cv.put(nine("button_normal", 300, 72), W / 2 + 16, by)
    cv.text((W / 2 + 166, by + 36), "SKIP", cinzel(28), BONE_TXT, anchor="mm")

    cv.put(pm(tex("cursor_point")), x0 + cw + gap + 196 - 9, cy + 330 - 3)
    cv.save(os.path.join(OUT, "mock_reward.png"))


SHEET_GROUPS = [
    ("frames", ["panel", "modal", "tooltip", "modal_crest", "title_plaque"]),
    ("cards", ["card", "card_hover", "card_pressed", "card_disabled"]),
    ("buttons", ["button_normal", "button_hover", "button_pressed", "button_disabled", "button_primary_normal",
                 "button_primary_hover", "button_primary_pressed", "button_primary_disabled"]),
    ("ornaments", ["divider", "divider_small", "medallion_player", "medallion_engine", "node_ring",
                   "node_ring_available", "node_ring_visited"]),
    ("widgets", ["slot", "slot_hover", "slot_selected", "bar_frame", "bar_fill_soul", "bar_fill_ember",
                 "bar_fill_gold", "scroll_track", "scroll_grabber", "scroll_grabber_hover", "slider_track",
                 "slider_grabber", "slider_grabber_hover", "check_off", "check_on", "close", "close_hover", "coin",
                 "coin_small", "cursor", "cursor_point", "menu_marker"]),
]


def kit_sheet():
    W, pad = 2600, 28
    lab = font("EBGaramond.ttf", 17)
    head = font("Cinzel.ttf", 26)
    items = []
    x, y, rh = pad, pad + 40, 0
    for title, names in SHEET_GROUPS:
        items.append(("head", title, pad, y - 36))
        for n in names:
            im = tex(n)
            if x + im.width + pad > W and x > pad:
                x, y, rh = pad, y + rh + pad + 24, 0
            items.append(("img", n, x, y))
            x += max(im.width, round(lab.getlength(f"{n} {im.width}x{im.height}"))) + pad
            rh = max(rh, im.height)
        x, y, rh = pad, y + rh + pad + 24 + 44, 0
    # stretch tests at large sizes plus the tiling fill
    items.append(("head", "stretched (nine-slice) + bg_slate 2x2 tile", pad, y - 36))
    tests = [("panel", 900, 300), ("modal", 1180, 520), ("card", 300, 420), ("button_primary_normal", 520, 72),
             ("button_normal", 220, 64), ("tooltip", 420, 120), ("bar_frame", 700, 40), ("title_plaque", 1100, 100),
             ("slot", 220, 96), ("scroll_track", 32, 420)]
    for n, w, h in tests:
        if x + w + pad > W and x > pad:
            x, y, rh = pad, y + rh + pad + 24, 0
        items.append(("nine", (n, w, h), x, y))
        x += w + pad
        rh = max(rh, h)
    if x + 1024 + pad > W:
        x, y, rh = pad, y + rh + pad + 24, 0
    items.append(("tile", "bg_slate", x, y))
    rh = max(rh, 1024)
    cv = Canvas(W, y + rh + pad + 24)
    for kind, n, x, y in items:
        if kind == "head":
            cv.text((x, y), n.upper(), head, (200, 186, 160))
        elif kind == "img":
            im = tex(n)
            cv.put(im, x, y)
            cv.text((x, y + im.height + 3), f"{n} {im.width}x{im.height}", lab, (140, 134, 128), shadow=False)
        elif kind == "nine":
            name, w, h = n
            cv.put(nine(name, w, h), x, y)
            cv.text((x, y + h + 3), f"{name} @ {w}x{h}", lab, (140, 134, 128), shadow=False)
        else:
            t = tex(n)
            big = Image.new("RGBA", (t.width * 2, t.height * 2))
            for i in range(2):
                for j in range(2):
                    big.paste(t, (i * t.width, j * t.height))
            cv.put(big, x, y)
            cv.text((x, y + big.height + 3), "bg_slate 2x2", lab, (140, 134, 128), shadow=False)
    cv.save(os.path.join(OUT, "kit_sheet.png"))


def preview(names, bg=BG):
    ims = [tex(n) for n in names]
    pad = 24
    W = min(2400, max(sum(i.width + pad for i in ims) + pad, 400))
    rows, x, y, rh = [], pad, pad, 0
    for im in ims:
        if x + im.width + pad > W and x > pad:
            x, y, rh = pad, y + rh + pad + 20, 0
        rows.append((im, x, y))
        x += im.width + pad
        rh = max(rh, im.height)
    sheet = Image.new("RGBA", (W, y + rh + pad + 20), bg)
    d = ImageDraw.Draw(sheet)
    f = font("EBGaramond.ttf", 15)
    for (im, x, y), n in zip(rows, names):
        sheet.alpha_composite(im, (x, y))
        d.text((x, y + im.height + 3), n, font=f, fill=(150, 145, 140, 255))
    sheet.convert("RGB").save(os.path.join(OUT, "preview.png"))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(sys.argv[2:])
    else:
        kit_sheet()
        mock_reward()
        print("[compose] build/ui/kit_sheet.png, build/ui/mock_reward.png")
