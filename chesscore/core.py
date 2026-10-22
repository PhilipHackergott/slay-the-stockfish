"""Chess core: rules through pyffish, the engine through UCI. One variant per fight.

The player is always white and the engine black. Results are reported from the player's side.
"""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
import threading
import time
from contextlib import contextmanager
from pathlib import Path

import pyffish as sf

HERE = Path(__file__).resolve().parent
ENGINE_PATH = Path(os.environ.get("STS_ENGINE", HERE / "bin" / "fairy-stockfish"))
PLAYER_KING = "W"


class CoreError(Exception):
    pass


@contextmanager
def captured_c_output():
    """Captures text that the C++ library writes to fd 1 (pyffish reports loader errors there)."""
    buf = tempfile.TemporaryFile(mode="w+b")
    saved = os.dup(1)
    os.dup2(buf.fileno(), 1)
    out: list[str] = []
    try:
        yield out
    finally:
        os.dup2(saved, 1)
        os.close(saved)
        buf.seek(0)
        out.append(buf.read().decode("utf-8", "replace").strip())
        buf.close()


def side_to_move(fen: str) -> str:
    parts = fen.split(" ")
    return parts[1] if len(parts) > 1 else "w"


def board_part(fen: str) -> str:
    return fen.split(" ")[0]


class Engine:
    """A Fairy-Stockfish process over UCI."""

    def __init__(self, path: Path = ENGINE_PATH):
        if not path.exists():
            raise CoreError(f"engine binary missing: {path} (run chesscore/build_engine.sh)")
        self.proc = subprocess.Popen(
            [str(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1,
        )
        self.lock = threading.Lock()
        self._send("uci")
        self._wait_for("uciok", 10.0)
        self.skill: int | None = None

    def _send(self, line: str) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def _wait_for(self, token: str, timeout: float) -> list[str]:
        assert self.proc.stdout is not None
        lines: list[str] = []
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = self.proc.stdout.readline()
            if line == "":
                raise CoreError("engine exited")
            line = line.strip()
            lines.append(line)
            if line.startswith(token):
                return lines
        raise CoreError(f"engine timeout waiting for {token}")

    def load_variant(self, path: str, name: str) -> None:
        self._send(f"setoption name VariantPath value {path}")
        self._send(f"setoption name UCI_Variant value {name}")
        self._send("ucinewgame")
        self._send("isready")
        self._wait_for("readyok", 10.0)

    def set_skill(self, skill: int) -> None:
        if skill != self.skill:
            self._send(f"setoption name Skill Level value {skill}")
            self.skill = skill

    def best_move(self, fen: str, moves: list[str], movetime_ms: int, skill: int, depth: int = 0) -> dict:
        self.set_skill(skill)
        pos = f"position fen {fen}" + (" moves " + " ".join(moves) if moves else "")
        self._send(pos)
        go = f"go depth {depth}" if depth > 0 else f"go movetime {max(1, movetime_ms)}"
        self._send(go)
        lines = self._wait_for("bestmove", movetime_ms / 1000.0 + 30.0)
        score_cp, mate = None, None
        for line in lines:
            m = re.search(r" score (cp|mate) (-?\d+)", line)
            if m:
                if m.group(1) == "cp":
                    score_cp, mate = int(m.group(2)), None
                else:
                    mate, score_cp = int(m.group(2)), None
        best = lines[-1].split()[1]
        return {"move": best, "score_cp": score_cp, "mate": mate}

    def close(self) -> None:
        try:
            self._send("quit")
            self.proc.wait(timeout=2)
        except Exception:
            self.proc.kill()


class ChessCore:
    def __init__(self):
        self.variant = "chess"
        self.variant_path: str | None = None
        self.engine: Engine | None = None
        self._tmpdir = tempfile.mkdtemp(prefix="sts_variants_")

    # --- variants -----------------------------------------------------------------------------
    def load_variant(self, name: str, ini: str) -> dict:
        if not re.fullmatch(r"[a-z0-9_]+", name):
            raise CoreError(f"bad variant name: {name}")
        with captured_c_output() as out:
            sf.load_variant_config(ini)
        if name not in sf.variants():
            raise CoreError(f"variant {name} did not load: {out[0] if out else ''}")
        path = os.path.join(self._tmpdir, f"{name}.ini")
        with open(path, "w") as f:
            f.write(ini)
        self.variant, self.variant_path = name, path
        if self.engine is not None:
            self.engine.load_variant(path, name)
        return {"warnings": out[0] if out and out[0] else ""}

    def _ensure_engine(self) -> Engine:
        if self.engine is None:
            self.engine = Engine()
            if self.variant_path:
                self.engine.load_variant(self.variant_path, self.variant)
        return self.engine

    # --- rules --------------------------------------------------------------------------------
    def validate(self, fen: str) -> dict:
        # pyffish counts only the variant's king letter; the player's pseudo-royal king is
        # checked as a K (see the handover, Engine integration).
        board, _, rest = fen.partition(" ")
        probe = board.replace(PLAYER_KING, "K") + " " + rest
        with captured_c_output() as out:
            code = sf.validate_fen(probe, self.variant)
        if code != sf.FEN_OK:
            return {"valid": False, "reason": out[0] or f"fen error {code}"}
        if self.in_check(fen, "b" if side_to_move(fen) == "w" else "w"):
            return {"valid": False, "reason": "side not to move is in check"}
        return {"valid": True, "reason": ""}

    def in_check(self, fen: str, side: str) -> bool:
        parts = fen.split(" ")
        parts[1] = side
        if len(parts) > 3:
            parts[3] = "-"
        probe = " ".join(parts)
        try:
            return bool(sf.gives_check(self.variant, probe, []))
        except Exception:
            return False

    def legal(self, fen: str, moves: list[str]) -> list[str]:
        return list(sf.legal_moves(self.variant, fen, moves))

    def apply(self, fen: str, moves: list[str], move: str) -> dict:
        if move not in self.legal(fen, moves):
            raise CoreError(f"illegal move {move}")
        capture = bool(sf.is_capture(self.variant, fen, moves, move))
        after = moves + [move]
        return {
            "fen": sf.get_fen(self.variant, fen, after),
            "capture": capture,
            "check": bool(sf.gives_check(self.variant, fen, after)),
        }

    def result(self, fen: str, moves: list[str]) -> dict:
        cur = sf.get_fen(self.variant, fen, moves) if moves else fen
        stm = side_to_move(cur)

        def from_player(value: int) -> str:
            if value == 0:
                return "draw"
            stm_wins = value > 0
            return "win" if stm_wins == (stm == "w") else "loss"

        legal = sf.legal_moves(self.variant, fen, moves)
        if not legal:
            value = sf.game_result(self.variant, fen, moves)
            in_check = bool(sf.gives_check(self.variant, fen, moves))
            reason = "checkmate" if in_check and value != 0 else ("stalemate" if value == 0 else "no moves")
            return {"state": from_player(value), "reason": reason}
        ended, value = sf.is_immediate_game_end(self.variant, fen, moves)
        if ended:
            return {"state": from_player(value), "reason": "rule"}
        ended, value = sf.is_optional_game_end(self.variant, fen, moves)
        if ended:
            return {"state": "draw" if value == 0 else from_player(value), "reason": "repetition or 50 moves"}
        white_insufficient, black_insufficient = sf.has_insufficient_material(self.variant, fen, moves)
        if white_insufficient and black_insufficient:
            return {"state": "draw", "reason": "insufficient material"}
        return {"state": "ongoing", "reason": ""}

    # --- engine -------------------------------------------------------------------------------
    def engine_move(self, fen: str, moves: list[str], movetime_ms: int, skill: int, depth: int = 0) -> dict:
        engine = self._ensure_engine()
        res = engine.best_move(fen, moves, movetime_ms, skill, depth)
        if res["move"] in ("(none)", "0000"):
            raise CoreError("engine has no move")
        return res

    def close(self) -> None:
        if self.engine is not None:
            self.engine.close()
            self.engine = None
