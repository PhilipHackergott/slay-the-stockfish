extends Node
## Loads every content resource under res://data once, and knows which letter stands for which
## piece type in the current fight.

var pieces: Dictionary = {}
var encounters: Dictionary = {}
var relics: Dictionary = {}
var events: Dictionary = {}
var acts: Dictionary = {}
var perks: Dictionary = {}
var omens: Dictionary = {}
var difficulties: Array = []
var config: RunConfig

## Letters of the current fight: lower-case letter -> piece id (custom pieces get theirs per fight).
var _letters: Dictionary = {}
## The player's king line node (w): king, warlord, conqueror or regent.
var _royal_type: StringName = &"king"


func _init() -> void:
	reload()


func reload() -> void:
	pieces = _load_dir("res://data/pieces")
	encounters = _load_dir("res://data/encounters")
	relics = _load_dir("res://data/relics")
	events = _load_dir("res://data/events")
	acts = _load_dir("res://data/acts")
	perks = _load_dir("res://data/perks")
	omens = _load_dir("res://data/omens")
	difficulties = _load_dir("res://data/difficulty").values()
	difficulties.sort_custom(func(a, b): return a.level < b.level)
	config = load("res://data/run_config.tres") as RunConfig
	if config == null:
		push_warning("content: data/run_config.tres missing, using defaults")
		config = RunConfig.new()


func _load_dir(dir: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var res := load(dir.path_join(file))
		if res != null and "id" in res:
			out[res.id] = res
	return out


## Stitched pieces (the Tailor): "<base>__<atom>" is the base piece plus one Betza atom.
const STITCH := "__"
const STITCH_VALUE := {"W": 2, "F": 2, "N": 3}
const STITCH_TEXT := {"W": "also steps one square straight", "F": "also steps one square diagonally",
	"N": "also leaps like a knight"}
var _stitched: Dictionary = {}


func piece(id: StringName) -> PieceDef:
	var d: PieceDef = pieces.get(id)
	if d == null and String(id).contains(STITCH):
		d = _stitched.get(id)
		if d == null:
			d = _stitch(id)
	return d


static func stitched_id(base: StringName, atom: String) -> StringName:
	return StringName("%s%s%s" % [base, STITCH, atom])


func _stitch(id: StringName) -> PieceDef:
	var parts := String(id).split(STITCH)
	var b: PieceDef = pieces.get(StringName(parts[0]))
	if b == null or parts.size() != 2 or not STITCH_VALUE.has(parts[1]):
		return null
	var d: PieceDef = b.duplicate()
	d.id = id
	d.letter = ""
	d.betza = Betza.of(b.id) + parts[1]
	d.value = b.value + int(STITCH_VALUE[parts[1]])
	d.display_name = "Stitched " + b.display_name
	d.moves_text = "%s Stitched: %s." % [b.moves_text, STITCH_TEXT[parts[1]]]
	d.rarity = &""
	d.unlock = &""
	d.look = b.look if b.look != &"" else b.id
	_stitched[id] = d
	return d


## letters: {piece id: letter} from VariantGen for custom pieces. royal_type: the player's king node.
func set_fight_letters(letters: Dictionary, royal_type: StringName = &"king") -> void:
	_letters.clear()
	for id in letters:
		_letters[String(letters[id]).to_lower()] = StringName(id)
	_royal_type = royal_type


func clear_fight_letters() -> void:
	_letters.clear()
	_royal_type = &"king"


## The letter a type shows on the board this fight (lower case), or "" if it has none yet.
func letter_of(id: StringName) -> String:
	var def := piece(id)
	if def == null:
		return ""
	if def.is_royal() and id != &"king":
		return VariantGen.PLAYER_KING
	if def.letter != "":
		return def.letter
	for l in _letters:
		if _letters[l] == id:
			return l
	return ""


## white: the player's side (W is the player's king line, k the engine's king).
func piece_by_letter(letter: String, white: bool = true) -> PieceDef:
	var l := letter.to_lower()
	if l == VariantGen.PLAYER_KING:
		return pieces.get(_royal_type if white else &"king", pieces.get(&"king"))
	if _letters.has(l):
		return piece(_letters[l])
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


func act(id: StringName) -> ActDef:
	return acts.get(id)


func omen(id: StringName) -> OmenDef:
	return omens.get(id)


func difficulty(level: int) -> DifficultyDef:
	for d in difficulties:
		if d.level == level:
			return d
	return null


func encounters_of(kind: StringName, tier: int = -1) -> Array:
	var out: Array = []
	for e in encounters.values():
		if e.kind == kind and (tier < 0 or e.tier == tier):
			out.append(e)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


## Recruitable pieces of one tier, sorted by id.
func recruits_of_tier(tier: int) -> Array:
	var out: Array = pieces.values().filter(func(p): return p.tier == tier and p.is_recruitable())
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


func perk(id: StringName) -> PerkDef:
	return perks.get(id)


## Perk ids in a fixed order.
func perk_ids() -> Array:
	var ids: Array = perks.keys()
	ids.sort()
	return ids
