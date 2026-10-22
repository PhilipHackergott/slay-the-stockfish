class_name EndScreen
extends Control
## Run over: the engine fell, or your king did.

signal new_run
signal to_title

var victory := false
var reason := ""


func setup(p_victory: bool, p_reason: String) -> EndScreen:
	victory = p_victory
	reason = p_reason
	return self


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.55)
	UiKit.full(shade)
	add_child(shade)
	add_child(UiKit.vignette())
	var accent := UiKit.GOLD if victory else UiKit.BLOOD
	var p := UiKit.panel(accent, Color(0.03, 0.025, 0.045, 0.94), 30)
	p.custom_minimum_size = Vector2(1000, 0)
	var col := UiKit.vbox(12)
	p.add_child(col)
	var cc := UiKit.centered(p)
	UiKit.full(cc)
	add_child(cc)
	var t := UiKit.title("The Engine Falls" if victory else "Your King Falls", 72, accent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var r := UiKit.label(reason, 24, UiKit.BONE)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(r)
	var s: Dictionary = Run.stats
	var st := UiKit.label("Seed %d · %d nodes · %d fights won · %d pieces lost" % [Run.seed_value, Run.visited.size(),
		int(s.get("fights_won", 0)), int(s.get("units_lost", 0))], 20, UiKit.MUTED)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(st)
	col.add_child(UiKit.heading("Your army at the end", 26))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for u in Run.units:
		grid.add_child(ArmyPanel.row(u, true))
	var btns := UiKit.hbox(20)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_child(UiKit.button("Begin a new run", func(): new_run.emit(), 24))
	btns.add_child(UiKit.button("Title", func(): to_title.emit(), 24))
	col.add_child(UiKit.spacer(8))
	col.add_child(btns)
	UiKit.fade_in(self, 0.8)
