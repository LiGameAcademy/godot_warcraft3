extends SceneTree
## 小地图 Phase 3 冒烟：Catalog 色 + Lost Temple 光栅尺寸。
## godot --headless --path . -s res://tests/unit/selftest_minimap_raster.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var terrain_path := "res://assets/map-parsed/losttemple/terrain.json"
	var hf_path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	if not FileAccess.file_exists(terrain_path) or not FileAccess.file_exists(hf_path):
		push_error("selftest_minimap_raster: missing losttemple parsed data")
		quit(1)
		return

	var terrain: Variant = JSON.parse_string(FileAccess.get_file_as_string(terrain_path))
	var hf_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(hf_path))
	if typeof(terrain) != TYPE_DICTIONARY or typeof(hf_raw) != TYPE_DICTIONARY:
		push_error("selftest_minimap_raster: bad JSON")
		quit(1)
		return
	var tdict: Dictionary = terrain
	var hf_dict: Dictionary = hf_raw
	for k in [
		"groundTilesets",
		"cliffTilesets",
		"mainTileset",
		"tilepointWidth",
		"tilepointHeight",
		"centerOffset",
		"mapWidth",
		"mapHeight",
	]:
		if tdict.has(k) and not hf_dict.has(k):
			hf_dict[k] = tdict[k]
	var hf := Wc3Heightfield.from_dict(hf_dict)
	if not hf.is_valid():
		push_error("selftest_minimap_raster: invalid heightfield")
		quit(1)
		return

	var tiles := Wc3TerrainTileCatalog.new()
	tiles.load_default()
	var colors: PackedColorArray = Wc3GroundTileCatalog.build_minimap_colors(
		hf.ground_tilesets, tiles
	)
	if colors.size() != hf.ground_tilesets.size() or colors.is_empty():
		push_error("selftest_minimap_raster: colors size mismatch")
		ok = false
	else:
		print("  minimap colors=%d first=%s" % [colors.size(), colors[0]])

	var cliffs := Wc3CliffCatalog.new()
	cliffs.load_default()
	var img: Image = MapMinimapRaster.rasterize_from(hf, tiles, cliffs)
	if img == null:
		push_error("selftest_minimap_raster: rasterize returned null")
		ok = false
	elif img.get_width() != hf.width or img.get_height() != hf.height:
		push_error(
			"selftest_minimap_raster: size want %dx%d got %dx%d"
			% [hf.width, hf.height, img.get_width(), img.get_height()]
		)
		ok = false
	else:
		print(
			"  raster OK %dx%d sample=%s"
			% [img.get_width(), img.get_height(), img.get_pixel(80, 80)]
		)

	var tmp := "user://selftest_war3mapMap.png"
	var bake_err: Error = MapMinimapRaster.bake_war3map_png(img, tmp)
	if bake_err != OK:
		push_error("selftest_minimap_raster: bake failed %s" % error_string(bake_err))
		ok = false
	else:
		var baked := Image.new()
		if baked.load(ProjectSettings.globalize_path(tmp)) != OK:
			push_error("selftest_minimap_raster: cannot reload bake")
			ok = false
		elif baked.get_width() != 256 or baked.get_height() != 256:
			push_error("selftest_minimap_raster: bake size not 256")
			ok = false
		else:
			print("  bake OK 256x256")

	var fov_s: float = MapMinimapUtils.effective_fov_screen_scale(75.0, 50.0)
	if fov_s >= 1.0 or fov_s < 0.5:
		push_error("selftest_minimap_raster: unexpected fov scale %s" % fov_s)
		ok = false
	else:
		print("  effective fov scale(75→50)=%.3f" % fov_s)

	# 显示图应为 256；水色：含水格且 water>ground 应偏蓝
	var r := MapMinimapRaster.new(hf)
	r.setup_terrain(colors, cliffs.build_cliff_to_ground_map(hf.cliff_tilesets, hf.ground_tilesets))
	r.rasterize()
	var disp: Image = r.get_display_image()
	if disp == null or disp.get_width() != 256 or disp.get_height() != 256:
		push_error("selftest_minimap_raster: display not 256")
		ok = false
	else:
		print("  display OK 256x256")
	var water_tinted := 0
	var water_flags := 0
	for i in range(hf.flags_packed.size()):
		if (int(hf.flags_packed[i]) & Wc3Coords.FLAG_WATER) == 0:
			continue
		water_flags += 1
		var gh: float = float(hf.heights[i])
		var wh: float = float(hf.water_heights[i]) + r.get_water_offset_wc3()
		if wh > gh:
			water_tinted += 1
	print(
		"  water flags=%d visible(waterH>groundH)=%d offset=%.1f"
		% [water_flags, water_tinted, r.get_water_offset_wc3()]
	)
	if water_flags > 0 and water_tinted <= 0:
		push_error("selftest_minimap_raster: no visible water despite flags")
		ok = false

	if ok:
		print("selftest_minimap_raster: OK")
		quit(0)
	else:
		print("selftest_minimap_raster: FAIL")
		quit(1)
