"""Which Fairy-Stockfish rule options work with our pseudo-royal player king (Design lab: arenas).

Run: chesscore/.venv/bin/python tools/probe_variants.py
"""
import pyffish as sf

BASE = """[{n}:chess]
king = k
customPiece1 = w:K
extinctionPieceTypes = w
extinctionPseudoRoyal = true
extinctionValue = loss
castling = false
pieceValueMg = w:1
pieceValueEg = w:1
"""


def variant(name: str, extra: str) -> str:
    sf.load_variant_config(BASE.format(n=name) + extra + "\n")
    return name


def legal(v: str, fen: str) -> list:
    return sorted(sf.legal_moves(v, fen, []))


def ends(v: str, fen: str, moves: list) -> bool:
    return sf.is_immediate_game_end(v, fen, moves)[0]


def check(name: str, ok: bool, note: str) -> None:
    print(f"{'works ' if ok else 'BROKEN'}  {name:16} {note}")


v = variant("p_hill", "flagPieceWhite = w\nflagPieceBlack = k\nflagRegionWhite = d4 e4 d5 e5\nflagRegionBlack = d4 e4 d5 e5")
check("Summit Altar", ends(v, "4k3/8/8/8/8/4W3/8/8 w - - 0 1", ["e3e4"]), "king on e4 ends the game")

v = variant("p_walls", "")
check("Collapsed Nave", len(legal(v, "4k3/8/8/3**3/8/8/8/3RW3 w - - 0 1")) < len(legal(v, "4k3/8/8/8/8/8/8/3RW3 w - - 0 1")),
      "* squares in the FEN block moves")

v = variant("p_check", "checkCounting = true")
check("Tolling Bells", ends(v, "4k3/8/8/8/8/8/8/R3W3 w - - 1+3 0 1", ["a1a8"]), "third check ends the game")

v = variant("p_hunger", "mustCapture = true")
check("The Hunger", legal(v, "4k3/8/8/3p4/4P3/8/8/4W3 w - - 0 1") == ["e4d5"], "only the capture is legal")

v = variant("p_crow", "wallingRule = duck")
check("The Crow", "," in legal(v, "4k3/8/8/8/8/8/4P3/4W3 w - - 0 1")[0], "moves are two-part (move,crow)")

v = variant("p_past", "wallingRule = past")
check("Burning Stakes", "," in legal(v, "4k3/8/8/8/8/8/4P3/4W3 w - - 0 1")[0], "the left square becomes a wall")

v = variant("p_gorgon", "petrifyOnCaptureTypes = r")
check("Gorgon Cloister", "3*4" in sf.get_fen(v, "4k3/8/8/3p4/8/8/8/3RW3 w - - 0 1", ["d1d5"]),
      "a capturing rook turns to stone (petrifyOnCapture = true does nothing)")

v = variant("p_zh", "pieceDrops = true\ncapturesToHand = true")
check("Ossuary", "[P]" in sf.get_fen(v, "4k3/8/8/3p4/4P3/8/8/4W3[] w - - 0 1", ["e4d5"]), "captures go to the pocket")

v = variant("p_gate", "gating = true\nseirawanGating = true")
check("Reliquary Gates", "a1b1n" in legal(v, "r3k3/8/8/8/8/8/8/R3W3[N] w A - 0 1"), "a pocket knight gates in")

v = variant("p_crown", "promotedPieceType = n:q\npromotionRegionWhite = *6 *7 *8\nmandatoryPiecePromotion = false")
check("Coronation Rows", "e5c6+" in legal(v, "4k3/8/8/4N3/8/8/8/4W3 w - - 0 1"), "a knight may crown on rank 6")

v = variant("p_twin", "extinctionPieceTypes = wk\nking = -")
check("Twin-souled", not ends(v, "3k4/8/8/8/8/8/8/R3W3 b - - 0 1", []), "one of two kings left is not a loss")

v = variant("p_ascent", "flagPieceWhite = w\nflagPieceBlack = k\nflagRegionWhite = *8\nflagRegionBlack = *1")
check("The Ascent", ends(v, "k7/4W3/8/8/8/8/8/8 w - - 0 1", ["e7e8"]), "a king on the far rank ends the game")

v = variant("p_mercy", "stalemateValue = loss")
r = sf.game_result(v, "k7/2W5/1Q6/8/8/8/8/8 b - - 0 1", [])
check("Mercy's End", r < 0, f"stalemated side scores {r}")

v = variant("p_shallow", "promotionRegionWhite = *6 *7 *8\npromotionRegionBlack = *3 *2 *1")
check("Shallow Crypt", "e5e6q" in legal(v, "4k3/8/8/4P3/8/8/8/4W3 w - - 0 1"), "pawns promote on rank 6")

v = variant("p_atomic", "blastOnCapture = true")
check("Powder Crypt", len(legal(v, "4k3/8/8/3pn3/4P3/8/8/4W3 w - - 0 1")) > 0, "atomic captures with the pseudo-royal king")
