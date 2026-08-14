extends SceneTree
## godot --headless --path . -s res://tests/unit/selftest_scn_unsafe.gd
## 含外链 gdignore PNG 的 .scn 必须被标 unsafe，避免 ResourceLoader 刷屏。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cases := [
		"res://assets/asset-converted/Doodads/Terrain/LordaeronTree/LordaeronTree0.scn",
		"res://assets/asset-converted/Doodads/Ashenvale/Water/AshenvaleLilyPad/AshenvaleLilyPad0.scn",
		"res://assets/asset-converted/Units/Human/Peasant/Peasant.scn",
	]
	var bad := 0
	for p in cases:
		var unsafe := RuntimeAssets.is_packed_scene_unsafe_for_resource_loader(str(p))
		var resolved := RuntimeAssets.resolve_model_scene(str(p))
		print("%s unsafe=%s resolve='%s'" % [p, unsafe, resolved])
		if not unsafe or not resolved.is_empty():
			bad += 1
	print("RESULT bad=%d" % bad)
	quit(0 if bad == 0 else 1)
