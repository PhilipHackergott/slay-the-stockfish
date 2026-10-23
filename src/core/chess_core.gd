extends Node
## Client for the chess core sidecar (chesscore/server.py): JSON lines over a pipe.
## Every call is a coroutine: `var res: Dictionary = await ChessCore.call_core({...})`.
## One worker thread writes requests and blocks on replies; a second drains stderr so the
## sidecar never stalls on a full pipe.

class Pending:
	extends RefCounted
	signal done(result: Dictionary)

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _thread: Thread
var _err_thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array = []
var _pending: Dictionary = {}
var _next_id := 0
var _quit := false
var _dead := false
var log_stderr := false


func is_running() -> bool:
	return _pid > 0 and not _dead


func start() -> bool:
	if _pid > 0:
		return not _dead
	var cmd := core_command()
	var info: Dictionary = {} if cmd.is_empty() else OS.execute_with_pipe(cmd[0], cmd.slice(1))
	if info.is_empty():
		push_warning("chess core: could not start %s" % (" ".join(cmd) if not cmd.is_empty()
			else "(no server.py found; set STS_CHESSCORE and/or STS_PYTHON)"))
		_dead = true
		_pid = 0
		return false
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	_pid = int(info["pid"])
	_thread = Thread.new()
	_thread.start(_worker)
	_err_thread = Thread.new()
	_err_thread.start(_drain_stderr)
	return true


## [python, args..., server.py] for the chess core sidecar, or [] if there is no server.py. Lookup order:
## 1. STS_CHESSCORE (folder with server.py) and/or STS_PYTHON (interpreter) from the environment.
## 2. Source tree, editor builds only (`godot --path .`): res://chesscore with its .venv python.
## 3. Runtime bundled by tools/package: <app>/Contents/Resources/chesscore on macOS, <exe dir>/chesscore on
##    Windows. Its python runs with -E -s -B: no PYTHON* env vars, no user site-packages, no .pyc writes
##    into the (signed, possibly read-only) bundle.
## Exported builds never use globalize_path("res://..."): it returns a path relative to the working directory there.
func core_command() -> PackedStringArray:
	var core_dir := OS.get_environment("STS_CHESSCORE")
	var python := OS.get_environment("STS_PYTHON")
	if core_dir == "" and OS.has_feature("editor"):
		var src := ProjectSettings.globalize_path("res://chesscore")
		if FileAccess.file_exists(src.path_join("server.py")):
			core_dir = src
	if core_dir == "":
		var exe_dir := OS.get_executable_path().get_base_dir()
		if OS.has_feature("macos"):
			core_dir = exe_dir.get_base_dir().path_join("Resources/chesscore")
		else:
			core_dir = exe_dir.path_join("chesscore")
	var server := core_dir.path_join("server.py")
	if not FileAccess.file_exists(server):
		return PackedStringArray()
	var cmd := PackedStringArray()
	if python == "":
		for rel: String in ["python/python.exe", "python/bin/python3.12", "python/bin/python3"]:
			if FileAccess.file_exists(core_dir.path_join(rel)):
				cmd = PackedStringArray([core_dir.path_join(rel), "-E", "-s", "-B"])
				break
	if cmd.is_empty():
		for rel: String in [".venv/bin/python", ".venv/Scripts/python.exe"]:
			if python == "" and FileAccess.file_exists(core_dir.path_join(rel)):
				python = core_dir.path_join(rel)
		cmd = PackedStringArray([python if python != "" else "python3"])
	cmd.append(server)
	return cmd


func call_core(req: Dictionary) -> Dictionary:
	if not start():
		return {"ok": false, "error": "chess core is not running"}
	var p := Pending.new()
	_mutex.lock()
	_next_id += 1
	var id := _next_id
	var msg := req.duplicate()
	msg["id"] = id
	_pending[id] = p
	_queue.append([id, JSON.stringify(msg)])
	_mutex.unlock()
	_sem.post()
	var res: Dictionary = await p.done
	return res


# --- convenience wrappers ---------------------------------------------------------------------

func load_variant(variant_name: String, ini: String) -> Dictionary:
	return await call_core({"op": "load_variant", "name": variant_name, "ini": ini})


func validate(fen: String) -> Dictionary:
	return await call_core({"op": "validate", "fen": fen})


func legal(fen: String, moves: PackedStringArray) -> PackedStringArray:
	var res: Dictionary = await call_core({"op": "legal", "fen": fen, "moves": Array(moves)})
	return PackedStringArray(res.get("moves", []))


func apply(fen: String, moves: PackedStringArray, move: String) -> Dictionary:
	return await call_core({"op": "apply", "fen": fen, "moves": Array(moves), "move": move})


func result(fen: String, moves: PackedStringArray) -> Dictionary:
	return await call_core({"op": "result", "fen": fen, "moves": Array(moves)})


func in_check(fen: String, side: String) -> bool:
	var res: Dictionary = await call_core({"op": "in_check", "fen": fen, "side": side})
	return bool(res.get("check", false))


## Moves of the side to move that win at once.
func mates_in_one(fen: String) -> PackedStringArray:
	var res: Dictionary = await call_core({"op": "mates_in_one", "fen": fen})
	return PackedStringArray(res.get("moves", []))


## Key moves of the side to move that win next move whatever the reply (problems; nothing wins at once).
func mate_in_two(fen: String) -> PackedStringArray:
	var res: Dictionary = await call_core({"op": "mate_in_two", "fen": fen})
	return PackedStringArray(res.get("moves", []))


func engine_move(fen: String, moves: PackedStringArray, movetime_ms: int, skill: int, depth: int = 0) -> Dictionary:
	return await call_core({"op": "engine_move", "fen": fen, "moves": Array(moves),
		"movetime_ms": movetime_ms, "skill": skill, "depth": depth})


# --- threads ----------------------------------------------------------------------------------

func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			break
		var item: Array = _queue.pop_front() if not _queue.is_empty() else []
		_mutex.unlock()
		if item.is_empty():
			continue
		var id: int = item[0]
		var res: Dictionary
		if _dead:
			res = {"ok": false, "error": "chess core exited"}
		else:
			_stdio.store_string(String(item[1]) + "\n")
			_stdio.flush()
			var reply := _stdio.get_line()
			var parsed: Variant = JSON.parse_string(reply) if reply != "" else null
			if parsed is Dictionary:
				res = parsed
			else:
				_dead = reply == ""
				res = {"ok": false, "error": "chess core reply: '%s'" % reply}
		call_deferred("_deliver", id, res)


func _drain_stderr() -> void:
	while not _quit:
		var line := _stderr.get_line()
		if line == "" and _stderr.get_error() != OK:
			break
		if log_stderr and line != "":
			print("[core] ", line)


func _deliver(id: int, res: Dictionary) -> void:
	_mutex.lock()
	var p: Pending = _pending.get(id)
	_pending.erase(id)
	_mutex.unlock()
	if p != null:
		p.done.emit(res)


func stop() -> void:
	if _pid <= 0:
		return
	_mutex.lock()
	_quit = true
	_mutex.unlock()
	if not _dead:
		OS.kill(_pid)
	_sem.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _err_thread != null and _err_thread.is_started():
		_err_thread.wait_to_finish()
	_pid = -1


func _exit_tree() -> void:
	stop()
