class_name EndScreen
extends Control
## Run over: the engine fell, or your king did. Shows what the run unlocked.

signal new_run
signal to_title

var victory := false
var reason := ""
## Unlock keys this run earned (Profile.UNLOCKS / difficulty_N).
var unlocked: Array = []


func setup(p_victory: bool, p_reason: String, p_unlocked: Array = []) -> EndScreen:
	victory = p_victory
	reason = p_reason
	unlocked = p_unlocked
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := UiKit.GOLD if victory else UiKit.BLOOD
	var m := UiModal.new().setup("The Engine Falls" if victory else "Your King Falls", 1100, false, reason, 560)
	m.accent = accent
	add_child(m)
	Audio.music("")
	Audio.play("win_sting" if victory else "loss_sting")
	var col := m.body
	var s: Dictionary = Run.stats
	var act := Run.current_act()
	var diff := Content.difficulty(Run.difficulty)
	var st := UiKit.label("%s · %s · seed %d · %d fights won · %d pieces lost · %d gold earned" % [
		act.display_name if act else "Act %d" % (Run.act_index + 1), diff.display_name if diff else "Mortal",
		Run.seed_value, int(s.get("fights_won", 0)), int(s.get("units_lost", 0)), int(s.get("gold_earned", 0))], 19, UiKit.MUTED, true)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(st)
	if not unlocked.is_empty():
		col.add_child(UiKit.divider(600, true))
		col.add_child(UiKit.caption("Unlocked", 20, UiKit.GOLD))
		for key in unlocked:
			var l := UiKit.label(Profile.unlock_text(String(key)), 21, UiKit.SOUL)
			col.add_child(l)
	col.add_child(UiKit.divider(600, true))
	col.add_child(UiKit.caption("Your army at the end", 20, UiKit.BONE))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(UiKit.centered(grid))
	for u in Run.units:
		var r := ArmyPanel.row(u, true)
		r.custom_minimum_size.x = 310
		grid.add_child(r)
	m.footer.add_child(UiKit.button("Title", func(): to_title.emit(), 22))
	m.footer.add_child(UiKit.button("Begin a new run", func(): new_run.emit(), 24, true))
