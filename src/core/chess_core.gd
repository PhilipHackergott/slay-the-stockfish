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
	var py := _python_path()
	var script := ProjectSettings.globalize_path("res://chesscore/server.py")
	var info: Dictionary = OS.execute_with_pipe(py, PackedStringArray([script]))
	if info.is_empty():
		push_warning("chess core: could not start %s %s" % [py, script])
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


func _python_path() -> String:
	var env := OS.get_environment("STS_PYTHON")
	if env != "":
		return env
	var venv := ProjectSettings.globalize_path("res://chesscore/.venv/bin/python")
	if FileAccess.file_exists(venv):
		return venv
	return "python3"


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
