"""JSON-lines server over stdin/stdout for Godot (OS.execute_with_pipe).

Request:  {"id": 1, "op": "legal", "fen": "...", "moves": []}
Response: {"id": 1, "ok": true, ...} or {"id": 1, "ok": false, "error": "..."}

The C++ library prints to stdout, so the protocol writes to a private copy of fd 1 and fd 1
itself is pointed at stderr.
"""
from __future__ import annotations

import json
import os
import sys
import traceback

PROTO = os.fdopen(os.dup(1), "w", buffering=1)
os.dup2(2, 1)
sys.stdout = sys.stderr

from core import ChessCore, CoreError  # noqa: E402

API_VERSION = 1


def handle(core: ChessCore, req: dict) -> dict:
    op = req.get("op")
    fen = req.get("fen", "")
    moves = list(req.get("moves", []))
    if op == "ping":
        return {"api": API_VERSION}
    if op == "load_variant":
        return core.load_variant(req["name"], req["ini"])
    if op == "validate":
        return core.validate(fen)
    if op == "legal":
        return {"moves": core.legal(fen, moves)}
    if op == "apply":
        return core.apply(fen, moves, req["move"])
    if op == "result":
        return core.result(fen, moves)
    if op == "in_check":
        return {"check": core.in_check(fen, req.get("side", "w"))}
    if op == "engine_move":
        return core.engine_move(fen, moves, int(req.get("movetime_ms", 100)), int(req.get("skill", 20)),
                                int(req.get("depth", 0)))
    if op == "quit":
        return {"bye": True}
    raise CoreError(f"unknown op {op}")


def main() -> None:
    core = ChessCore()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        rid = None
        req: dict = {}
        try:
            req = json.loads(line)
            rid = req.get("id")
            res = handle(core, req)
            res.update({"id": rid, "ok": True})
        except CoreError as e:
            res = {"id": rid, "ok": False, "error": str(e)}
        except Exception as e:  # keep serving; report the bug
            traceback.print_exc(file=sys.stderr)
            res = {"id": rid, "ok": False, "error": f"{type(e).__name__}: {e}"}
        PROTO.write(json.dumps(res) + "\n")
        PROTO.flush()
        if req.get("op") == "quit":
            break
    core.close()


if __name__ == "__main__":
    main()
