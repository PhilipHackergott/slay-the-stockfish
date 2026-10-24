class_name RunFixture
extends RefCounted
## Tests that need an army start from the pre-draft classic one: king, four pawns, knight, bishop
## (unit ids 1 to 7), with the draft closed and no leftover gold.

const CLASSIC := [&"pawn", &"pawn", &"pawn", &"pawn", &"knight", &"bishop"]


static func classic(p_seed: int, p_difficulty: int = 0) -> void:
	Run.new_run(p_seed, p_difficulty)
	var army: Array = CLASSIC.duplicate()
	for t in Run.difficulty_mods()["remove_from_start"]:
		army.erase(t)
	for t in army:
		Run.add_unit(t)
	Run.draft.clear()
