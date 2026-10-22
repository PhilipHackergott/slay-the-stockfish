"""Smoke test for a bundled chess core, started the way the game starts it (python -E -s -B server.py).

usage: <any python 3> tools/package/smoke_core.py <chesscore dir>
Checks ping, a broken variant (pyffish's C++ output must not reach the protocol pipe), a real variant, legal moves,
an engine move (engine binary + VariantPath round trip), quit, and that every reply ends in a bare '\n'.
On Windows it also checks that pyffish loads the bundled msvcp140.dll. Prints SMOKE CORE OK or exits 1.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"
VARIANT = """[smoke:chess]
king = k
customPiece1 = w:K
extinctionPieceTypes = w
extinctionPseudoRoyal = true
extinctionValue = loss
castling = false
"""


def python_of(core: Path) -> Path:
    for rel in ("python/python.exe", "python/bin/python3.12", "python/bin/python3"):
        if (core / rel).exists():
            return core / rel
    raise SystemExit(f"SMOKE CORE FAIL: no python under {core}")


def fail(msg: str) -> None:
    print(f"SMOKE CORE FAIL: {msg}")
    sys.exit(1)


def main() -> None:
    core = Path(sys.argv[1]).resolve()
    py = python_of(core)
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}
    t0 = time.monotonic()
    proc = subprocess.Popen([str(py), "-E", "-s", "-B", str(core / "server.py")], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, cwd=str(Path.home()), **flags)
    assert proc.stdin and proc.stdout

    def ask(req: dict) -> dict:
        proc.stdin.write((json.dumps(req) + "\n").encode())
        proc.stdin.flush()
        raw = proc.stdout.readline()
        if not raw.endswith(b"\n") or raw.endswith(b"\r\n"):
            fail(f"bad line ending for {req['op']}: {raw!r}")
        try:
            return json.loads(raw)
        except ValueError:
            fail(f"non-JSON reply to {req['op']}: {raw!r}")
        return {}

    ping = ask({"id": 1, "op": "ping"})
    boot_ms = (time.monotonic() - t0) * 1000
    if not ping.get("ok") or ping.get("api") != 1:
        fail(f"ping {ping}")
    bad = ask({"id": 2, "op": "load_variant", "name": "smoke_bad", "ini": "[smoke_bad:notavariant]\n"})
    if bad.get("ok") or ask({"id": 3, "op": "ping"}).get("id") != 3:
        fail(f"broken variant: {bad}")
    loaded = ask({"id": 4, "op": "load_variant", "name": "smoke", "ini": VARIANT})
    if not loaded.get("ok"):
        fail(f"load_variant {loaded}")
    fen = START.replace("K", "W")
    legal = ask({"id": 5, "op": "legal", "fen": fen, "moves": []}).get("moves", [])
    if len(legal) != 20:
        fail(f"legal moves {legal}")
    t1 = time.monotonic()
    best = ask({"id": 6, "op": "engine_move", "fen": fen, "moves": ["e2e4"], "movetime_ms": 300, "skill": 20})
    engine_ms = (time.monotonic() - t1) * 1000
    after = ask({"id": 7, "op": "legal", "fen": fen, "moves": ["e2e4"]}).get("moves", [])
    if not best.get("ok") or best.get("move") not in after:
        fail(f"engine_move {best}")
    if not ask({"id": 8, "op": "quit"}).get("bye"):
        fail("quit")
    proc.wait(timeout=10)

    dll = ""
    if sys.platform == "win32":
        probe = ("import ctypes, pyffish; k = ctypes.WinDLL('kernel32');"
                 "k.GetModuleHandleW.restype = ctypes.c_void_p;"
                 "k.GetModuleFileNameW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32];"
                 "b = ctypes.create_unicode_buffer(1024); k.GetModuleFileNameW(k.GetModuleHandleW('msvcp140.dll'), b, 1024);"
                 "print(b.value)")
        dll = subprocess.run([str(py), "-E", "-s", "-B", "-c", probe], capture_output=True, text=True,
                             **flags).stdout.strip()
        if not Path(dll).resolve().is_relative_to(core):
            fail(f"msvcp140.dll loaded from outside the bundle: {dll!r}")
        dll = f" msvcp140={dll}"
    print(f"SMOKE CORE OK python={py} boot={boot_ms:.0f}ms engine_move={best['move']} "
          f"({engine_ms:.0f}ms){dll}")


if __name__ == "__main__":
    main()
