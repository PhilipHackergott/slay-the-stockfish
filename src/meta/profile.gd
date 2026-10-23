extends Node
## What outlives a run: stats, unlocks, the highest difficulty tier reached, and settings.
## Stored in user://profile.json.

signal unlocked(key: StringName)

const VERSION := 1
## Unlock keys, what earns them, and what they open (pieces and relics name the key in `unlock`).
const UNLOCKS := {
	&"runs_1": "Finish a run",
	&"runs_2": "Finish two runs",
	&"guardian_1": "Defeat the Choir Engine",
	&"guardian_2": "Defeat the Abbot Engine",
	&"win": "Defeat Stockfish",
}

var path := "user://profile.json"
var data: Dictionary = {}


func _ready() -> void:
	load_profile()


func defaults() -> Dictionary:
	return {
		"version": VERSION, "runs": 0, "wins": 0, "max_difficulty": 0, "best_act": 0, "unlocks": [],
		"settings": {"master_db": 0.0, "music_db": -6.0, "sfx_db": -2.0, "fullscreen": false},
	}


func load_profile() -> void:
	data = defaults()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("profile: %s is unreadable, starting fresh" % path)
		return
	for k in parsed:
		if k == "settings" and parsed[k] is Dictionary:
			data["settings"].merge(parsed[k], true)
		else:
			data[k] = parsed[k]


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("profile: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func reset() -> void:
	data = defaults()
	save()


func is_unlocked(key: StringName) -> bool:
	return key == &"" or Array(data.get("unlocks", [])).has(String(key))


## Returns true when the key is new.
func unlock(key: StringName) -> bool:
	if is_unlocked(key):
		return false
	var list: Array = data.get("unlocks", [])
	list.append(String(key))
	data["unlocks"] = list
	unlocked.emit(key)
	return true


func max_difficulty() -> int:
	return int(data.get("max_difficulty", 0))


func runs() -> int:
	return int(data.get("runs", 0))


func wins() -> int:
	return int(data.get("wins", 0))


## Act guardian defeated (act 1 or 2). Returns the keys it unlocked.
func record_guardian(act_index: int) -> Array:
	var out: Array = []
	var key := StringName("guardian_%d" % act_index)
	if UNLOCKS.has(key) and unlock(key):
		out.append(key)
	data["best_act"] = maxi(int(data.get("best_act", 0)), act_index + 1)
	save()
	return out


## A run ended. Returns what it unlocked: keys, plus "difficulty_N" for a new tier.
func record_run_end(victory: bool, difficulty: int, act_reached: int, top_difficulty: int) -> Array:
	var out: Array = []
	data["runs"] = runs() + 1
	data["best_act"] = maxi(int(data.get("best_act", 0)), act_reached)
	for n in [1, 2]:
		var key := StringName("runs_%d" % n)
		if runs() >= n and unlock(key):
			out.append(key)
	if victory:
		data["wins"] = wins() + 1
		if unlock(&"win"):
			out.append(&"win")
		if difficulty >= max_difficulty() and difficulty < top_difficulty:
			data["max_difficulty"] = difficulty + 1
			out.append(StringName("difficulty_%d" % (difficulty + 1)))
	save()
	return out


## What an unlock key opened, for the end screen.
func unlock_text(key: String) -> String:
	if key.begins_with("difficulty_"):
		var d: DifficultyDef = Content.difficulty(int(key.trim_prefix("difficulty_")))
		return "Difficulty: %s (%s)" % [d.display_name, d.description] if d != null else key
	var names: Array = []
	for p in Content.pieces.values():
		if String(p.unlock) == key:
			names.append(p.display_name)
	for r in Content.relics.values():
		if String(r.unlock) == key:
			names.append(r.display_name)
	for a in Content.arenas.values():
		if String(a.unlock) == key:
			names.append("arena %s" % a.display_name)
	for e in Content.events.values():
		if String(e.unlock) == key:
			names.append("event %s" % e.title)
	var what: String = ", ".join(names) if not names.is_empty() else "nothing new"
	return "%s: %s" % [UNLOCKS.get(StringName(key), key), what]


func setting(key: String, default: Variant = null) -> Variant:
	return data.get("settings", {}).get(key, default)


func set_setting(key: String, value: Variant) -> void:
	var s: Dictionary = data.get("settings", {})
	s[key] = value
	data["settings"] = s
	save()
