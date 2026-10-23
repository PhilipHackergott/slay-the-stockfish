"""Repeats every check from the handover's Engine integration section, plus the API seam."""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

from core import ChessCore, ENGINE_PATH  # noqa: E402

BASE = """[{name}:chess]
king = k
customPiece1 = w:{king}
extinctionPieceTypes = w
extinctionPseudoRoyal = true
extinctionValue = loss
castling = false
"""


@pytest.fixture()
def core():
    c = ChessCore()
    yield c
    c.close()


def load(core, name, king="K", extra=""):
    core.load_variant(name, BASE.format(name=name, king=king) + extra)


def test_custom_king_cannot_step_into_check(core):
    load(core, "t_king_kn", king="KN")
    fen = "4k3/8/8/8/8/8/3r4/4W3 w - - 0 1"
    legal = core.legal(fen, [])
    assert "e1d2" in legal  # capture is fine
    assert "e1e2" not in legal and "e1d1" not in legal  # both on the rook's lines
    assert "e1f3" in legal  # the N part of w:KN


def test_mate_of_custom_king_is_detected(core):
    load(core, "t_mate")
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR w - - 0 1"
    moves = ["f2f3", "e7e5", "g2g4", "d8h4"]
    assert core.legal(fen, moves) == []
    assert core.result(fen, moves) == {"state": "loss", "reason": "checkmate"}


def test_engine_side_not_extinct_and_mated_normally(core):
    load(core, "t_black_mate")
    fen = "6k1/5ppp/8/8/8/8/8/R3W3 w - - 0 1"
    assert core.result(fen, [])["state"] == "ongoing"  # black has no w pieces and is not extinct
    assert core.result(fen, ["a1a8"]) == {"state": "win", "reason": "checkmate"}
    assert core.mates_in_one(fen) == ["a1a8"]
    assert core.mates_in_one("6k1/6pp/8/8/8/8/8/R3W3 w - - 0 1") == []  # f7 is free


def test_validate_with_custom_king(core):
    load(core, "t_validate")
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR w - - 0 1"
    assert core.validate(fen)["valid"]
    assert not core.validate("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQ1BNR w - - 0 1")["valid"]


def test_side_not_to_move_in_check_is_invalid(core):
    load(core, "t_check_invalid")
    # black to move but white's king is attacked by the rook: invalid
    assert not core.validate("4k3/8/8/8/8/8/8/r3W3 b - - 0 1")["valid"]
    assert core.validate("4k3/8/8/8/8/8/8/r3W3 w - - 0 1")["valid"]


def test_one_sided_pocket_drops(core):
    load(core, "t_pocket", extra="pieceDrops = true\ncapturesToHand = false\ndropRegionWhite = *1 *2 *3 *4\n")
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR[B] w - - 0 1"
    drops = [m for m in core.legal(fen, []) if "@" in m]
    assert drops and all(m[3] in "34" for m in drops)  # ranks 1 and 2 are full
    # captures do not fill pockets
    after = core.apply(fen, ["e2e4", "d7d5"], "e4d5")["fen"]
    assert "[B]" in after
    black_drops = [m for m in core.legal(after, []) if "@" in m]
    assert black_drops == []


def test_custom_pawn_sideways_double_step_and_promotion(core):
    extra = "customPiece2 = a:fsmWfceFifmnD\npromotionPawnTypesWhite = a\npromotionPieceTypesWhite = q\n"
    load(core, "t_pawn", extra=extra)
    fen = "4k3/8/8/8/8/8/3A4/4W3 w - - 0 1"
    legal = core.legal(fen, [])
    assert {"d2d3", "d2d4", "d2c2"} <= set(legal)
    promo = core.legal("4k3/A7/8/8/8/8/8/4W3 w - - 0 1", [])
    assert "a7a8q" in promo


def test_piece_type_budget_twenty_custom_letters(core):
    letters = "abcdfghijlmostuvxyz"  # 19 letters plus w (the king) = 20 custom pieces
    extra = "".join(f"customPiece{i + 2} = {ch}:W\n" for i, ch in enumerate(letters))
    load(core, "t_budget", extra=extra)
    row = "".join(ch.upper() for ch in letters[:8])
    fen = f"4k3/8/8/8/8/8/{row}/4W3 w - - 0 1"
    legal = core.legal(fen, [])
    assert any(m.startswith("a2") for m in legal) and any(m.startswith("h2") for m in legal)


def test_rule_relic_promotion_on_seventh(core):
    load(core, "t_promo7", extra="promotionRegionWhite = *7 *8\n")
    legal = core.legal("4k3/8/P7/8/8/8/8/4W3 w - - 0 1", [])
    assert "a6a7q" in legal and "a6a7" not in legal


@pytest.mark.skipif(not ENGINE_PATH.exists(), reason="engine not built")
def test_engine_moves_in_generated_custom_variant(core):
    extra = "customPiece2 = a:fsmWfceFifmnD\npromotionPawnTypesWhite = a\npieceDrops = true\ncapturesToHand = false\n"
    load(core, "t_engine", king="KN", extra=extra)
    fen = "rnbqkbnr/pppppppp/8/8/8/8/AAAAAAAA/RNBQWBNR[B] b - - 0 1"
    t0 = time.monotonic()
    res = core.engine_move(fen, [], movetime_ms=200, skill=20)
    assert time.monotonic() - t0 < 2.0
    assert res["move"] in core.legal(fen, [])
    assert res["score_cp"] is not None or res["mate"] is not None


@pytest.mark.skipif(not ENGINE_PATH.exists(), reason="engine not built")
def test_server_json_lines_roundtrip():
    proc = subprocess.Popen([sys.executable, str(HERE / "server.py")], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True, cwd=HERE)

    def call(req):
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    assert call({"id": 1, "op": "ping"})["api"] == 1
    ini = BASE.format(name="t_server", king="K")
    assert call({"id": 2, "op": "load_variant", "name": "t_server", "ini": ini})["ok"]
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQWBNR w - - 0 1"
    bad = call({"id": 3, "op": "validate", "fen": fen.replace("W", "")})  # prints to C stdout
    assert bad["ok"] and not bad["valid"]
    assert len(call({"id": 4, "op": "legal", "fen": fen, "moves": []})["moves"]) == 20
    mv = call({"id": 5, "op": "engine_move", "fen": fen, "moves": ["e2e4"], "movetime_ms": 50, "skill": 0})
    assert mv["ok"] and len(mv["move"]) >= 4
    err = call({"id": 6, "op": "apply", "fen": fen, "moves": [], "move": "e2e5"})
    assert not err["ok"] and "illegal" in err["error"]
    call({"id": 7, "op": "quit"})
    proc.wait(timeout=5)
