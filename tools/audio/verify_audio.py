"""Checks the rendered files as the game will see them (OGGs decoded with ffmpeg).

Per file: duration, sample peak, DC offset, clipped samples, integrated loudness.
Per loop: seam metrics comparing the wrap point (end -> start) with the rest of the file:
  jump   = |x[0] - x[-1]| / 99.9th percentile of |x[n+1] - x[n]|   (< ~1 means no step)
  rms_db = RMS of the last 50 ms vs the first 50 ms
  hf     = energy above 6 kHz in a 6 ms window centred on the seam, as a percentile
           of the same measure at 400 positions inside the file, as RMS dBFS, and relative
           to the windows 12 ms either side; a click is a local spike (> +6 dB) above -60 dBFS
           (musical onsets or risers at the seam rank high but are not local spikes)
Writes build/audio/report.txt and build/audio/spectrograms.png.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100


def load(path: Path) -> np.ndarray:
    if path.suffix == ".wav":
        sr, d = wavfile.read(path)
        assert sr == SR, (path, sr)
        x = d.astype(np.float64) / 32768.0
        return x.T if x.ndim == 2 else x[None]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "2",
                          "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).T.astype(np.float64)


def seam_metrics(x: np.ndarray) -> dict:
    w = int(0.05 * SR)
    d = np.abs(np.diff(x, axis=1))
    ref = np.percentile(d, 99.9) + 1e-12
    jump = float(np.max(np.abs(x[:, 0] - x[:, -1])) / ref)
    rms = lambda v: np.sqrt(np.mean(v ** 2) + 1e-20)
    rms_db = float(20 * np.log10(rms(x[:, -w:]) / rms(x[:, :w])))
    sos = signal.butter(4, 6000, "high", fs=SR, output="sos")
    N = x.shape[1]
    h = signal.sosfilt(sos, np.concatenate([x, x], axis=1), axis=1)
    hw = int(0.003 * SR)
    e_seam = np.sum(h[:, N - hw:N + hw] ** 2)
    rng = np.random.default_rng(1)
    pos = rng.integers(N // 2 + hw, N + N // 2 - hw, 400)
    es = np.array([np.sum(h[:, p - hw:p + hw] ** 2) for p in pos])
    hf_pct = float(np.mean(es < e_seam) * 100.0)
    hf_dbfs = float(10 * np.log10(e_seam / (2 * hw * x.shape[0]) + 1e-20))
    off = int(0.012 * SR)
    around = 0.5 * (np.sum(h[:, N - off - hw:N - off + hw] ** 2) + np.sum(h[:, N + off - hw:N + off + hw] ** 2))
    hf_local = float(10 * np.log10((e_seam + 1e-20) / (around + 1e-20)))
    quiet = 20 * np.log10(max(rms(x[:, -w:]), rms(x[:, :w])) + 1e-12) < -45
    return {"jump": round(jump, 3), "rms_db": round(rms_db, 2), "quiet": bool(quiet), "hf_pct": round(hf_pct, 1),
            "hf_dbfs": round(hf_dbfs, 1), "hf_local_db": round(hf_local, 1)}


def lufs(x: np.ndarray) -> float:
    import make_audio
    return make_audio.lufs(x)


def run(root: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    meta = json.loads((root / "assets/audio/audio.json").read_text())["files"]
    out_dir = root / "build/audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    lines = [f"{'name':16s} {'cat':8s} {'dur s':>7s} {'peak':>7s} {'LUFS':>6s} {'Mmax':>6s} {'>5k%':>5s} "
             f"{'DC':>8s} {'clip':>4s}  seam"]
    problems = []
    items = sorted(meta.items(), key=lambda kv: (kv[1]["category"] != "sfx", kv[0]))
    specs = []
    total = 0
    for name, m in items:
        path = root / m["path"].replace("res://", "")
        total += path.stat().st_size
        x = load(path)
        dur = x.shape[1] / SR
        pk = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        dc = float(np.max(np.abs(x.mean(axis=1))))
        clip = int(np.sum(np.abs(x) >= 0.999))
        lu = lufs(x)
        seam = ""
        if m.get("loop"):
            s = seam_metrics(x)
            seam = (f"jump {s['jump']:.2f}  rms {s['rms_db']:+.2f} dB{' (quiet)' if s['quiet'] else ''}  "
                    f"hf {s['hf_pct']:.0f}% {s['hf_dbfs']:.0f} dBFS, {s['hf_local_db']:+.1f} dB vs +-12 ms")
            if (s["jump"] > 1.5 or (abs(s["rms_db"]) > 3.0 and not s["quiet"])
                    or (s["hf_local_db"] > 6.0 and s["hf_dbfs"] > -60)):
                problems.append(f"{name}: seam {s}")
            if "loop_samples" in m and x.shape[1] != m["loop_samples"]:
                problems.append(f"{name}: decoded {x.shape[1]} samples, rendered {m['loop_samples']}")
        if abs(dur - m["duration"]) > 0.01:
            problems.append(f"{name}: duration {dur:.3f} != audio.json {m['duration']}")
        if clip or pk > -0.5:
            problems.append(f"{name}: peak {pk:.2f} dBFS, {clip} clipped samples")
        if dc > 1e-3:
            problems.append(f"{name}: DC {dc:.5f}")
        import make_audio
        mm = make_audio.momentary_max(x)
        X = np.abs(np.fft.rfft(x.mean(axis=0))) ** 2
        fr = np.fft.rfftfreq(x.shape[1], 1.0 / SR)
        hf = 100.0 * X[fr > 5000].sum() / (X.sum() + 1e-20)
        lines.append(f"{name:16s} {m['category']:8s} {dur:7.2f} {pk:7.2f} {lu:6.1f} {mm:6.1f} {hf:5.1f} "
                     f"{dc:8.5f} {clip:4d}  {seam}")
        specs.append((name, m["category"], dur, x.mean(axis=0)))
    lines.append(f"total size {total / 1e6:.2f} MB")
    lines += ["", "problems:"] + (problems or ["none"])
    report = "\n".join(lines)
    (out_dir / "report.txt").write_text(report + "\n")
    print(report)

    cols = 5
    rows = int(np.ceil(len(specs) / cols))
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 5.2, rows * 3.0), squeeze=False)
    for ax, (name, cat, dur, mono) in zip(axes.flat, specs):
        nper = 1024 if dur < 10 else 4096
        f, t, S = signal.spectrogram(mono, fs=SR, nperseg=nper, noverlap=nper * 3 // 4, scaling="spectrum")
        S = 10 * np.log10(S + 1e-14)
        ax.pcolormesh(t, f, S, vmin=S.max() - 75, vmax=S.max(), shading="auto", cmap="magma", rasterized=True)
        ax.set_yscale("symlog", linthresh=500)
        ax.set_ylim(30, 16000)
        ax.set_yticks([100, 500, 1000, 2000, 5000, 10000])
        ax.set_yticklabels(["100", "500", "1k", "2k", "5k", "10k"], fontsize=7)
        ax.tick_params(axis="x", labelsize=7)
        ax.set_title(f"{name} [{cat}] {dur:.2f}s", fontsize=9)
    for ax in list(axes.flat)[len(specs):]:
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(out_dir / "spectrograms.png", dpi=55)
    plt.close(fig)
    print(f"wrote {out_dir / 'spectrograms.png'}")
