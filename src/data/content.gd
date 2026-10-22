extends Node
## Loads every content resource under res://data once.

var pieces: Dictionary = {}
var encounters: Dictionary = {}
var relics: Dictionary = {}
var events: Dictionary = {}
var config: RunConfig


func _init() -> void:
	reload()


func reload() -> void:
	pieces = _load_dir("res://data/pieces")
	encounters = _load_dir("res://data/encounters")
	relics = _load_dir("res://data/relics")
	events = _load_dir("res://data/events")
	config = load("res://data/run_config.tres") as RunConfig
	if config == null:
		push_warning("content: data/run_config.tres missing, using defaults")
		config = RunConfig.new()


func _load_dir(dir: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var res := load(dir.path_join(file))
		if res != null and "id" in res:
			out[res.id] = res
	return out


func piece(id: StringName) -> PieceDef:
	return pieces.get(id)


func piece_by_letter(letter: String) -> PieceDef:
	var l := letter.to_lower()
	if l == VariantGen.PLAYER_KING:
		return pieces.get(&"king")
	for p in pieces.values():
		if p.letter == l:
			return p
	return null


func value_of_letter(letter: String) -> int:
	var p := piece_by_letter(letter)
	return p.value if p != null else 0


func relic(id: StringName) -> RelicDef:
	return relics.get(id)


func encounter(id: StringName) -> EncounterDef:
	return encounters.get(id)


func encounters_of(kind: StringName, tier: int = -1) -> Array:
	var out: Array = []
	for e in encounters.values():
		if e.kind == kind and (tier < 0 or e.tier == tier):
			out.append(e)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out
