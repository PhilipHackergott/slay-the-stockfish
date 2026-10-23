"""Generates the mate-in-two problems of the puzzle events (data/encounters/puzzle_*.tres).

Random but shaped positions (the black king near its back rank, a small white force), checked with
the game's own rules (chess with the pseudo-royal W king): nothing wins at once, exactly one key
move, at least three black replies to it. Tier 1 allows a checking key; tiers 2 and 3 want a quiet
key (no check, no capture), tier 3 more black pieces.

Usage: chesscore/.venv/bin/python tools/gen_puzzles.py [--per-tier 3] [--seed 1] [--write]
"""
from __future__ import annotations

import argparse
import multiprocessing as mp
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "chesscore"))

from core import ChessCore  # noqa: E402

INI = """[sts_puzzle:chess]
king = k
customPiece1 = w:K
extinctionPieceTypes = w
extinctionPseudoRoyal = true
extinctionValue = loss
castling = false
pieceValueMg = w:1
pieceValueEg = w:1
"""
NAMES = {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king", "w": "king"}
FILES = "abcdefgh"
WHITE_FORCES = [["Q"], ["R", "R"], ["Q", "N"], ["R", "B"], ["Q", "B"], ["R", "N"], ["R", "N", "B"], ["Q", "R"],
                ["B", "B", "N"], ["Q", "P"]]
BLACK_COUNT = {1: (0, 2), 2: (1, 3), 3: (2, 5)}
TITLES = {1: "The Hanged Problem", 2: "The Drowned Problem", 3: "The Engine's Riddle"}
ROMAN = ["I", "II", "III", "IV", "V", "VI"]

_core: ChessCore | None = None


def _init() -> None:
    global _core
    _core = ChessCore()
    _core.load_variant("sts_puzzle", INI)


def fen_of(board: dict) -> str:
    rows = []
    for r in range(7, -1, -1):
        row, empty = "", 0
        for f in range(8):
            c = board.get((f, r))
            if c is None:
                empty += 1
                continue
            if empty:
                row += str(empty)
                empty = 0
            row += c
        rows.append(row + (str(empty) if empty else ""))
    return "/".join(rows) + " w - - 0 1"


def random_board(rng: random.Random, tier: int) -> dict:
    board: dict = {}

    def free(lo: int, hi: int, pawn: bool = False) -> tuple:
        while True:
            p = (rng.randrange(8), rng.randint(lo, hi))
            if p not in board and not (pawn and p[1] in (0, 7)):
                return p

    bk = (rng.randrange(8), rng.choice([7, 7, 7, 6]))
    board[bk] = "k"
    while True:
        wk = free(0, 6)
        if max(abs(wk[0] - bk[0]), abs(wk[1] - bk[1])) > 1:
            break
    board[wk] = "W"
    for letter in rng.choice(WHITE_FORCES):
        board[free(1, 6, True) if letter == "P" else free(1, 7)] = letter
    lo, hi = BLACK_COUNT[tier]
    for _ in range(rng.randint(lo, hi)):
        letter = rng.choice("ppppnbr")
        board[free(1, 6, True) if letter == "p" else free(2, 7)] = letter
    return board


def judge(fen: str, tier: int) -> str | None:
    """The key move if this is a clean problem of the tier, else None."""
    core = _core
    if not core.validate(fen)["valid"] or core.in_check(fen, "b") or core.in_check(fen, "w"):
        return None
    # The engine screens (fast); the exact search below only runs on its mates in two.
    if core.engine_move(fen, [], 0, 20, 4).get("mate") != 2:
        return None
    if core.mates_in_one(fen):
        return None
    keys = core.mate_in_two(fen)
    if len(keys) != 1:
        return None
    key = keys[0]
    if len(core.legal(fen, [key])) < 3:
        return None
    after = core.apply(fen, [], key)
    if after["capture"] or (tier >= 2 and after["check"]):
        return None
    return key


def search(args: tuple) -> tuple | None:
    seed, tier = args
    rng = random.Random(seed)
    board = random_board(rng, tier)
    fen = fen_of(board)
    key = judge(fen, tier)
    return (tier, fen, key, board) if key else None


def tres(pid: str, title: str, tier: int, board: dict, key: str) -> str:
    def sq(p: tuple) -> str:
        return f"{FILES[p[0]]}{p[1] + 1}"

    black = {sq(p): NAMES[c] for p, c in sorted(board.items()) if c.islower()}
    white = {sq(p): NAMES[c.lower()] for p, c in sorted(board.items()) if c.isupper()}

    def gd(d: dict) -> str:
        return "{" + ", ".join(f'"{k}": &"{v}"' for k, v in d.items()) + "}"

    return "\n".join([
        '[gd_resource type="Resource" script_class="EncounterDef" format=3]', "",
        '[ext_resource type="Script" path="res://src/data/encounter_def.gd" id="1"]', "",
        "[resource]", 'script = ExtResource("1")', f'id = &"{pid}"', f'display_name = "{title}"',
        'kind = &"puzzle"', f"tier = {tier}", f"layout = {gd(black)}", f"player_layout = {gd(white)}",
        "move_limit = 2", f'solution = "{key}"', "movetime_ms = 400", "skill = 20",
        'flavor = "White to move. Mate in two, whatever the engine answers."', "",
    ])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-tier", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    found: dict = {1: [], 2: [], 3: []}
    seen: set = set()
    with mp.Pool(max(1, mp.cpu_count() - 2), initializer=_init) as pool:
        batch = 0
        while any(len(v) < a.per_tier for v in found.values()):
            jobs = [(a.seed * 10_000_000 + batch * 4000 + i, t) for t in (1, 2, 3) if len(found[t]) < a.per_tier
                    for i in range(4000)]
            batch += 1
            for hit in pool.imap_unordered(search, jobs, chunksize=50):
                if hit is None:
                    continue
                tier, fen, key, board = hit
                if len(found[tier]) < a.per_tier and fen not in seen:
                    seen.add(fen)
                    found[tier].append((fen, key, board))
                    print(f"tier {tier}: {fen}  key {key}", flush=True)
    for tier, hits in found.items():
        for i, (fen, key, board) in enumerate(hits):
            pid = f"puzzle_{tier}_{i + 1}"
            text = tres(pid, f"{TITLES[tier]} {ROMAN[i]}", tier, board, key)
            if a.write:
                (ROOT / "data" / "encounters" / f"{pid}.tres").write_text(text)
    if a.write:
        print("written to data/encounters/puzzle_*.tres")


if __name__ == "__main__":
    main()
