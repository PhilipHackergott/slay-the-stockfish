extends SceneTree
## Parse gate (AUDIT R4): load() every .gd under res://src and res://tests (skipping .gdignore dirs).
## $GODOT --headless --path . -s res://scripts/check_parse.gd --quit-after 300   → exit code = broken count (max 100)
func _initialize() -> void:
	var files := _walk("res://src") + _walk("res://tests")
	var bad := 0
	for p in files:
		var s := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if s == null or not s.can_instantiate():
			bad += 1
			printerr("PARSE FAIL ", p)
	print("PARSE OK %d scripts" % files.size() if bad == 0 else "PARSE FAILED %d of %d" % [bad, files.size()])
	quit(mini(bad, 100))

func _walk(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_walk(dir.path_join(d)))
	return out
