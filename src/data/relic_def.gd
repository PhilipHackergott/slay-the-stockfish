class_name RelicDef
extends Resource
## A relic. kind (how it reads): rule (variant lines), pocket (FEN pocket + drops), edit (position
## edit), hybrid (lift a piece into the pocket, drop it as a move), clock (player clock), gold
## (economy), xp (experience), army (your pieces and Command), engine (the enemy), curse.
## tier: common, uncommon, rare, boss (guardian rewards), curse (pacts; never offered).

@export var id: StringName
@export var display_name: String
@export var kind: StringName
@export var tier: StringName = &"common"
@export_multiline var description: String
## rule: lines appended to the fight's variant section.
@export var ini_lines: PackedStringArray
## rule: 0-based ranks where the player's pawns promote (the edit validator needs them).
@export var promotion_ranks: PackedInt32Array
## pocket: white pocket letters at the start of each fight, e.g. "B" (standard letters only).
@export var pocket: String
## edit / hybrid: uses per fight.
@export var charges_per_fight: int = 0
## edit: &"swap" (two of your pieces trade places) or &"move" (one piece to an empty square).
@export var edit_kind: StringName = &"swap"
## clock: extra base time and extra increment in seconds (negative shortens).
@export var clock_bonus_s: int = 0
@export var increment_bonus_s: int = 0
## gold: extra share of fight gold (0.5 = +50 %), and flat gold per won fight.
@export var gold_bonus: float = 0.0
@export var gold_flat: int = 0
## Shop prices are multiplied by this.
@export var price_mult: float = 1.0
## Extra Command for the deployed army.
@export var command_bonus: int = 0
## Temporary pieces that join every fight on your third rank (no run units, no XP).
@export var start_pieces: PackedStringArray
## The first of your pieces slain in a won fight gets back up.
@export var save_first_slain: bool = false
## A fight that would end the run is fought again from the start instead; the relic is used up.
@export var second_chance: bool = false
## Campfires offer Graft (fuse two pieces) while you hold it.
@export var campfire_graft: bool = false
## XP: per capture by pieces of a model family (xp_family "" = every piece), a multiplier on capture
## XP, to every piece that fought after a won fight, and to the survivors whenever one falls.
@export var xp_family: StringName
@export var xp_bonus: int = 0
@export var xp_mult: float = 1.0
@export var xp_after_fight: int = 0
@export var xp_on_loss: int = 0
## Rewards: extra recruit cards, extra relic cards.
@export var extra_reward_choice: int = 0
@export var relic_choice_bonus: int = 0
## Engine: skill change, thinking-time multiplier, moves first, enemy material multiplier.
@export var engine_skill_delta: int = 0
@export var movetime_mult: float = 1.0
@export var engine_first: bool = false
@export var enemy_ratio_mult: float = 1.0
## Campfire Kindle: what the stronger version does (empty = cannot be kindled).
@export var kindle_text: String
## Shop price before difficulty (0 = the tier's price from the run config).
@export var price: int = 0
## Profile unlock key ("" = always available).
@export var unlock: StringName
@export var icon: String


## A copy with its numbers raised by half (Kindle at a campfire). Drawbacks stay as they are.
func kindled() -> RelicDef:
	var k: RelicDef = duplicate()
	k.display_name = display_name + " (kindled)"
	k.description = kindle_text if kindle_text != "" else description
	k.clock_bonus_s = _up(clock_bonus_s)
	k.increment_bonus_s = _up(increment_bonus_s)
	k.gold_bonus = gold_bonus * 1.5 if gold_bonus > 0.0 else gold_bonus
	k.gold_flat = _up(gold_flat)
	k.price_mult = 1.0 - (1.0 - price_mult) * 1.5 if price_mult < 1.0 else price_mult
	k.command_bonus = _up(command_bonus)
	k.xp_bonus = _up(xp_bonus)
	k.xp_mult = 1.0 + (xp_mult - 1.0) * 1.5 if xp_mult > 1.0 else xp_mult
	k.xp_after_fight = _up(xp_after_fight)
	k.xp_on_loss = _up(xp_on_loss)
	k.charges_per_fight = _up(charges_per_fight)
	k.engine_skill_delta = -_up(-engine_skill_delta) if engine_skill_delta < 0 else engine_skill_delta
	k.movetime_mult = 1.0 - (1.0 - movetime_mult) * 1.5 if movetime_mult < 1.0 else movetime_mult
	return k


static func _up(n: int) -> int:
	return ceili(n * 1.5) if n > 0 else n
