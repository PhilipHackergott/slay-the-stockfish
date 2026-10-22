"""The five object-transform clips every piece carries (contract: move, leap, capture, drop, spawn).

Keys are (seconds, value[, slope_in[, slope_out]]); slopes in units per second, otherwise auto-clamped Bezier.
Pitch is +X rotation (the top leans toward -Y, the piece's front). Horizontal travel is the game's job.
"""
import math
import random

import common

D = math.radians
LOC_Z = ("location", 2)
ROT_X = ("rotation_euler", 0)
ROT_Y = ("rotation_euler", 1)
ROT_Z = ("rotation_euler", 2)
SC_X = ("scale", 0)
SC_Y = ("scale", 1)
SC_Z = ("scale", 2)

DURATIONS = {"move": 0.55, "leap": 0.75, "capture": 0.90, "drop": 0.60, "spawn": 0.50}


def _squash(chans, keys_z, keys_xy):
    chans[SC_Z] = keys_z
    chans[SC_X] = keys_xy
    chans[SC_Y] = list(keys_xy)


def move():
    c = {
        LOC_Z: [(0.0, 0.0), (0.08, 0.0, 0.0, 2.4), (0.27, 0.30), (0.45, 0.0, -2.6, 0.0), (0.55, 0.0)],
        ROT_X: [(0.0, 0.0), (0.08, D(-2)), (0.20, D(7)), (0.30, D(10)), (0.41, D(6)), (0.47, D(-2.5)),
                (0.52, D(1)), (0.55, 0.0)],
    }
    _squash(c, [(0.0, 1.0), (0.08, 0.94), (0.16, 1.05), (0.27, 1.0), (0.43, 1.03), (0.48, 0.90), (0.52, 1.02),
                (0.55, 1.0)],
            [(0.0, 1.0), (0.08, 1.03), (0.16, 0.976), (0.27, 1.0), (0.43, 0.985), (0.48, 1.054), (0.52, 0.99),
             (0.55, 1.0)])
    return c


def leap():
    c = {
        LOC_Z: [(0.0, 0.0), (0.10, 0.0, 0.0, 5.0), (0.36, 0.95), (0.62, 0.0, -6.0, 0.0), (0.75, 0.0)],
        ROT_X: [(0.0, 0.0), (0.10, D(-3)), (0.20, D(-6)), (0.36, D(5)), (0.56, D(18)), (0.62, D(3)),
                (0.67, D(-3)), (0.71, D(1.2)), (0.75, 0.0)],
    }
    _squash(c, [(0.0, 1.0), (0.10, 0.92), (0.18, 1.08), (0.34, 1.0), (0.58, 1.04), (0.64, 0.88), (0.70, 1.03),
                (0.75, 1.0)],
            [(0.0, 1.0), (0.10, 1.04), (0.18, 0.962), (0.34, 1.0), (0.58, 0.98), (0.64, 1.066), (0.70, 0.985),
             (0.75, 1.0)])
    return c


def capture(height, seed=7):
    rng = random.Random(seed)
    rx, ry, rz, lz = [(0.0, 0.0)], [(0.0, 0.0)], [(0.0, 0.0)], [(0.0, 0.0)]
    t = 0.025
    while t < 0.245:
        amp = D(1.0 + 3.0 * t / 0.25)
        rx.append((t, rng.uniform(-amp, amp)))
        ry.append((t, rng.uniform(-amp, amp)))
        rz.append((t, rng.uniform(-amp, amp) * 0.6))
        lz.append((t, rng.uniform(0.0, 0.008)))
        t += 0.025
    rx += [(0.25, D(1)), (0.45, D(25)), (0.90, D(30))]
    ry += [(0.25, 0.0), (0.45, D(7)), (0.90, D(10))]
    rz += [(0.25, 0.0), (0.90, D(12))]
    lz += [(0.25, 0.0), (0.45, -0.06 * height), (0.90, -height, -3.0 * height)]
    c = {ROT_X: rx, ROT_Y: ry, ROT_Z: rz, LOC_Z: lz}
    _squash(c, [(0.0, 1.0), (0.25, 1.0), (0.30, 0.94), (0.45, 0.95), (0.90, 0.6)],
            [(0.0, 1.0), (0.25, 1.0), (0.30, 1.04), (0.45, 0.97), (0.90, 0.6)])
    return c


def drop():
    c = {
        LOC_Z: [(0.0, 2.2, 0.0, 0.0), (0.36, 0.0, -12.0, 0.0), (0.60, 0.0)],
        ROT_Z: [(0.0, D(90)), (0.36, 0.0), (0.60, 0.0)],
        ROT_X: [(0.0, 0.0), (0.36, 0.0), (0.41, D(3)), (0.49, D(-1.5)), (0.60, 0.0)],
    }
    _squash(c, [(0.0, 1.0), (0.30, 1.07), (0.36, 1.0), (0.40, 0.86), (0.47, 1.05), (0.54, 0.98), (0.60, 1.0)],
            [(0.0, 1.0), (0.30, 0.966), (0.36, 1.0), (0.40, 1.078), (0.47, 0.976), (0.54, 1.01), (0.60, 1.0)])
    return c


def spawn(height):
    c = {LOC_Z: [(0.0, -height, 0.0, 4.5 * height), (0.34, 0.03), (0.50, 0.0)]}
    s = [(0.0, 0.8), (0.30, 1.04), (0.42, 0.99), (0.50, 1.0)]
    _squash(c, s, list(s))
    return c


def add_all(ob, height):
    clips = {"move": move(), "leap": leap(), "capture": capture(height), "drop": drop(), "spawn": spawn(height)}
    for name, chans in clips.items():
        common.add_clip(ob, name, DURATIONS[name], chans)
