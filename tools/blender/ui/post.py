"""Raw 2x renders (build/ui/raw) -> assets/ui/kit/*.png + kit.json.

python post.py [name ...]   (needs Pillow + numpy; build_all.sh runs it from build/ui/.venv)
Steps per file (spec.py): premultiplied 2x2 box downscale, then the listed ops (bloom from the state difference,
threshold bloom, outer halo, desaturate, hole clearing, resize). Prints a stretch report for nine-slice edges.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RAW = os.path.join(ROOT, "build", "ui", "raw")
OUT = os.path.join(ROOT, "assets", "ui", "kit")


def load_raw(name):
    a = np.asarray(Image.open(os.path.join(RAW, name + ".png")).convert("RGBA"), np.float32) / 255.0
    a[..., :3] *= a[..., 3:4]
    h, w = a.shape[0] // 2, a.shape[1] // 2
    return a[:h * 2, :w * 2].reshape(h, 2, w, 2, 4).mean(axis=(1, 3))


def save(a, path):
    a = np.clip(a, 0.0, 1.0)
    al = a[..., 3:4]
    rgb = np.where(al > 1e-4, a[..., :3] / np.maximum(al, 1e-4), 0.0)
    out = np.concatenate([np.clip(rgb, 0, 1), al], axis=2)
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def _box(a, r, axis):
    if r < 1:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad), axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def blur(a, sigma):
    """Gaussian-ish blur (three box passes), zero outside the image."""
    r = max(1, int(round(sigma * 0.85)))
    for _ in range(3):
        a = _box(_box(a, r, 0), r, 1)
    return a


def add_glow(img, glow):
    out = img.copy()
    out[..., :3] = img[..., :3] + glow
    out[..., 3] = np.maximum(img[..., 3], np.clip(glow.max(axis=2), 0, 1))
    return np.clip(out, 0, 1)


def op_bloom(img, base, strength, r1, r2):
    g = np.clip(img[..., :3] - base[..., :3], 0, None)
    return add_glow(img, (blur(g, r1) * 0.55 + blur(g, r2) * 0.65) * strength)


def op_selfbloom(img, thr, strength, r):
    lum = img[..., :3].max(axis=2, keepdims=True)
    g = img[..., :3] * np.clip((lum - thr) / (1.0 - thr), 0, 1)
    return add_glow(img, blur(g, r) * strength)


def op_halo(img, color, r, strength):
    solid = (img[..., 3] > 0.9).astype(np.float32)
    k = np.clip(blur(solid[..., None], r)[..., 0] * 1.6, 0, 1) * strength
    col = np.array(color, np.float32) / 255.0
    halo = np.concatenate([col[None, None, :] * k[..., None], k[..., None]], axis=2)
    return img + halo * (1.0 - img[..., 3:4])


def op_desat(img, amount, darken):
    out = img.copy()
    lum = (img[..., :3] * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(axis=2, keepdims=True)
    out[..., :3] = (img[..., :3] * (1 - amount) + lum * amount) * (1 - darken)
    return out


def op_hole(img, radius):
    h, w = img.shape[:2]
    y, x = np.mgrid[0:h, 0:w]
    r = np.hypot(x + 0.5 - w / 2, y + 0.5 - h / 2)
    return img * np.clip(r - radius + 1.0, 0, 1)[..., None]


def op_resize(img, w, h):
    chans = []
    for c in range(4):
        im = Image.fromarray(img[..., c].astype(np.float32), "F")
        chans.append(np.asarray(im.resize((w, h), Image.LANCZOS), np.float32))
    out = np.stack(chans, axis=2)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[..., :3] = np.clip(out[..., :3], 0, out[..., 3:4])
    return out


def build(name, cache):
    f = spec.FILES[name]
    if f["raw"] not in cache:
        cache[f["raw"]] = load_raw(f["raw"])
    img = cache[f["raw"]].copy()
    for op in f["post"]:
        kind, args = op[0], op[1:]
        if kind == "bloom":
            if args[0] not in cache:
                cache[args[0]] = load_raw(args[0])
            img = op_bloom(img, cache[args[0]], *args[1:])
        elif kind == "selfbloom":
            img = op_selfbloom(img, *args)
        elif kind == "halo":
            img = op_halo(img, *args)
        elif kind == "desat":
            img = op_desat(img, *args)
        elif kind == "hole":
            img = op_hole(img, *args)
        elif kind == "resize":
            img = op_resize(img, *args)
    w, h = f["size"]
    assert img.shape[:2] == (h, w), (name, img.shape, f["size"])
    return img


def stretch_report(name, img):
    """Mean abs step (0..255) between neighbouring pixels along the stretch axis of each edge strip.

    Smooth drifts stretch invisibly; sharp detail along the axis (rivets, ornaments, grain) is what smears."""
    l, t, r, b = spec.FILES[name]["margin"]
    if not any((l, t, r, b)):
        return None
    h, w = img.shape[:2]
    a = img[..., :4] * 255.0
    res = {}
    strips = {"top": a[:t, l:w - r], "bottom": a[h - b:, l:w - r],
              "left": a[t:h - b, :l].transpose(1, 0, 2), "right": a[t:h - b, w - r:].transpose(1, 0, 2)}
    # long strips (bars, plaques, tracks) only ever stretch along their long axis
    horiz_only, vert_only = w >= 4 * h, h >= 4 * w
    for k, s in strips.items():
        if (s.size == 0 or (k in ("top", "bottom") and (vert_only or not (l or r)))
                or (k in ("left", "right") and (horiz_only or not (t or b)))):
            continue
        res[k] = float(np.abs(np.diff(s, axis=1)).mean()) if s.shape[1] > 1 else 0.0
    return res


def main():
    names = sys.argv[1:] or list(spec.FILES)
    os.makedirs(OUT, exist_ok=True)
    cache = {}
    worst = 0.0
    for n in names:
        img = build(n, cache)
        save(img, os.path.join(OUT, spec.FILES[n]["file"]))
        rep = stretch_report(n, img)
        if rep:
            worst = max(worst, max(rep.values()))
            print(f"[post] {n:24s} edge detail " + " ".join(f"{k}={v:.1f}" for k, v in rep.items()))
        else:
            print(f"[post] {n}")
    meta = {}
    for n, f in spec.FILES.items():
        e = {"file": f["file"], "size": f["size"], "margin": f["margin"], "content": f["content"]}
        e.update(f["extra"])
        meta[n] = e
    with open(os.path.join(OUT, "kit.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
        fh.write("\n")
    print(f"[post] wrote {len(names)} files + kit.json; worst edge detail {worst:.1f}/255")


if __name__ == "__main__":
    main()
