#!/usr/bin/env python3
"""Procedural audio for Slay the Stockfish.

Every sound in assets/audio/ is synthesised here from scratch: no samples, no
recordings. Each sound has its own RNG seeded from its name, so reruns (and
partial reruns) produce identical files.

Rebuild everything:

    tools/audio/build.sh                  # creates tools/audio/.venv on first run

Options (passed through build.sh):

    --only ui_click,music_map             # render a subset (audio.json is merged)
    --group sfx|music                     # render one group
    --verify-only / --no-verify           # only check + plot / skip the checks
    --jobs N                              # worker processes (default: cpu count, max 6)

Checks live in verify_audio.py (decodes the OGGs like the game does and measures
duration, peak, DC, clipping, loudness and loop-seam continuity).

Outputs:

    assets/audio/sfx/<name>.wav           16-bit 44.1 kHz mono, peak -3 dBFS
    assets/audio/music/<name>.ogg         Vorbis q5 stereo 44.1 kHz, ~-18 LUFS, seamless loops
    assets/audio/audio.json               category, duration, suggested volume_db, loop info
    build/audio/spectrograms.png          sanity sheet
    build/audio/report.txt                peaks, loudness, loop-seam metrics

Techniques: modal synthesis (resonator banks excited by pulses / noise /
stick-slip impulse trains) for stone, wood and metal; additive bells with
inharmonic church-bell partials and beating pairs; FM strike transients;
choir pads from detuned polyBLEP saws through vowel formant filters; additive
pipe organ; stretched-partial piano; STFT-shaped noise for whooshes, wind and
paper; synthetic stereo impulse responses (frequency-dependent decay) for
convolution reverb (IRs normalised to unit mid-band gain, so `wet` is the
direct-to-reverb ratio). Loops are built periodically: events wrap around the
loop, oscillators are quantised to whole cycles, noise beds are filtered
circularly and the reverb tail is folded back onto the head, so the seam is
exact. Components inside a sound are balanced by measured loudness (fitm / fit
scale each part to a target momentary / integrated LUFS) rather than raw gains.

Levels: SFX peak -3 dBFS (sustained ones capped at -14 LUFS momentary, short
impacts get a 2-4 dB transient shave first); music and ambience -18 LUFS
integrated, peak <= -1.5 dBFS (wrap-around lookahead limiter, rarely engaged).

Encoding: WAV via scipy, OGG via `oggenc -q 5 --serial <fixed>` (deterministic).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import zlib
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from scipy import ndimage, signal
from scipy.io import wavfile

SR = 44100
TAU = 2.0 * np.pi
ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets/audio/sfx"
MUSIC_DIR = ROOT / "assets/audio/music"
META_PATH = ROOT / "assets/audio/audio.json"
BUILD = ROOT / "build/audio"

SFX_PEAK_DB = -3.0
SFX_MAX_MOMENTARY_LUFS = -14.0
MUSIC_LUFS = -18.0
MUSIC_PEAK_DB = -1.5


# ----------------------------------------------------------------------------
# basics


def rng(name: str, salt: int = 0) -> np.random.Generator:
    return np.random.default_rng([zlib.crc32(name.encode()), salt])


def n(sec: float) -> int:
    return int(round(sec * SR))


def tvec(N: int) -> np.ndarray:
    return np.arange(N) / SR


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def hz(note: str) -> float:
    pcs = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    pc = pcs[note[0]]
    i = 1
    while i < len(note) and note[i] in "#b":
        pc += 1 if note[i] == "#" else -1
        i += 1
    midi = 12 * (int(note[i:]) + 1) + pc
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def qf(f: float, N: int) -> float:
    """Frequency rounded to a whole number of cycles over N samples (seamless loops)."""
    return max(1.0, round(f * N / SR)) * SR / N


def env(N: int, pts, curve: str = "cos") -> np.ndarray:
    """Piecewise envelope through (time_s, value) points, cosine-eased by default."""
    t = tvec(N)
    ts = np.array([p[0] for p in pts], float)
    vs = np.array([p[1] for p in pts], float)
    if curve == "lin":
        return np.interp(t, ts, vs)
    i = np.clip(np.searchsorted(ts, t, side="right") - 1, 0, len(ts) - 2)
    t0, t1 = ts[i], ts[i + 1]
    frac = np.clip((t - t0) / np.maximum(t1 - t0, 1e-9), 0.0, 1.0)
    frac = 0.5 - 0.5 * np.cos(np.pi * frac)
    out = vs[i] + (vs[i + 1] - vs[i]) * frac
    out[t < ts[0]] = vs[0]
    out[t >= ts[-1]] = vs[-1]
    return out


def decay(N: int, t60: float, start: float = 0.0) -> np.ndarray:
    t = tvec(N) - start
    return np.where(t >= 0, 10.0 ** (-3.0 * np.maximum(t, 0) / t60), 0.0)


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0) -> None:
    s = n(at)
    if s >= dst.shape[-1]:
        return
    k = min(src.shape[-1], dst.shape[-1] - s)
    dst[..., s:s + k] += gain * src[..., :k]


def pan(x: np.ndarray, p: float) -> np.ndarray:
    a = (p + 1.0) * np.pi / 4.0
    return np.stack([np.cos(a) * x, np.sin(a) * x])


# ----------------------------------------------------------------------------
# filters


def _sos(kind: str, f, order: int = 2):
    if np.ndim(f) == 0:
        f = min(float(f), SR * 0.45)
    else:
        f = [max(10.0, min(float(x), SR * 0.45)) for x in f]
    return signal.butter(order, f, btype=kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("low", fc, order), x, axis=-1)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("high", fc, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", [lo, hi], order), x, axis=-1)


def peak_bp(x, f, q):
    """RBJ band-pass with 0 dB peak gain."""
    w = TAU * min(f, SR * 0.45) / SR
    al = np.sin(w) / (2.0 * q)
    b = np.array([al, 0.0, -al])
    a = np.array([1.0 + al, -2.0 * np.cos(w), 1.0 - al])
    return signal.lfilter(b / a[0], a / a[0], x, axis=-1)


def circ(fn, x, pad: int):
    """Apply a causal filter to a periodic signal so the output is periodic too."""
    N = x.shape[-1]
    reps = int(np.ceil(pad / N))
    head = np.concatenate([x] * reps, axis=-1)[..., -pad:] if pad else x[..., :0]
    return fn(np.concatenate([head, x], axis=-1))[..., pad:]


def fft_filter(x, gain_fn, circular=False):
    """Zero-phase filter in the frequency domain; gain_fn(freqs) -> gain."""
    N = x.shape[-1]
    M = N if circular else int(2 ** np.ceil(np.log2(N + n(0.5))))
    X = np.fft.rfft(x, M, axis=-1)
    f = np.fft.rfftfreq(M, 1.0 / SR)
    y = np.fft.irfft(X * gain_fn(f), M, axis=-1)
    return y[..., :N]


def band_gain(lo, hi, slope=2):
    def g(f):
        f = np.maximum(f, 1e-3)
        out = np.ones_like(f)
        if lo:
            out /= np.sqrt(1.0 + (lo / f) ** (2 * slope))
        if hi:
            out /= np.sqrt(1.0 + (f / hi) ** (2 * slope))
        return out
    return g


def stft_shape(x, gain_fn, nper=1024):
    """Time-varying spectral shaping: gain_fn(freqs[:,None], times[None,:])."""
    nov = nper * 3 // 4
    f, t, Z = signal.stft(x, fs=SR, nperseg=nper, noverlap=nov, boundary="zeros", padded=True)
    _, y = signal.istft(Z * gain_fn(f[:, None], t[None, :]), fs=SR, nperseg=nper, noverlap=nov)
    out = np.zeros(len(x))
    k = min(len(x), len(y))
    out[:k] = y[:k]
    return out


def sweep_band(x, times, centres, bw_oct=1.0):
    """Gaussian (log-frequency) band whose centre glides through (time, Hz) points."""
    lt = np.log(np.asarray(centres, float))

    def g(f, t):
        fc = np.exp(np.interp(t, times, lt))
        return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / bw_oct) ** 2)
    return stft_shape(x, g)


def sweep_lp(x, times, cutoffs, order=2):
    lc = np.log(np.asarray(cutoffs, float))

    def g(f, t):
        fc = np.exp(np.interp(t, times, lc))
        return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    return stft_shape(x, g, nper=2048)


# ----------------------------------------------------------------------------
# sources


def white(N, r):
    return r.standard_normal(N)


def colored(N, r, exponent=1.0):
    """1/f^exponent noise (1 = pink, 2 = brown) via FFT shaping; periodic over N."""
    X = np.fft.rfft(r.standard_normal(N))
    f = np.fft.rfftfreq(N, 1.0 / SR)
    f[0] = f[1] if N > 1 else 1.0
    X *= (f / 1000.0) ** (-exponent / 2.0)
    X[0] = 0.0
    y = np.fft.irfft(X, N)
    return y / (np.std(y) + 1e-12)


def pnoise(N, r, cycles: int, slope=1.0):
    """Smooth random modulation, periodic over N, in [-1, 1]; `cycles` = highest harmonic."""
    k = np.arange(1, cycles + 1)
    spec = np.zeros(N // 2 + 1, complex)
    spec[1:cycles + 1] = (r.standard_normal(cycles) + 1j * r.standard_normal(cycles)) / k ** slope
    y = np.fft.irfft(spec, N)
    return y / (np.max(np.abs(y)) + 1e-12)


def phase_of(freq, N, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, float), (N,))
    return phase0 + np.cumsum(f) / SR


def sine(freq, N, phase0=0.0):
    return np.sin(TAU * phase_of(freq, N, phase0))


def saw(freq, N, phase0=0.0):
    """Band-limited (polyBLEP) sawtooth; freq may be an array."""
    f = np.broadcast_to(np.asarray(freq, float), (N,))
    dt = np.clip(f / SR, 1e-9, 0.5)
    ph = (phase0 + np.cumsum(f) / SR) % 1.0
    y = 2.0 * ph - 1.0
    m = ph < dt
    x = ph[m] / dt[m]
    y[m] -= 2.0 * x - x * x - 1.0
    m = ph > 1.0 - dt
    x = (ph[m] - 1.0) / dt[m]
    y[m] -= x * x + 2.0 * x + 1.0
    return y


def pulse(N, at, width):
    """Unit-area Hann pulse (hardness: first spectral null at 2/width)."""
    out = np.zeros(N)
    w = max(2, n(width))
    s = n(at)
    if s >= N:
        return out
    h = np.hanning(w + 2)[1:-1]
    h /= h.sum()
    k = min(w, N - s)
    out[s:s + k] = h[:k]
    return out


def burst(N, r, at, dur, lo, hi, tau, amp=1.0):
    out = np.zeros(N)
    m = n(dur)
    x = r.standard_normal(m) * np.exp(-tvec(m) / tau)
    x *= np.minimum(1.0, tvec(m) / 0.0005 + 1e-3)
    place(out, bp(x, lo, hi) if lo else lp(x, hi), at, amp)
    return out


def modal(exc, freqs, t60s, gains):
    """Bank of two-pole resonators: each mode rings as r^n sin(w n) with unit impulse gain."""
    exc = np.asarray(exc, float)
    out = np.zeros_like(exc)
    k = len(freqs)
    for f, t60, g in zip(freqs, np.broadcast_to(t60s, (k,)), np.broadcast_to(gains, (k,))):
        if f <= 20 or f >= 0.45 * SR:
            continue
        rr = 10.0 ** (-3.0 / (t60 * SR))
        w = TAU * f / SR
        out += g * signal.lfilter([np.sin(w)], [1.0, -2.0 * rr * np.cos(w), rr * rr], exc)
    return out


def friction(N, r, rate, modes, t60, gains, band, noise_amp):
    """Stick-slip texture: Poisson micro-impacts into resonators plus band noise."""
    rate = np.broadcast_to(np.asarray(rate, float), (N,))
    hits = (r.random(N) < rate / SR) * np.minimum(r.exponential(1.0, N), 2.5)
    return modal(hits, modes, t60, gains) + noise_amp * bp(r.standard_normal(N), *band)


# ----------------------------------------------------------------------------
# instruments


BELL = [  # ratio to prime, amplitude, relative decay (church bell: hum, prime, minor tierce, quint, nominal, ...)
    (0.5, 0.55, 1.0), (1.0, 0.45, 0.7), (1.183, 0.6, 0.6), (1.506, 0.25, 0.35), (2.0, 1.0, 0.45),
    (2.514, 0.35, 0.28), (2.662, 0.22, 0.25), (3.011, 0.25, 0.2), (4.166, 0.14, 0.14),
    (5.433, 0.08, 0.1), (6.796, 0.04, 0.07),
]


def bell(f, dur, r, T=None, bright=1.0, strike=1.0, maxf=8000.0):
    N = n(dur)
    t = tvec(N)
    T = T or 9.0 * (196.0 / f) ** 0.6
    out = np.zeros(N)
    for ratio, a, d in BELL:
        fr = f * ratio
        if fr > maxf:
            continue
        a *= bright ** np.log2(max(ratio, 1.0))
        beat = r.uniform(0.15, 1.1) * np.sqrt(ratio)
        p1, p2 = r.uniform(0, TAU, 2)
        e = 10.0 ** (-3.0 * t / (d * T)) * (1.0 - np.exp(-t / (0.02 if ratio < 1 else 0.0015)))
        out += a * e * (0.6 * np.sin(TAU * (fr - beat / 2) * t + p1) + 0.4 * np.sin(TAU * (fr + beat / 2) * t + p2))
    m = min(N, n(0.12))
    ts = t[:m]
    idx = 3.0 * np.exp(-ts / 0.012)
    clang = np.sin(TAU * f * 4.0 * ts + idx * np.sin(TAU * f * 5.43 * ts)) * np.exp(-ts / 0.018)
    out[:m] += 0.22 * strike * clang
    out += 0.25 * strike * burst(N, r, 0.0, 0.05, f * 2, min(f * 12, 7000), 0.006)
    return out


def chime(f, dur, r, T=2.5, fm=0.3):
    N = n(dur)
    t = tvec(N)
    out = np.zeros(N)
    for ratio, a, d in [(1.0, 1.0, 1.0), (2.756, 0.4, 0.45), (5.404, 0.18, 0.2), (8.933, 0.06, 0.1)]:
        fr = f * ratio
        if fr > 9000:
            continue
        beat = r.uniform(0.3, 1.5)
        e = 10.0 ** (-3.0 * t / (d * T)) * (1.0 - np.exp(-t / 0.001))
        out += a * e * (0.6 * np.sin(TAU * fr * t + r.uniform(0, TAU)) + 0.4 * np.sin(TAU * (fr + beat) * t))
    idx = 2.0 * np.exp(-t / 0.15)
    out += fm * np.sin(TAU * f * t + idx * np.sin(TAU * f * 3.5 * t)) * 10.0 ** (-3.0 * t / (0.5 * T))
    out += 0.15 * burst(N, r, 0.0, 0.01, f, min(4 * f, 8000), 0.002)
    return out


def rev_swell(N, r, at, dur, lo, hi):
    """Reverse-cymbal-like noise swell ending at `at + dur`."""
    out = np.zeros(N)
    m = n(dur)
    x = bp(colored(m, r, 0.5), lo, hi) * (tvec(m) / dur) ** 2.5
    x[-n(0.01):] *= np.linspace(1, 0, n(0.01))
    place(out, x, at)
    return out


FORMANTS = {  # vowel: (freqs, gains dB, bandwidths) -- classic choir tables (alto / bass)
    "a": ([800, 1150, 2800, 3500, 4950], [0, -4, -20, -36, -60], [80, 90, 120, 130, 140]),
    "o": ([450, 800, 2830, 3500, 4950], [0, -9, -16, -28, -55], [70, 80, 100, 130, 135]),
    "u": ([325, 700, 2530, 3500, 4950], [0, -12, -30, -40, -64], [50, 60, 170, 180, 200]),
    "a_bass": ([600, 1040, 2250, 2450, 2750], [0, -7, -9, -9, -20], [60, 70, 110, 120, 130]),
    "o_bass": ([400, 750, 2400, 2600, 2900], [0, -11, -21, -20, -40], [40, 80, 100, 120, 120]),
    "u_bass": ([350, 600, 2400, 2675, 2950], [0, -20, -32, -28, -36], [40, 80, 100, 120, 120]),
}


def formant(x, vowel, widen=1.6):
    F, G, B = FORMANTS[vowel]
    y = np.zeros_like(x)
    for f, g, bw in zip(F, G, B):
        y += db(g) * peak_bp(x, f, f / (bw * widen))
    return y


def choir(notes, N, r, vowel="a", n_saw=3, detune=9.0, vib=0.0045, breath=0.06, pans=None, glide=None):
    """Stereo choir section: detuned vibrato saws per voice through vowel formants."""
    t = tvec(N)
    out = np.zeros((2, N))
    for i, f in enumerate(notes):
        v = vowel + ("_bass" if f < 190 else "")
        voice = np.zeros(N)
        for k in range(n_saw):
            cents = (k - (n_saw - 1) / 2.0) * (2.0 * detune / max(1, n_saw - 1)) + r.normal(0, 2.0)
            rate = r.uniform(4.6, 5.8)
            fi = f * 2.0 ** (cents / 1200.0) * (1.0 + vib * np.sin(TAU * rate * t + r.uniform(0, TAU)))
            fi *= 1.0 + 0.0025 * pnoise(N, r, max(2, int(N / SR * 1.5)))
            if glide is not None:
                fi = fi * glide
            voice += saw(fi, N, r.uniform())
        voice /= n_saw
        sung = 2.2 * formant(voice, v) + 0.1 * lp(voice, 1000)
        sung += breath * formant(r.standard_normal(N), v)
        p = pans[i] if pans is not None else (((i % 2) * 2 - 1) * 0.3)
        out += pan(sung, p)
    return out


ORGAN = [(0.5, 0.35), (1, 1.0), (2, 0.55), (3, 0.22), (4, 0.3), (5, 0.07), (6, 0.12), (8, 0.08)]


def organ(f, N, r, stops=ORGAN, celeste=1.6, periodic=False, maxf=6000.0, chiff=0.15):
    t = tvec(N)
    y = np.zeros(N)
    for mult, a in stops:
        for c, w in ((0.0, 1.0), (celeste, 0.6)):
            ff = f * mult * 2.0 ** (c / 1200.0)
            if ff > maxf:
                continue
            if periodic:
                ff = qf(ff, N)
            y += a * w * np.sin(TAU * ff * t + r.uniform(0, TAU))
    if chiff and not periodic:
        y += chiff * burst(N, r, 0.0, 0.08, f * 1.5, f * 3, 0.02) * 6.0
    return y


def strings(notes, N, r, cutoff=1100.0, n_saw=5, detune=12.0, vib=0.003, pans=None, periodic=False):
    t = tvec(N)
    out = np.zeros((2, N))
    vib_in = np.minimum(1.0, t / 1.5)
    for i, f in enumerate(notes):
        voice = np.zeros(N)
        for k in range(n_saw):
            cents = (k - (n_saw - 1) / 2.0) * (2.0 * detune / max(1, n_saw - 1))
            ff = f * 2.0 ** (cents / 1200.0)
            rate = r.uniform(4.8, 5.8)
            if periodic:
                ff, rate = qf(ff, N), qf(rate, N)
                fi = ff * (1.0 + vib * np.sin(TAU * rate * t + r.uniform(0, TAU)))
            else:
                fi = ff * (1.0 + vib * vib_in * np.sin(TAU * rate * t + r.uniform(0, TAU)))
            voice += saw(fi, N, r.uniform())
        voice /= n_saw
        p = pans[i] if pans is not None else r.uniform(-0.5, 0.5)
        out += pan(voice, p)
    if periodic:
        out = circ(lambda x: lp(x, cutoff, 2), out, n(0.5))
        out = out + 0.35 * circ(lambda x: peak_bp(x, 300.0, 1.2), out, n(0.5))
    else:
        out = lp(out, cutoff, 2)
        out = out + 0.35 * peak_bp(out, 300.0, 1.2)
    return out


def piano(f, dur, r, vel=0.5, maxf=3500.0):
    """Dark piano-like pluck: stretched partials, two-stage decay, detuned unison."""
    N = n(dur)
    t = tvec(N)
    B = 0.00035
    cutoff = f * (3.0 + 9.0 * vel)
    y = np.zeros(N)
    for k in range(1, 31):
        fk = k * f * np.sqrt(1.0 + B * k * k)
        if fk > maxf:
            break
        a = (1.0 / k) / (1.0 + (fk / cutoff) ** 2) * (0.3 + abs(np.sin(np.pi * k / 7.3)))
        tau1 = 0.5 / np.sqrt(k)
        tau2 = min(8.0, 5.0 * (110.0 / f) ** 0.4 / k ** 0.8)
        e = 0.6 * np.exp(-t / tau1) + 0.4 * np.exp(-t / tau2)
        d = fk * 0.0005 * r.uniform(0.5, 1.0)
        y += a * e * (np.sin(TAU * (fk - d) * t + r.uniform(0, TAU)) + np.sin(TAU * (fk + d) * t + r.uniform(0, TAU)))
    y *= 1.0 - np.exp(-t / 0.002)
    y += 0.3 * vel * burst(N, r, 0.0, 0.05, 0, 350, 0.01) * 4.0
    y *= env(N, [(0, 1), (dur - 0.4, 1), (dur, 0)])
    return y * (0.4 + vel)


def drum(f, dur, r, ratios=(1.0, 1.5, 1.98, 2.44), amps=(1.0, 0.5, 0.3, 0.2), t60s=(0.9, 0.6, 0.4, 0.3),
         drop=0.25, noise=0.3, noise_hi=1500.0):
    """Tuned membrane (timpani-ish): additive modes with a pitch drop and a noise strike."""
    N = n(dur)
    t = tvec(N)
    bend = 1.0 + drop * np.exp(-t / 0.04)
    y = np.zeros(N)
    for ratio, a, d in zip(ratios, amps, t60s):
        y += a * sine(f * ratio * bend, N, r.uniform()) * 10.0 ** (-3.0 * t / d)
    y *= 1.0 - np.exp(-t / 0.001)
    y += noise * burst(N, r, 0.0, 0.1, 60, noise_hi, 0.015) * 3.0
    return y


def bass_pluck(f, dur, r, bright=1.0):
    N = n(dur)
    t = tvec(N)
    s = saw(f, N, r.uniform())
    bright_part = lp(s, 900.0 * bright, 2) * np.exp(-t / 0.07)
    dark_part = lp(s, 170.0, 2)
    y = 0.8 * bright_part + 0.9 * dark_part + 0.8 * np.sin(TAU * f * t)
    y *= (1.0 - np.exp(-t / 0.003)) * np.exp(-t / 0.2)
    y *= env(N, [(0, 1), (dur - 0.03, 1), (dur, 0)])
    return y


def tick(f, r, amp=1.0):
    N = n(0.08)
    exc = pulse(N, 0.0, 0.0002)
    y = modal(exc, [f, f * 1.58, f * 2.41], [0.03, 0.02, 0.012], [1.0, 0.5, 0.25])
    y += 0.15 * burst(N, r, 0.0, 0.004, f, f * 3, 0.001)
    return amp * y


# ----------------------------------------------------------------------------
# reverb


_IR: dict = {}

IR_SPECS = {
    # name: band RT60s (<250, <1k, <3k, <7k, >7k), length s, predelay s, early span s, lowpass
    "room": ((0.45, 0.4, 0.32, 0.22, 0.12), 0.7, 0.003, 0.025, 7000.0),
    "hall": ((2.0, 1.7, 1.25, 0.75, 0.35), 2.4, 0.012, 0.06, 6500.0),
    "cathedral": ((7.0, 5.6, 3.8, 1.9, 0.8), 7.5, 0.035, 0.13, 5500.0),
}


def ir(kind: str) -> np.ndarray:
    if kind in _IR:
        return _IR[kind]
    rts, length, predelay, span, lpf = IR_SPECS[kind]
    r = rng("ir_" + kind)
    M = n(length)
    t = tvec(M)
    edges = [250.0, 1000.0, 3000.0, 7000.0]
    chans = []
    for _ in range(2):
        w = r.standard_normal(M)
        parts = [lp(w, edges[0], 4)]
        parts += [bp(w, lo, hi, 2) for lo, hi in zip(edges[:-1], edges[1:])]
        parts += [hp(w, edges[-1], 4)]
        tail = sum(p * 10.0 ** (-3.0 * t / rt) for p, rt in zip(parts, rts))
        tail *= 1.0 - np.exp(-t / (0.02 + span * 0.25))
        tail /= np.sqrt(np.sum(tail ** 2))
        er = np.zeros(M)
        for ti in np.sort(r.uniform(0.0, span, 14)):
            er[n(ti)] += r.choice([-1.0, 1.0]) * (1.0 - 0.6 * ti / span)
        er = lp(er, 4500.0)
        er *= np.sqrt(0.2 / (np.sum(er ** 2) + 1e-12))
        x = np.concatenate([np.zeros(n(predelay)), tail + er])[:M]
        x = lp(x, lpf)
        x *= env(M, [(0, 1), (length * 0.9, 1), (length, 0)])
        chans.append(x)
    h = np.array(chans)
    # unit mean power gain over 100 Hz - 4 kHz (log-weighted), so wet = direct-to-reverb amplitude ratio
    nfft = 1 << int(np.ceil(np.log2(M)))
    H = np.fft.rfft(h, nfft, axis=1)
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    band = (f >= 100) & (f <= 4000)
    w = 1.0 / f[band]
    p = np.sum(np.abs(H[:, band]) ** 2 * w, axis=1) / w.sum()
    _IR[kind] = h / np.sqrt(p.mean())
    return _IR[kind]


def verb(x, kind, wet, dry=1.0, stereo=False):
    """Convolution reverb for one-shots (output grows by the IR length)."""
    h = ir(kind)
    if x.ndim == 1 and not stereo:
        w = signal.oaconvolve(x, h[0])
        out = w * wet
        out[:len(x)] += dry * x
        return out
    if x.ndim == 1:
        x = np.stack([x, x])
    w = np.stack([signal.oaconvolve(x[c], h[c]) for c in range(2)])
    out = w * wet
    out[:, :x.shape[1]] += dry * x
    return out


def verb_loop(x, kind, wet, dry=1.0):
    """Circular convolution reverb: the tail beyond the loop folds back onto the head."""
    h = ir(kind)
    N = x.shape[-1]
    if x.ndim == 1:
        x = np.stack([x, x])
    out = dry * x.copy()
    for c in range(2):
        w = signal.fftconvolve(x[c], h[c])
        folded = w[:N].copy()
        i = N
        while i < len(w):
            k = min(N, len(w) - i)
            folded[:k] += w[i:i + k]
            i += k
        out[c] += wet * folded
    return out


# ----------------------------------------------------------------------------
# loudness (ITU-R BS.1770 K-weighting, gated integrated loudness)


def _k_weight(x):
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / SR)
    Vh = 10.0 ** (G / 20.0)
    Vb = Vh ** 0.4996667741545416
    a0 = 1.0 + K / Q + K * K
    b1 = np.array([(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0])
    a1 = np.array([1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0])
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / SR)
    a2 = np.array([1.0, 2.0 * (K * K - 1.0) / (1.0 + K / Q + K * K), (1.0 - K / Q + K * K) / (1.0 + K / Q + K * K)])
    b2 = np.array([1.0, -2.0, 1.0])
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=-1), axis=-1)


def _block_power(x):
    x = np.atleast_2d(x)
    y = _k_weight(x)
    blk, hop = n(0.4), n(0.1)
    if y.shape[1] < blk:
        y = np.pad(y, ((0, 0), (0, blk - y.shape[1])))
    c = np.cumsum(np.pad(y ** 2, ((0, 0), (1, 0))), axis=1)
    starts = np.arange(0, y.shape[1] - blk + 1, hop)
    z = (c[:, starts + blk] - c[:, starts]) / blk
    return z.sum(axis=0)


def lufs(x) -> float:
    z = _block_power(x)
    lk = -0.691 + 10 * np.log10(z + 1e-20)
    z = z[lk > -70]
    if len(z) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(z.mean()) - 10
    z2 = z[-0.691 + 10 * np.log10(z) > rel]
    return float(-0.691 + 10 * np.log10(z2.mean()))


def momentary_max(x) -> float:
    return float(np.max(-0.691 + 10 * np.log10(_block_power(x) + 1e-20)))


def fitm(x, target):
    """Scale one component of a sound to a target momentary loudness (balance inside an SFX)."""
    return x * db(target - momentary_max(x))


def peak_db(x) -> float:
    return float(20 * np.log10(np.max(np.abs(x)) + 1e-12))


# ----------------------------------------------------------------------------
# finishing + encoding


def transient_limit(x, reduce_db):
    """Shave the first sub-millisecond spikes of an impact so its body reads at the same peak level."""
    a = np.abs(x)
    need = np.minimum(1.0, a.max() * db(-reduce_db) / np.maximum(a, 1e-12))
    w = 2 * n(0.0015) + 1
    g = ndimage.uniform_filter1d(ndimage.minimum_filter1d(need, w), w)
    return x * np.minimum(g, need)


def finish_sfx(x, loop=False, max_dur=None, punch=0.0):
    if punch:
        x = transient_limit(x, punch)
    if loop:
        x = x - x.mean()
        x = circ(lambda v: hp(v, 25.0, 2), x, n(0.5))
    else:
        x = hp(x, 25.0, 2)
        e = ndimage.maximum_filter1d(np.abs(x), n(0.01))
        last = np.nonzero(e > np.max(e) * db(-62))[0]
        end = min(len(x), (last[-1] if len(last) else len(x)) + n(0.02))
        if max_dur:
            end = min(end, n(max_dur))
        x = x[:end].copy()
        fo = max(n(0.02), min(end // 4, int(0.15 * end)))
        x[-fo:] *= np.cos(np.linspace(0, np.pi / 2, fo)) ** 2
        x[:n(0.0005)] *= np.linspace(0, 1, n(0.0005))
    g = db(SFX_PEAK_DB) / (np.max(np.abs(x)) + 1e-12)
    mm = momentary_max(x * g)
    if mm > SFX_MAX_MOMENTARY_LUFS:
        g *= db(SFX_MAX_MOMENTARY_LUFS - mm)
    return x * g


def limit_loop(x, ceiling):
    a = np.max(np.abs(x), axis=0)
    need = np.minimum(1.0, ceiling / np.maximum(a, 1e-12))
    if need.min() >= 1.0:
        return x
    w = n(0.01)
    g = ndimage.minimum_filter1d(need, 2 * w + 1, mode="wrap")
    g = ndimage.uniform_filter1d(g, w, mode="wrap")
    g = np.minimum(g, need)
    return x * g


def finish_loop(x, target=MUSIC_LUFS):
    x = x - x.mean(axis=1, keepdims=True)
    x = circ(lambda v: hp(v, 28.0, 2), x, n(1.0))
    x = x * db(target - lufs(x))
    return limit_loop(x, db(MUSIC_PEAK_DB))


def to_i16(x):
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)


def write_wav(path: Path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    d = to_i16(x)
    wavfile.write(str(path), SR, d.T if d.ndim == 2 else d)


def write_ogg(path: Path, x, name: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "in.wav"
        write_wav(tmp, x)
        serial = zlib.crc32(name.encode()) & 0x7FFFFFFF
        subprocess.run(["oggenc", "-Q", "-q", "5", "--serial", str(serial), "-o", str(path), str(tmp)], check=True)


# ----------------------------------------------------------------------------
# SFX (mono, return float; finish_sfx normalises)


def ui_hover(r):
    N = n(0.14)
    exc = pulse(N, 0.0, 0.00025)
    y = modal(exc, [1450, 2380, 3720], [0.035, 0.022, 0.012], [1.0, 0.45, 0.2])
    y += 0.05 * burst(N, r, 0.0, 0.003, 1000, 4000, 0.0008)
    return verb(lp(y, 5000), "room", 0.2)


def ui_click(r):
    N = n(0.5)
    t1 = 0.032
    lift = pulse(N, 0.0, 0.00015)
    fall = pulse(N, t1, 0.00015)
    iron = [820, 2260, 4431, 7325]
    y = 0.35 * modal(lift, [1650, 4547], [0.06, 0.03], [1.0, 0.4])
    y += modal(fall, iron, [0.35, 0.2, 0.1, 0.05], [1.0, 0.6, 0.3, 0.08])
    y += 0.9 * modal(pulse(N, t1, 0.002), [170, 310], [0.08, 0.05], [1.0, 0.5])
    y += 0.12 * burst(N, r, t1, 0.006, 1000, 5000, 0.0012)
    return verb(lp(y, 7000), "room", 0.25)


def _slab(N, r, t0, t1, rise, fall):
    """Stone slab friction between t0 and t1."""
    e = env(N, [(0, 0), (t0, 0), (t0 + rise, 1), (t1 - fall, 0.85), (t1, 0)])
    x = friction(N, r, 80 + 70 * e, [380, 620, 1040, 1650], [0.05, 0.04, 0.03, 0.02], [1.0, 0.8, 0.5, 0.3],
                 (220, 1800), 0.5)
    return lp(x, 2500) * e


def ui_open(r):
    N = n(1.2)
    wh = sweep_band(colored(N, r, 1.0), [0.0, 0.3, 0.7], [120, 380, 160], 1.0) * env(N, [(0, 0), (0.3, 1), (0.75, 0)])
    th = modal(pulse(N, 0.55, 0.006), [85, 140, 230], [0.25, 0.15, 0.08], [1.0, 0.6, 0.3])
    y = fitm(_slab(N, r, 0.0, 0.55, 0.08, 0.1), -14) + fitm(wh, -17) + fitm(th, -16)
    return verb(y, "hall", 0.4)


def ui_close(r):
    N = n(0.8)
    wh = sweep_band(colored(N, r, 1.0), [0.0, 0.28], [420, 130], 0.9) * env(N, [(0, 0), (0.24, 1), (0.34, 0)])
    th = modal(pulse(N, 0.29, 0.006), [90, 150, 250], [0.18, 0.1, 0.06], [1.0, 0.5, 0.3])
    y = fitm(_slab(N, r, 0.0, 0.3, 0.24, 0.03), -15) + fitm(wh, -18) + fitm(th, -15)
    return verb(y, "hall", 0.35)


def ui_deny(r):
    N = n(0.5)
    wood = np.array([205, 470, 790, 1180])
    t60 = [0.09, 0.05, 0.035, 0.025]
    g = [1.0, 0.6, 0.35, 0.2]
    y = modal(pulse(N, 0.0, 0.0015), wood, t60, g)
    y += 0.75 * modal(pulse(N, 0.12, 0.0016), wood * 0.94, t60, g)
    y += 0.04 * (burst(N, r, 0.0, 0.01, 200, 1500, 0.003) + burst(N, r, 0.12, 0.01, 200, 1500, 0.003))
    return verb(lp(y, 2500), "room", 0.25)


def piece_select(r):
    N = n(0.4)
    t = tvec(N)
    e = env(N, [(0, 0), (0.015, 1), (0.07, 0)])
    scrape = lp(friction(N, r, 300, [1200, 2100, 3300], 0.02, [1.0, 0.6, 0.3], (800, 3500), 0.4), 5000) * e
    tk = modal(pulse(N, 0.004, 0.0003), [1700, 2900, 4200], [0.05, 0.03, 0.02], [1.0, 0.5, 0.25])
    body = modal(pulse(N, 0.004, 0.002), [260, 520], [0.04, 0.03], [1.0, 0.5])
    glow = np.sin(TAU * 1318.5 * t) * env(N, [(0, 0), (0.03, 1), (0.25, 0)])
    y = fitm(scrape, -22) + fitm(tk, -18) + fitm(body, -22) + fitm(glow, -27)
    return verb(y, "hall", 0.3)


def _clack(N, at, scale=1.0, hard=0.0002):
    stone = np.array([1180, 2320, 3460, 4980, 6200]) * scale
    y = modal(pulse(N, at, hard), stone, [0.07, 0.05, 0.035, 0.022, 0.015], [1.0, 0.7, 0.5, 0.3, 0.15])
    y += 0.8 * modal(pulse(N, at, 0.0015), np.array([210, 365, 590]) * scale, [0.12, 0.08, 0.05], [0.8, 0.5, 0.3])
    return y


def piece_move(r):
    N = n(1.0)
    e = env(N, [(0, 0), (0.03, 1), (0.17, 0.8), (0.2, 0)])
    slide = friction(N, r, 160, [900, 1500, 2300, 3400], [0.03, 0.025, 0.02, 0.015], [1.0, 0.7, 0.5, 0.3],
                     (500, 4000), 0.5) * e
    clack = _clack(N, 0.205) + 0.1 * burst(N, r, 0.205, 0.004, 1500, 6000, 0.001)
    y = fitm(slide, -25) + fitm(clack, -16)
    return verb(lp(y, 8000), "hall", 0.35)


def _thud(N, r, at, f_sub, body, t60s, sub_t60=0.3, sub_amp=1.0):
    t = tvec(N) - at
    m = t >= 0
    ts = np.maximum(t, 0)
    f = f_sub * (1.0 + 0.6 * np.exp(-ts / 0.05))
    ph = np.cumsum(np.where(m, f, 0)) / SR
    sub = np.sin(TAU * ph) * np.where(m, 10.0 ** (-3.0 * ts / sub_t60), 0) * (1.0 - np.exp(-ts / 0.003))
    y = sub_amp * sub
    y += 3.0 * modal(pulse(N, at, 0.004), body, t60s, np.linspace(1.0, 0.3, len(body)))
    return y


def _pebbles(N, r, t0, count, spread, lo=2000, hi=4500, amp=0.3):
    y = np.zeros(N)
    times = np.sort(t0 + r.exponential(spread, count))
    groups = [np.exp(r.uniform(np.log(lo), np.log(hi), 3)) for _ in range(4)]
    exc = [np.zeros(N) for _ in groups]
    for k, ti in enumerate(times):
        a = amp * r.uniform(0.3, 1.0) * np.exp(-(ti - t0) / (spread * 2.5))
        exc[k % 4] += a * pulse(N, ti, 0.0002)
    for g, e in zip(groups, exc):
        y += modal(e, g, [0.03, 0.02, 0.012], [1.0, 0.6, 0.3])
    return y


def piece_leap(r):
    N = n(1.4)
    at = 0.4
    wh = sweep_band(white(N, r), [0.0, 0.2, 0.38], [350, 1100, 500], 0.8) * env(N, [(0, 0), (0.22, 1), (0.4, 0)])
    thud = _thud(N, r, at, 72.0, [100, 175, 265, 410], [0.3, 0.2, 0.12, 0.08], 0.3, 0.9)
    clack = modal(pulse(N, at, 0.0003), [880, 1760, 2650, 3900], [0.06, 0.045, 0.03, 0.02], [0.6, 0.4, 0.3, 0.15])
    clack += 0.15 * burst(N, r, at, 0.02, 300, 2500, 0.006)
    y = fitm(wh, -20) + fitm(thud, -12) + fitm(clack, -18) + fitm(_pebbles(N, r, at + 0.05, 5, 0.06), -28)
    return verb(lp(y, 8000), "hall", 0.45)


def piece_capture(r):
    N = n(1.8)
    crack = burst(N, r, 0.0, 0.02, 900, 5000, 0.004)
    shatter = np.zeros(N)
    for g in range(3):
        exc = np.zeros(N)
        for ti in r.exponential(0.02, 10):
            exc += r.uniform(0.3, 1.0) * pulse(N, min(ti, 0.12), 0.0002)
        freqs = np.exp(r.uniform(np.log(900), np.log(5200), 5))
        shatter += modal(exc, freqs, r.uniform(0.03, 0.12, 5), r.uniform(0.3, 1.0, 5))
    thump = _thud(N, r, 0.0, 95.0, [120, 210, 330], [0.25, 0.15, 0.1], 0.35, 1.0)
    debris = _pebbles(N, r, 0.08, 26, 0.18)
    dust = lp(colored(N, r, 1.0), 1800) * env(N, [(0, 0), (0.03, 1), (1.2, 0)]) * decay(N, 0.9)
    y = fitm(crack, -21) + fitm(shatter, -12) + fitm(thump, -16) + fitm(debris, -21) + fitm(dust, -28)
    return verb(lp(y, 8500), "hall", 0.45)


def piece_drop(r):
    N = n(2.0)
    at = 0.18
    wh = sweep_band(colored(N, r, 0.5), [0.0, 0.18], [200, 600], 0.9) * env(N, [(0, 0), (0.15, 1), (0.19, 0)])
    thud = _thud(N, r, at, 62.0, [105, 180, 290, 450, 640], [0.35, 0.25, 0.16, 0.1, 0.07], 0.45, 1.1)
    clack = modal(pulse(N, at, 0.0004), [760, 1500, 2300], [0.05, 0.035, 0.02], [1.0, 0.6, 0.3])
    clack += 0.6 * burst(N, r, at, 0.03, 0, 1500, 0.008)
    dust = bp(colored(N, r, 0.7), 300, 2500) * env(N, [(0, 0), (at, 0), (at + 0.02, 1), (1.6, 0)]) * decay(N, 1.0, at)
    pebbles = _pebbles(N, r, at + 0.03, 8, 0.12)
    y = fitm(wh, -26) + fitm(thud, -10) + fitm(clack, -20) + fitm(dust, -20) + fitm(pebbles, -27)
    return verb(lp(y, 8000), "hall", 0.5)


def piece_spawn(r):
    N = n(2.6)
    t = tvec(N)
    rise = env(N, [(0, -5.0), (1.4, 0.0)])
    a = env(N, [(0, 0), (0.6, 1), (1.3, 0.8), (2.1, 0)])
    trem = 1.0 + 0.15 * np.sin(TAU * 6.0 * t)
    y = np.zeros(N)
    for note in ["A4", "E5", "A5", "C6"]:
        f = hz(note) * 2.0 ** (rise / 12.0)
        for cents in (-3.0, 3.0):
            ff = f * 2.0 ** (cents / 1200.0)
            ph = r.uniform()
            for ratio, amp in ((1.0, 1.0), (2.005, 0.25), (3.01, 0.08)):
                y += amp * np.sin(TAU * phase_of(ff * ratio, N, ph * ratio))
    y *= a * trem
    air = sweep_band(white(N, r), [0.0, 1.3], [700, 3500], 1.0) * env(N, [(0, 0), (0.7, 1), (1.6, 0)])
    low = np.sin(TAU * 110.0 * t) * env(N, [(0, 0), (0.5, 1), (2.0, 0)])
    y = fitm(y, -14) + fitm(air, -23) + fitm(low, -22)
    return verb(lp(y, 7500), "cathedral", 0.9)


def swap(r):
    N = n(1.8)
    t = tvec(N)
    a = sweep_band(white(N, r), [0.0, 0.45], [300, 1800], 0.9) * env(N, [(0, 0), (0.3, 1), (0.47, 0)])
    b = sweep_band(white(N, r), [0.3, 0.8], [1800, 300], 0.9) * env(N, [(0, 0), (0.3, 0), (0.58, 1), (0.82, 0)])
    y = fitm(a, -16) + fitm(b, -17)
    vib = 1.0 + 0.01 * np.sin(TAU * 7.0 * t)
    f1 = env(N, [(0, 520), (0.45, 780)]) * vib
    f2 = env(N, [(0, 780), (0.3, 780), (0.8, 520)]) * vib
    for f, e in ((f1, env(N, [(0, 0), (0.25, 1), (0.47, 0)])), (f2, env(N, [(0, 0), (0.3, 0), (0.55, 1), (0.82, 0)]))):
        ph = phase_of(f, N)
        y += fitm(e * (np.sin(TAU * ph) + 0.3 * np.sin(TAU * 2.0 * ph)), -23)
    return verb(lp(y, 7000), "cathedral", 0.7)


def pass_(r):
    N = n(5.0)
    t = tvec(N)
    f0 = 98.0
    ratios = [1, 1.52, 2.0, 2.31, 2.74, 3.18, 3.73, 4.21, 4.92, 5.6]
    amps = [1, 0.6, 0.5, 0.45, 0.35, 0.3, 0.22, 0.16, 0.1, 0.07]
    t60 = [4.0, 3.2, 3.0, 2.6, 2.2, 1.9, 1.6, 1.3, 1.0, 0.8]
    y = np.zeros(N)
    att = 1.0 - np.exp(-t / 0.012)
    for i, (ra, a, d) in enumerate(zip(ratios, amps, t60)):
        bloom = (1.0 - np.exp(-t / 0.12)) if i >= 4 else 1.0
        f = f0 * ra
        y += a * bloom * 10.0 ** (-3.0 * t / d) * (0.6 * np.sin(TAU * (f - 0.15) * t + r.uniform(0, TAU))
                                                   + 0.4 * np.sin(TAU * (f + 0.15) * t + r.uniform(0, TAU)))
    y *= att
    y += 0.4 * burst(N, r, 0.0, 0.05, 0, 300, 0.012) * 3.0
    return verb(lp(y, 2200), "cathedral", 0.95, dry=0.6)


def check_bell(r):
    y = bell(196.0, 7.5, r)
    return verb(lp(y, 3000), "cathedral", 1.2, dry=0.7)


def promote(r):
    N = n(3.4)
    y = np.zeros(N)
    for i, note in enumerate(["D4", "F4", "A4", "D5"]):
        at = 0.12 * i
        m = N - n(at)
        scoop = 2.0 ** (env(m, [(0, -1.0), (0.1, 0.0)]) / 12.0)
        c = choir([hz(note)], m, r, "a", glide=scoop, pans=[0.0]).sum(0)
        c *= env(m, [(0, 0), (0.25, 1), (1.5 - at, 0.85), (2.7 - at, 0)])
        place(y, c, at)
    t = tvec(N)
    sh = sum(np.sin(TAU * hz(nn) * t + r.uniform(0, TAU)) for nn in ("D6", "A6")) * (1 + 0.3 * np.sin(TAU * 7 * t))
    sh *= env(N, [(0, 0), (0.3, 0), (0.8, 1), (1.6, 0)])
    c1, c2 = np.zeros(N), np.zeros(N)
    place(c1, chime(hz("D6"), 2.8, r), 0.5)
    place(c2, chime(hz("A5"), 2.6, r), 0.62)
    y = fitm(y, -16) + fitm(sh, -27) + fitm(c1, -16) + fitm(c2, -19)
    return verb(lp(y, 7500), "cathedral", 0.8)


def level_up(r):
    N = n(3.6)
    notes = [hz(x) for x in ("D3", "A3", "D4", "F#4", "A4")]
    c = choir(notes, N, r, "a", pans=[0, -0.3, 0.3, -0.2, 0.2]).sum(0)
    c *= env(N, [(0, 0), (0.5, 1), (1.6, 0.9), (3.0, 0)])
    t = tvec(N)
    sub = np.sin(TAU * hz("D2") * t) * env(N, [(0, 0), (0.5, 1), (2.8, 0)])
    chimes = [np.zeros(N) for _ in range(3)]
    place(chimes[0], chime(hz("D6"), 3.0, r), 0.45)
    place(chimes[1], chime(hz("A6"), 2.6, r, T=2.0), 0.55)
    place(chimes[2], chime(hz("F#6"), 2.4, r, T=1.8), 0.68)
    y = fitm(c, -14) + fitm(sub, -23) + fitm(chimes[0], -16) + fitm(chimes[1], -19) + fitm(chimes[2], -22)
    return verb(lp(y, 8000), "cathedral", 0.8)


def _coin(N, r, at, amp):
    y = np.zeros(N)
    for k in range(2):
        f0 = r.uniform(2300, 3600)
        modes = f0 * np.array([1.0, 1.73, 2.33, 3.9])
        y += (1.0 if k == 0 else 0.6) * modal(pulse(N, at, 0.0002), modes,
                                              [r.uniform(0.25, 0.5), 0.2, 0.15, 0.08], [1.0, 0.55, 0.4, 0.15])
    y += 0.08 * burst(N, r, at, 0.0015, 2000, 7000, 0.0005)
    return amp * y


def gold(r):
    N = n(1.0)
    y = np.zeros(N)
    for at, a in zip([0.0, 0.055, 0.14, 0.19, 0.31], [1.0, 0.7, 0.85, 0.5, 0.4]):
        y += _coin(N, r, at + r.uniform(-0.008, 0.008) * (at > 0), a)
    return verb(hp(lp(y, 9000), 400), "room", 0.3)


def coin_tick(r):
    N = n(0.35)
    return verb(hp(lp(_coin(N, r, 0.0, 1.0), 9500), 600), "room", 0.18)


def shop_buy(r):
    N = n(1.2)
    y = np.zeros(N)
    for at, a in zip([0.0, 0.05, 0.11], [1.0, 0.75, 0.6]):
        y += _coin(N, r, at, a)
    coins = hp(lp(y, 9000), 400)
    t1 = 0.29
    latch = 0.3 * modal(pulse(N, t1 - 0.03, 0.00015), [1500, 4100], [0.05, 0.03], [1.0, 0.4])
    latch += modal(pulse(N, t1, 0.00015), [640, 1764, 3459, 5718], [0.4, 0.22, 0.12, 0.05], [1.0, 0.6, 0.3, 0.08])
    latch += 1.2 * modal(pulse(N, t1, 0.003), [140, 260], [0.1, 0.06], [1.0, 0.5])
    y = fitm(coins, -16) + fitm(latch, -15)
    return verb(lp(y, 8000), "room", 0.3)


def relic(r):
    N = n(4.8)
    t = tvec(N)
    swell = rev_swell(N, r, 0.0, 0.25, 300, 1500)
    at = 0.25
    m = N - n(at)
    tm = tvec(m)
    f0 = hz("D4")
    ch = np.zeros(m)
    for ratio, a, d in [(1.0, 1.0, 4.0), (1.19, 0.3, 3.0), (2.71, 0.5, 2.5), (5.15, 0.25, 1.2), (8.17, 0.1, 0.6)]:
        e = 10.0 ** (-3.0 * tm / d) * (1.0 - np.exp(-tm / 0.002))
        fr = f0 * ratio
        ch += a * e * (0.6 * np.sin(TAU * (fr - 0.35) * tm) + 0.4 * np.sin(TAU * (fr + 0.35) * tm + 1.0))
    ch += 0.2 * np.sin(TAU * f0 * 2 * tm + 2.5 * np.exp(-tm / 0.03) * np.sin(TAU * f0 * 3.7 * tm)) * np.exp(-tm / 0.05)
    c = np.zeros(N)
    place(c, ch, at)
    sub = np.sin(TAU * hz("D2") * t) + 0.15 * np.sin(TAU * 2 * hz("D2") * t)
    sub *= env(N, [(0, 0), (at, 0), (at + 0.03, 1), (4.5, 0)]) * decay(N, 3.0, at)
    d3 = np.sin(TAU * hz("D3") * t) * env(N, [(0, 0), (at, 0), (at + 0.03, 1), (3.0, 0)])
    y = fitm(swell, -24) + fitm(c, -14) + fitm(sub, -16) + fitm(d3, -21)
    return verb(y, "cathedral", 1.0)


def event_page(r):
    N = n(0.8)
    dens = env(N, [(0, 0.2), (0.02, 1), (0.12, 0.6), (0.4, 0.3), (0.45, 0)])
    hits = (r.random(N) < 350.0 * dens / SR) * r.exponential(1.0, N)
    crk = peak_bp(hits, 3200.0, 1.5) + 0.6 * peak_bp(hits, 2100.0, 2.0)
    sw = sweep_band(white(N, r), [0.08, 0.45], [3000, 1200], 1.3) * env(N, [(0, 0), (0.08, 0.2), (0.25, 1), (0.46, 0)])
    flap = modal(pulse(N, 0.44, 0.003), [180, 320], [0.05, 0.03], [1.0, 0.5]) + 0.17 * burst(N, r, 0.44, 0.03, 0, 1500, 0.006)
    y = fitm(crk, -22) + fitm(sw, -16) + fitm(flap, -22)
    return verb(lp(y, 7500), "room", 0.25)


def map_step(r):
    N = n(0.6)
    heel = modal(pulse(N, 0.0, 0.004), [110, 210, 340], [0.09, 0.06, 0.04], [1.0, 0.6, 0.35])
    toe = modal(pulse(N, 0.07, 0.003), [150, 290, 480], [0.07, 0.05, 0.03], [1.0, 0.6, 0.3])
    grit = friction(N, r, 400, [1500, 2600, 3800], 0.008, [1.0, 0.6, 0.3], (600, 4000), 0.3)
    g1 = grit * env(N, [(0, 0), (0.003, 1), (0.05, 0)])
    g2 = grit[::-1] * env(N, [(0, 0), (0.07, 0), (0.073, 1), (0.11, 0)])
    y = fitm(heel, -14) + fitm(toe, -17) + fitm(g1, -22) + fitm(g2, -27)
    return verb(lp(y, 6000), "hall", 0.35)


def clock_low(r):
    """Heartbeat, exactly one 0.8 s beat, periodic."""
    N = n(0.8)
    y = np.zeros(N)

    def beat(f0, amp):
        m = n(0.4)
        t = tvec(m)
        f = f0 * (1.0 + 0.6 * np.exp(-t / 0.02))
        b = np.sin(TAU * np.cumsum(f) / SR) * (1.0 - np.exp(-t / 0.004)) * np.exp(-t / 0.07)
        b += 0.25 * np.sin(TAU * np.cumsum(f * 2.1) / SR) * np.exp(-t / 0.03)
        b += 0.3 * lp(r.standard_normal(m) * np.exp(-t / 0.006), 400)
        return amp * b

    for at, f0, a in ((0.05, 52.0, 1.0), (0.31, 60.0, 0.75)):
        b = beat(f0, a)
        s = n(at)
        idx = (s + np.arange(len(b))) % N
        np.add.at(y, idx, b)
    y = circ(lambda v: lp(v, 600, 2), y, N)
    return verb_loop(y, "room", 0.12)[0]


def engine_think(r):
    """Breathy whisper, exactly 2.0 s, periodic."""
    N = n(2.0)
    t = tvec(N)
    nz = white(N, r)

    def vowel(F, B, G):
        def g(f):
            out = np.zeros_like(f)
            for fc, bw, gg in zip(F, B, G):
                out += db(gg) / np.sqrt(1.0 + ((f - fc) / (bw / 2)) ** 2)
            return out
        return fft_filter(nz, g, circular=True)

    ha = vowel([700, 1200, 2600], [260, 300, 400], [0, -4, -14])
    oo = vowel([350, 800, 2300], [200, 250, 400], [0, -6, -18])
    sh = vowel([2900, 4000], [900, 1200], [-10, -14])
    w1 = 0.5 + 0.5 * np.sin(TAU * t / 2.0)
    w2 = 0.5 + 0.5 * np.sin(TAU * 2.0 * t / 2.0 + 1.3)
    y = ha * w1 + oo * (1.0 - w1) + 0.5 * sh * w2 ** 2
    bumps = np.zeros(N)
    for c, w, a in ((0.15, 0.12, 1.0), (0.55, 0.18, 0.7), (0.95, 0.1, 0.9), (1.35, 0.22, 0.6), (1.75, 0.14, 0.8)):
        d = np.abs(t - c)
        d = np.minimum(d, 2.0 - d)
        bumps += a * np.exp(-0.5 * (d / w) ** 2)
    amp = (0.3 + bumps) * (0.8 + 0.2 * np.sin(TAU * t / 2.0))
    y = fft_filter(y * amp, band_gain(150, 4500), circular=True)
    return verb_loop(y, "room", 0.3)[0]


def win_sting(r):
    N = n(4.4)
    y = np.zeros(N)
    chords = [(0.0, 0.95, ["Bb2", "F3", "Bb3", "D4", "F4"]), (0.9, 1.75, ["C3", "G3", "C4", "E4", "G4"]),
              (1.7, 3.6, ["D2", "D3", "A3", "D4", "F#4", "A4"])]
    for t0, t1, notes in chords:
        m = n(t1 - t0 + 0.4)
        e = env(m, [(0, 0), (0.06, 1), (t1 - t0, 0.95), (t1 - t0 + 0.35, 0)])
        c = sum(organ(hz(x), m, r) for x in notes) * e
        place(y, c, t0)
    m = N - n(1.7)
    c = choir([hz(x) for x in ("D4", "F#4", "A4", "D5")], m, r, "a").sum(0)
    ch, dr = np.zeros(N), np.zeros(N)
    place(ch, c * env(m, [(0, 0), (0.4, 1), (1.9, 0.9), (2.5, 0)]), 1.7)
    place(dr, drum(hz("D2"), 2.0, r, drop=0.1), 1.7)
    y = fitm(y, -14) + fitm(ch, -17) + fitm(dr, -21)
    return verb(lp(y, 7000), "cathedral", 0.8)


def loss_sting(r):
    N = n(4.4)
    t = tvec(N)
    b = bell(hz("D3"), 4.4, r, T=7.0, bright=0.7)
    m = N
    glide = 2.0 ** (env(m, [(0, 0), (0.4, 0), (3.6, -5)]) / 12.0)
    dr = np.zeros(m)
    for note in ("D3", "A3", "D4"):
        for k in range(5):
            dr += saw(hz(note) * glide * 2.0 ** ((k - 2) * 6 / 1200.0), m, r.uniform())
    dr = sweep_lp(dr, [0.0, 1.0, 3.8], [1800, 1400, 300])
    dr *= env(m, [(0, 0), (0.3, 0), (1.0, 1), (3.0, 0.8), (4.2, 0)])
    sub = np.sin(TAU * np.cumsum(hz("D2") * glide) / SR) * env(N, [(0, 0), (0.5, 1), (3.0, 0.8), (4.2, 0)])
    y = fitm(b, -14) + fitm(dr, -17) + fitm(sub, -19)
    return verb(lp(y, 5000), "cathedral", 1.0)


SFX = {
    # name: (fn, suggested volume_db, loop, max duration s)
    "ui_hover": (ui_hover, -10.0, False, 0.25),
    "ui_click": (ui_click, -3.0, False, 0.6),
    "ui_open": (ui_open, -2.0, False, 1.4),
    "ui_close": (ui_close, -3.0, False, 1.0),
    "ui_deny": (ui_deny, -2.0, False, 0.6),
    "piece_select": (piece_select, -4.0, False, 0.5),
    "piece_move": (piece_move, 0.0, False, 1.0),
    "piece_leap": (piece_leap, 0.0, False, 1.5),
    "piece_capture": (piece_capture, 0.0, False, 2.0),
    "piece_drop": (piece_drop, -1.0, False, 2.2),
    "piece_spawn": (piece_spawn, -2.0, False, 3.5),
    "swap": (swap, -2.0, False, 2.5),
    "pass": (pass_, -3.0, False, 6.0),
    "check_bell": (check_bell, -6.0, False, 9.0),
    "promote": (promote, -1.0, False, 4.5),
    "level_up": (level_up, -1.0, False, 4.5),
    "gold": (gold, -4.0, False, 1.1),
    "coin_tick": (coin_tick, -8.0, False, 0.6),
    "shop_buy": (shop_buy, -3.0, False, 1.3),
    "relic": (relic, -1.0, False, 6.0),
    "event_page": (event_page, -3.0, False, 0.9),
    "map_step": (map_step, -2.0, False, 0.8),
    "clock_low": (clock_low, -6.0, True, None),
    "win_sting": (win_sting, 0.0, False, 4.0),
    "loss_sting": (loss_sting, 0.0, False, 4.0),
    "engine_think": (engine_think, -14.0, True, None),
}

PUNCH_DB = {"ui_click": 3.0, "ui_deny": 3.0, "piece_select": 3.0, "piece_move": 4.0, "piece_leap": 3.0,
            "piece_capture": 4.0, "piece_drop": 2.0, "map_step": 3.0, "gold": 2.0, "coin_tick": 2.0, "shop_buy": 2.0}

# ----------------------------------------------------------------------------
# music + ambience (stereo loops; everything wraps around the loop length)


class Loop:
    def __init__(self, sec: float):
        self.N = n(sec)
        self.x = np.zeros((2, self.N))

    def add(self, sig, at, p=0.0, gain=1.0):
        if sig.ndim == 1:
            sig = pan(sig, p)
        s = n(at) % self.N
        i = 0
        L = sig.shape[1]
        while i < L:
            k = min(L - i, self.N - s)
            self.x[:, s:s + k] += gain * sig[:, i:i + k]
            i += k
            s = 0


def drone(notes, N, r, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)), drift=0.0015, cycles=8):
    """Periodic soft drone: whole-cycle partials with slow periodic amplitude drift (stereo)."""
    t = tvec(N)
    out = np.zeros((2, N))
    for i, note in enumerate(notes):
        f = hz(note) if isinstance(note, str) else note
        for c in range(2):
            y = np.zeros(N)
            for h, a in harmonics:
                ff = qf(f * h * (1.0 + drift * (c - 0.5)), N)
                y += a * np.sin(TAU * ff * t + r.uniform(0, TAU))
            out[c] += y * (0.7 + 0.3 * pnoise(N, r, cycles))
    return out


def fit(x, target):
    """Scale a stem to a target loudness (stems are balanced by measured LUFS, not by guessed gains)."""
    return x * db(target - lufs(x))


def periodic_noise(N, r, lo, hi, exponent=0.0):
    x = colored(N, r, exponent) if exponent else r.standard_normal(N)
    y = fft_filter(x, band_gain(lo, hi), circular=True)
    return y / (np.std(y) + 1e-12)


def music_title(r):
    """Slow mournful choir (12 chords x 8 s) over a D drone, distant bells every 24 s."""
    L, seg = 96.0, 8.0
    pad, far = Loop(L), Loop(L)
    chords = [
        ["D3", "A3", "D4", "F4"], ["Bb2", "F3", "D4", "F4"], ["G2", "D3", "Bb3", "D4"], ["A2", "E3", "C#4", "E4"],
        ["D3", "A3", "D4", "F4"], ["C3", "A3", "C4", "F4"], ["Bb2", "G3", "D4", "G4"], ["A2", "E3", "D4", "E4"],
        ["Bb2", "F3", "D4", "F4"], ["G2", "G3", "Bb3", "D4"], ["Eb3", "G3", "Bb3", "Eb4"], ["A2", "E3", "C#4", "E4"],
    ]
    for i, notes in enumerate(chords):
        m = n(seg + 3.0)
        e = env(m, [(0, 0), (2.5, 1), (7.0, 0.9), (10.5, 0)])
        c = choir([hz(x) for x in notes], m, r, "a" if i % 2 == 0 else "o", pans=[0.0, -0.35, 0.35, -0.15])
        pad.add(c * e, i * seg - 1.0, gain=0.5)
    pad.x += 0.07 * drone(["D2"], pad.N, r)
    for at, note, g in ((4.0, "D3", 0.5), (28.0, "A2", 0.4), (52.0, "D3", 0.5), (76.0, "Bb2", 0.35)):
        b = lp(bell(hz(note), 10.0, r, bright=0.6), 2200)
        far.add(b, at, r.uniform(-0.4, 0.4), g)
    return verb_loop(pad.x, "cathedral", 1.0) + verb_loop(far.x, "cathedral", 1.2, dry=0.3)


def music_map(r):
    """Low string pad + D drone, sparse dark piano plucks from the current chord."""
    L, seg = 90.0, 11.25
    pad, pl = Loop(L), Loop(L)
    chords = [
        ["D2", "A2", "F3", "A3"], ["Bb1", "F2", "D3", "A3"], ["G1", "D2", "Bb2", "G3"], ["A1", "E2", "C#3", "E3"],
        ["D2", "A2", "F3", "A3"], ["C2", "G2", "E3", "G3"], ["Bb1", "F2", "D3", "F3"], ["A1", "E2", "C#3", "A3"],
    ]
    for i, notes in enumerate(chords):
        m = n(seg + 3.5)
        e = env(m, [(0, 0), (3.5, 1), (seg, 0.9), (seg + 3.5, 0)])
        s = strings([hz(x) for x in notes], m, r, cutoff=900.0, pans=[0.0, -0.4, 0.4, -0.2])
        pad.add(s * e, i * seg - 1.75, gain=0.3)
    pad.x += 0.12 * drone(["D1", "D2", "A2"], pad.N, r, harmonics=((1, 1.0), (2, 0.3)))
    pad.x += 0.05 * np.stack([periodic_noise(pad.N, r, 30, 110, 2.0) for _ in range(2)])
    t = 2.0
    while t < L - 1.0:
        notes = chords[int(t // seg) % len(chords)]
        pool = sorted({hz(x) * (2 if hz(x) < 100 else 1) for x in notes})
        f = pool[r.integers(len(pool))]
        p = r.uniform(-0.4, 0.4)
        pl.add(piano(f, 6.0, r, vel=r.uniform(0.3, 0.55)), t, p, 0.35)
        if r.random() < 0.25:
            pl.add(piano(f * 1.5, 6.0, r, vel=0.3), t + r.uniform(0.15, 0.4), -p, 0.2)
        t += r.uniform(3.0, 6.5)
    return verb_loop(pad.x, "cathedral", 0.7) + verb_loop(pl.x, "cathedral", 1.0)


def _triad(root: str):
    return {"D": ["D3", "F3", "A3"], "Bb": ["D3", "F3", "Bb3"], "A": ["C#3", "E3", "A3"], "G": ["D3", "G3", "Bb3"],
            "Eb": ["Eb3", "G3", "Bb3"], "C": ["C3", "E3", "G3"]}[root]


def music_fight(r):
    """90 BPM, 32 bars: 8th-note bass pulse, timpani, chess-clock ticks, tremolo strings, bells."""
    bpm, bars = 90.0, 32
    beat = 60.0 / bpm
    bar = 4 * beat
    L = bars * bar
    close, far = Loop(L), Loop(L)
    roots = ["D", "D", "Bb", "A", "D", "D", "G", "A"]
    bass_oct = {"D": "D2", "Bb": "Bb1", "A": "A1", "G": "G1"}
    acc = [1.0, 0.5, 0.75, 0.5, 0.85, 0.5, 0.75, 0.55]
    for b in range(bars):
        root = roots[b // 4]
        f = hz(bass_oct[root])
        for e8 in range(8):
            at = b * bar + e8 * beat / 2
            ff = f * (2.0 if e8 in (2, 6) else 1.0)
            close.add(bass_pluck(ff, beat / 2 * 0.9, r, bright=0.6 + 0.5 * acc[e8]), at, 0.0, 0.3 * acc[e8])
            tk = tick(1900.0 if e8 % 2 == 0 else 1500.0, r, 0.35 * r.uniform(0.8, 1.2))
            close.add(tk, at, 0.35 if e8 % 2 else -0.35)
            if b >= 16:
                close.add(tick(1700.0, r, 0.15), at + beat / 4, 0.5)
        close.add(drum(f * 2 if f < 70 else f, 2.0, r, drop=0.12), b * bar, 0.0, 0.32)
        if b % 2 == 1:
            close.add(drum(f * 2 if f < 70 else f, 1.5, r, drop=0.12), b * bar + 2 * beat, 0.0, 0.18)
    t = tvec(n(4 * bar + 1.5))
    for s in range(8):
        m = len(t)
        e = env(m, [(0, 0), (1.5, 1), (4 * bar, 0.9), (4 * bar + 1.5, 0)])
        trem = 0.75 + 0.25 * np.sin(TAU * (bpm / 60.0 * 4) * t)
        st = strings([hz(x) for x in _triad(roots[s])], m, r, cutoff=1400.0, pans=[-0.4, 0.0, 0.4])
        far.add(st * e * trem, s * 4 * bar - 0.75, gain=0.16)
        if s in (2, 3, 6, 7):
            hi = strings([hz("A4"), hz("Bb4")], m, r, cutoff=2500.0, n_saw=3, pans=[-0.6, 0.6])
            far.add(hi * e, s * 4 * bar - 0.75, gain=0.03)
    for b, note, g in ((0, "D4", 0.3), (8, "A3", 0.2), (16, "D4", 0.3), (24, "A3", 0.2)):
        far.add(lp(bell(hz(note), 7.0, r, T=5.0, bright=0.7), 3000), b * bar, r.uniform(-0.5, 0.5), g)
    for b in (14, 30):
        far.add(rev_swell(n(2 * bar), r, 0.0, 2 * bar, 400, 3000), b * bar, 0.0, 0.12)
    mix = verb_loop(close.x, "hall", 0.35) + verb_loop(far.x, "cathedral", 0.9)
    return np.roll(mix, n(beat / 8), axis=1)


def brass(f, dur, r, peak_at, cut_lo=250.0, cut_hi=1800.0):
    N = n(dur)
    y = sum(saw(f * 2.0 ** (c / 1200.0), N, r.uniform()) for c in (-6.0, 0.0, 5.0))
    y += 0.6 * saw(f * 0.5, N, r.uniform())
    y = sweep_lp(y, [0.0, peak_at, dur], [cut_lo, cut_hi, cut_lo * 1.2])
    return y * env(N, [(0, 0), (peak_at, 1), (dur, 0)])


def music_boss(r):
    """120 BPM, 40 bars: organ pedal D/A, organ chords, low brass swells, driving pulse, choir stabs."""
    bpm, bars = 120.0, 40
    beat = 60.0 / bpm
    bar = 4 * beat
    L = bars * bar
    close, far = Loop(L), Loop(L)
    prog = ["D", "Bb", "Eb", "A", "D", "G", "Eb", "A", "Bb", "A"]
    bass = {"D": "D2", "Bb": "Bb1", "Eb": "Eb2", "A": "A1", "G": "G1"}
    upper = {"D": ["D4", "F4", "A4"], "Bb": ["D4", "F4", "Bb4"], "Eb": ["Eb4", "G4", "Bb4"],
             "A": ["C#4", "E4", "A4"], "G": ["D4", "G4", "Bb4"]}
    N = close.N
    pedal = sum(organ(hz(x), N, r, periodic=True) for x in ("D2", "A2"))
    far.x += 0.07 * np.stack([pedal, pedal]) * (0.85 + 0.15 * pnoise(N, r, 10))
    for i, ch in enumerate(prog):
        t0 = i * 4 * bar
        m = n(4 * bar + 0.6)
        e = env(m, [(0, 0), (0.08, 1), (4 * bar - 0.1, 0.9), (4 * bar + 0.5, 0)])
        org = sum(organ(hz(x), m, r) for x in upper[ch]) * e
        far.add(org, t0, 0.0, 0.07)
        f = hz(bass[ch])
        sw = brass(f, 7.0, r, 3.5) + 0.7 * brass(f * 1.5, 7.0, r, 3.5)
        far.add(sw, t0 + 0.5, r.uniform(-0.3, 0.3), 0.12)
        if i >= 4:
            m2 = n(1.4)
            c = choir([hz(x) for x in upper[ch]] + [hz(bass[ch]) * 2], m2, r, "a")
            far.add(c * env(m2, [(0, 0), (0.06, 1), (0.5, 0.7), (1.4, 0)]), t0, gain=0.25)
        for b in range(4):
            bb = i * 4 + b
            for e8 in range(8):
                at = bb * bar + e8 * beat / 2
                a = [1.0, 0.55, 0.7, 0.55, 0.9, 0.55, 0.7, 0.6][e8]
                ff = f * (2.0 if e8 % 4 == 3 else 1.0)
                close.add(bass_pluck(ff, beat / 2 * 0.85, r, bright=0.7 + 0.6 * a), at, 0.0, 0.3 * a)
                close.add(tick(2000.0 if e8 % 2 == 0 else 1600.0, r, 0.2), at, 0.4 if e8 % 2 else -0.4)
                if bb >= 20:
                    close.add(bass_pluck(ff, beat / 4 * 0.8, r, bright=0.5), at + beat / 4, 0.0, 0.1)
            for bt, g in ((0.0, 1.0), (1.5, 0.5), (2.0, 0.8), (3.5, 0.55)):
                close.add(drum(55.0, 1.2, r, drop=0.45, noise=0.5, noise_hi=900.0), bb * bar + bt * beat, 0.0, 0.45 * g)
    for b, note in ((0, "D3"), (20, "A2")):
        far.add(lp(bell(hz(note), 8.0, r, bright=0.6), 2500), b * bar, 0.3, 0.35)
    far.add(rev_swell(n(2 * bar), r, 0.0, 2 * bar, 300, 2500), (bars - 2) * bar, 0.0, 0.15)
    mix = verb_loop(close.x, "hall", 0.35) + verb_loop(far.x, "cathedral", 0.6)
    return np.roll(mix, n(beat / 8), axis=1)


def _crackles(N, r, rate_mod):
    """One channel of fire crackle: bursty Poisson clicks through small resonances, plus rare pops."""
    rate = 4.0 + 30.0 * rate_mod
    hits = (r.random(N) < rate / SR) * np.minimum(r.pareto(3.0, N), 3.0)
    grp = r.integers(0, 4, N)
    y = np.zeros(N)
    for g, (fc, q) in enumerate(((1400, 2.0), (2200, 2.5), (3100, 3.0), (4100, 3.0))):
        e = hits * (grp == g)
        y += circ(lambda v: modal(v, [fc, fc * 1.37], [0.008, 0.006], [1.0, 0.5]) + 0.5 * peak_bp(v, fc, q), e, n(0.1))
    pops = (r.random(N) < 0.25 / SR) * r.uniform(1.0, 2.5, N)
    y += circ(lambda v: modal(v, [420, 690, 1100], [0.035, 0.025, 0.015], [1.0, 0.6, 0.3]), pops, n(0.2))
    p = np.percentile(np.abs(y), 99.9)
    y = 2.0 * p * np.tanh(y / (2.0 * p))
    return circ(lambda v: lp(v, 7000), y, n(0.05))


def music_campfire(r):
    """Fire bed (roar, flutter, hiss, crackles, pops) over a warm F drone and soft string/hum pad."""
    L, seg = 90.0, 22.5
    N = n(L)
    fire = np.zeros((2, N))
    roar_mod = 0.65 + 0.35 * pnoise(N, r, 90)
    dens = (0.5 + 0.5 * pnoise(N, r, 45)) ** 2
    for c in range(2):
        roar = periodic_noise(N, r, 40, 600, 1.5) * roar_mod
        flutter = periodic_noise(N, r, 400, 1600) * (0.5 + 0.5 * pnoise(N, r, 360)) ** 2
        hiss = periodic_noise(N, r, 2500, 6000) * (0.5 + 0.5 * pnoise(N, r, 180))
        fire[c] = fit(roar, -25) + fit(flutter, -28) + fit(hiss, -38) + fit(_crackles(N, r, dens), -25)
    fire = limit_loop(fire, np.max(np.abs(fire)) * db(-6))
    pad, hum = Loop(L), Loop(L)
    chords = [["F2", "C3", "A3"], ["D2", "A2", "F3"], ["Bb1", "F2", "D3"], ["C2", "G2", "E3"]]
    hums = [["A3", "C4"], ["A3", "D4"], ["F3", "D4"], ["G3", "C4"]]
    for i, (ch, hm) in enumerate(zip(chords, hums)):
        m = n(seg + 6.0)
        e = env(m, [(0, 0), (6.0, 1), (seg, 0.9), (seg + 6.0, 0)])
        pad.add(strings([hz(x) for x in ch], m, r, cutoff=700.0, pans=[0.0, -0.4, 0.4]) * e, i * seg - 3.0)
        hum.add(choir([hz(x) for x in hm], m, r, "u", vib=0.003, breath=0.03, pans=[-0.3, 0.3]) * e, i * seg - 3.0)
    dr = drone(["F2", "C3"], N, r, harmonics=((1, 1.0), (2, 0.35), (3, 0.12), (4, 0.05)))
    warm = fit(dr, -27) + fit(pad.x, -25) + fit(hum.x, -31)
    return verb_loop(fire, "hall", 0.2) + verb_loop(warm, "hall", 0.55)


def caw(r):
    f0 = r.uniform(480, 620)
    dur = r.uniform(0.28, 0.42)
    N = n(dur + 0.05)
    t = tvec(N)
    f = f0 * env(N, [(0, 1.08), (0.3 * dur, 1.0), (dur, 0.85)]) * (1.0 + 0.012 * np.sin(TAU * 38.0 * t))
    src = saw(f, N, r.uniform()) * (1.0 + 0.6 * np.sin(TAU * 52.0 * t)) + 0.35 * r.standard_normal(N)
    y = sum(db(g) * peak_bp(src, F, F / bw) for F, g, bw in ((1150, 0, 300), (1750, -3, 400), (2600, -9, 500)))
    y += 0.2 * lp(src, 900)
    return y * env(N, [(0, 0), (0.025, 1), (0.35 * dur, 0.9), (dur, 0)])


def creak(r, dur):
    N = n(dur)
    rate = env(N, [(0, 30), (0.4 * dur, 70), (dur, 40)]) * (1.0 + 0.15 * pnoise(N, r, 12))
    ph = np.cumsum(rate) / SR
    ticks = np.diff(np.floor(ph), prepend=0.0) > 0
    k = r.uniform(0.85, 1.2)
    y = modal(ticks * r.uniform(0.5, 1.0, N), np.array([420, 880, 1350, 2100]) * k,
              [0.04, 0.03, 0.025, 0.015], [1.0, 0.7, 0.4, 0.2])
    return y * env(N, [(0, 0), (0.15 * dur, 1), (0.8 * dur, 0.8), (dur, 0)])


def clink(r):
    N = n(0.4)
    f0 = r.uniform(1400, 2400)
    return modal(pulse(N, 0.0, 0.0002), f0 * np.array([1.0, 2.7, 5.2]), [0.25, 0.12, 0.06], [1.0, 0.4, 0.15])


def ambience_wind(r):
    """Gusty wind through ruins: noise bands under a gust envelope, drifting whistles, crows, chains."""
    L = 100.0
    N = n(L)
    gust = 0.5 + 0.5 * pnoise(N, r, 25)
    wind = np.zeros((2, N))
    for c in range(2):
        g = np.roll(gust, c * n(0.7))
        body = periodic_noise(N, r, 100, 900, 1.0) * (0.25 + 0.75 * g ** 1.5)
        bright = periodic_noise(N, r, 700, 2800) * g ** 2.5
        rumble = periodic_noise(N, r, 30, 90, 2.0)
        whistle = np.zeros(N)
        for fc in (520, 610, 700, 820, 950):
            sig = fc / 40.0
            band = fft_filter(r.standard_normal(N), lambda f: np.exp(-0.5 * ((f - fc) / sig) ** 2), circular=True)
            band /= np.std(band) + 1e-12
            whistle += band * np.maximum(0.0, pnoise(N, r, 30)) ** 2 * g
        wind[c] = fit(body, -21) + fit(bright, -29) + fit(rumble, -31) + fit(whistle, -29)
    crows, chains = Loop(L), Loop(L)
    for at in (9.0, 33.0, 61.0, 84.0):
        p = r.uniform(-0.8, 0.8)
        tt = at
        for _ in range(int(r.integers(2, 5))):
            crows.add(lp(caw(r), 2500), tt, p, r.uniform(0.7, 1.0))
            tt += r.uniform(0.42, 0.6)
    for at in (17.0, 46.0, 72.0, 95.0):
        p = r.uniform(-0.7, 0.7)
        d = r.uniform(1.0, 2.0)
        chains.add(creak(r, d), at, p)
        for k in range(int(r.integers(2, 5))):
            chains.add(clink(r), at + d * r.uniform(0.2, 1.1), p + r.uniform(-0.1, 0.1), 0.6)
    ev = fit(crows.x, -33) + fit(chains.x, -35)
    return wind + verb_loop(ev, "cathedral", 1.4, dry=0.5)


MUSIC = {
    # name: (fn, suggested volume_db, category, target LUFS)
    "music_title": (music_title, 0.0, "music", MUSIC_LUFS),
    "music_map": (music_map, 0.0, "music", MUSIC_LUFS),
    "music_fight": (music_fight, 0.0, "music", MUSIC_LUFS),
    "music_boss": (music_boss, 0.0, "music", MUSIC_LUFS),
    "music_campfire": (music_campfire, 0.0, "music", MUSIC_LUFS),
    "ambience_wind": (ambience_wind, -10.0, "ambience", MUSIC_LUFS),
}


# ----------------------------------------------------------------------------
# driver


def render_one(name: str) -> dict:
    t0 = time.perf_counter()
    r = rng(name)
    if name in SFX:
        fn, vol, loop, max_dur = SFX[name]
        x = finish_sfx(fn(r), loop=loop, max_dur=max_dur, punch=PUNCH_DB.get(name, 0.0))
        path = SFX_DIR / f"{name}.wav"
        write_wav(path, x)
        meta = {"path": f"res://assets/audio/sfx/{name}.wav", "category": "sfx", "duration": round(len(x) / SR, 3),
                "volume_db": vol, "loop": loop}
    else:
        fn, vol, cat, target = MUSIC[name]
        x = finish_loop(fn(r), target)
        path = MUSIC_DIR / f"{name}.ogg"
        write_ogg(path, x, name)
        meta = {"path": f"res://assets/audio/music/{name}.ogg", "category": cat,
                "duration": round(x.shape[1] / SR, 3), "volume_db": vol, "loop": True,
                "loop_samples": int(x.shape[1])}
    meta["peak_dbfs"] = round(peak_db(x), 2)
    meta["lufs"] = round(lufs(x), 1)
    meta["_render_s"] = round(time.perf_counter() - t0, 2)
    return {name: meta}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="")
    ap.add_argument("--group", choices=["sfx", "music"])
    ap.add_argument("--verify-only", action="store_true")
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--jobs", type=int, default=min(6, os.cpu_count() or 1))
    args = ap.parse_args()
    names = list(SFX) + list(MUSIC)
    if args.group:
        names = list(SFX) if args.group == "sfx" else list(MUSIC)
    if args.only:
        want = [s.strip() for s in args.only.split(",") if s.strip()]
        bad = [w for w in want if w not in names]
        if bad:
            sys.exit(f"unknown sounds: {bad}")
        names = want
    t0 = time.perf_counter()
    if not args.verify_only:
        meta = json.loads(META_PATH.read_text())["files"] if META_PATH.exists() else {}
        order = sorted(names, key=lambda k: 0 if k in MUSIC else 1)
        with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as ex:
            for res in ex.map(render_one, order):
                for k, v in res.items():
                    print(f"  {k:16s} {v['duration']:7.2f}s  peak {v['peak_dbfs']:6.2f} dBFS  "
                          f"{v['lufs']:6.1f} LUFS  ({v.pop('_render_s')}s)", flush=True)
                    meta[k] = v
        known = set(SFX) | set(MUSIC)
        meta = {k: meta[k] for k in sorted(meta) if k in known}
        META_PATH.write_text(json.dumps({"generator": "tools/audio/make_audio.py", "sample_rate": SR,
                                         "files": meta}, indent=2) + "\n")
        print(f"rendered {len(names)} sounds in {time.perf_counter() - t0:.1f}s")
    if not args.no_verify:
        import verify_audio
        verify_audio.run(ROOT)


if __name__ == "__main__":
    main()
