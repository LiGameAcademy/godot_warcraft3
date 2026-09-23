extends SceneTree
# Behavioral oracle from HiveWE b70f9b8, terrain.ixx entrance/height/texture rules.
var failed := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		if failed < 10:
			push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var doc = preload("res://documents/map_document.gd").new()
	doc.create_from_options({"width": 4, "height": 4, "main_tileset": "L", "ground_tilesets": ["Ldrt", "Lgrs"], "cliff_tilesets": ["CLdi", "CLgr"]})
	var hf: Wc3Heightfield = doc.heightfield
	var indices := [6, 7, 11, 12]
	for heights in range(81):
		var digits := heights
		var levels: Array[int] = []
		for i in range(4):
			levels.append(2 + digits % 3)
			digits = digits / 3
		for flags in range(16):
			hf.flags_packed.fill(0)
			hf.layer_heights.fill(2)
			for i in range(4):
				hf.layer_heights[indices[i]] = levels[i]
				hf.flags_packed[indices[i]] = Wc3Coords.FLAG_RAMP if flags & (1 << i) else 0
			var entrance := flags == 15 and not (levels[0] == levels[3] and levels[1] == levels[2])
			check(Wc3RampCollect.is_entrance(hf.flags_packed, hf.layer_heights, 5, 5, 1, 1) == entrance, "entrance disagrees with HiveWE")
			var entries := Wc3RampCollect.plan_entrance_tiles(hf)
			check(entries.has(Vector2i(1, 1)) == entrance, "ground existence disagrees with entrance")
			var boost := Wc3RampCollect.plan_entrance_height_boost(hf)
			var low: int = levels.min()
			for i in range(4):
				check((boost[indices[i]] != 0) == (entrance and levels[i] == low), "height boost disagrees with HiveWE")
	for flags in range(64):
		var a := [flags & 1, (flags >> 1) & 1, (flags >> 2) & 1]
		var b := [(flags >> 3) & 1, (flags >> 4) & 1, (flags >> 5) & 1]
		var valid := (a == [0, 0, 0] and b == [1, 1, 1]) or (a == [1, 1, 1] and b == [0, 0, 0])
		check(Wc3RampCollect._ramp_cols_opposite(a[0], a[1], a[2], b[0], b[1], b[2]) == valid, "model matching accepts a broken column")
	hf.layer_heights.fill(2)
	hf.layer_heights[6] = 3
	hf.flags_packed.fill(0)
	hf.ground_textures.fill(0)
	hf.cliff_textures.fill(0)
	hf.cliff_textures[12] = 1
	var romp := PackedByteArray()
	romp.resize(25)
	var mapping := PackedInt32Array([3, 4])
	check(Wc3TerrainLogic.real_tile_texture(hf.ground_textures, hf.layer_heights, hf.cliff_textures, mapping, hf.flags_packed, romp, 5, 5, 2, 2) == 4, "texture must use queried corner type, not adjacent cliff type")
	hf.flags_packed[12] = Wc3Coords.FLAG_RAMP
	check(Wc3TerrainLogic.real_tile_texture(hf.ground_textures, hf.layer_heights, hf.cliff_textures, mapping, hf.flags_packed, romp, 5, 5, 2, 2) == 0, "ramp corner without romp retains painted ground")
	romp[6] = 1
	check(Wc3TerrainLogic.real_tile_texture(hf.ground_textures, hf.layer_heights, hf.cliff_textures, mapping, hf.flags_packed, romp, 5, 5, 2, 2) == 4, "romp forces matching cliff ground")
	hf.cliff_textures[12] = 15
	check(Wc3TerrainLogic.real_tile_texture(hf.ground_textures, hf.layer_heights, hf.cliff_textures, mapping, hf.flags_packed, romp, 5, 5, 2, 2) == 4, "sentinel cliff type maps to index one")
	print("selftest_ramp_hivewe: %s (%d failures; 1296 entrance cases, 64 model patterns, texture precedence)" % ["PASS" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)
