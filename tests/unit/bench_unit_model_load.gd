extends SceneTree
## godot --headless --path . -s res://tests/unit/bench_unit_model_load.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var samples := [
		"Units/Creeps/ForestTroll/ForestTroll.gltf",
		"Units/Creeps/Ogre/Ogre.gltf",
		"Units/Creeps/BanditMage/BanditMage.gltf",
		"Units/Creeps/GiantSeaTurtle/GiantSeaTurtle.gltf",
		"Buildings/Other/GoldMine/GoldMine.gltf",
		"Buildings/Other/Tavern/Tavern.gltf",
	]
	print("=== bench unit model load ===")
	for rel in samples:
		var gltf_res := RuntimeAssets.converted_path(rel)
		var scn_res := RuntimeAssets.model_scene_path(rel)
		var scn_disk := RuntimeAssets.project_abs(scn_res)
		var scn_sz := 0
		if FileAccess.file_exists(scn_disk):
			var f := FileAccess.open(scn_disk, FileAccess.READ)
			scn_sz = int(f.get_length())
			f.close()

		# resolve / unsafe / size gate
		var t0 := Time.get_ticks_msec()
		var resolved := RuntimeAssets.resolve_model_scene(gltf_res)
		var resolve_ms := Time.get_ticks_msec() - t0

		var scn_ms := -1
		if FileAccess.file_exists(scn_disk):
			t0 = Time.get_ticks_msec()
			# bypass size gate for fair measure
			var packed: Resource = ResourceLoader.load(scn_res, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			scn_ms = Time.get_ticks_msec() - t0
			if packed:
				packed = null

		t0 = Time.get_ticks_msec()
		var node := RuntimeAssets.load_gltf_scene(gltf_res)
		var gltf_ms := Time.get_ticks_msec() - t0
		if node:
			node.free()

		print(
			(
				"%s scn_mb=%.2f resolve_ms=%d resolved='%s' scn_load_ms=%d gltf_ms=%d"
				% [
					rel.get_file(),
					float(scn_sz) / 1000000.0,
					resolve_ms,
					resolved.get_file() if not resolved.is_empty() else "",
					scn_ms,
					gltf_ms,
				]
			)
		)
	quit(0)
