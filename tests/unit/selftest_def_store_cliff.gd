extends SceneTree
## TerrainArt 四表 DefStore + Catalog 资源映射自测。
## godot --headless -s res://tests/unit/selftest_def_store_cliff.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_terrain_art_tables()
	failed += _test_catalog_asset_map()
	failed += _test_water_params_from_def()
	if failed == 0:
		print("selftest_def_store_cliff: PASS")
		quit(0)
	else:
		push_error("selftest_def_store_cliff: FAIL (%d)" % failed)
		quit(1)


func _test_terrain_art_tables() -> int:
	var store: Node = get_root().get_node_or_null("Wc3DefStore")
	if store == null:
		push_error("Wc3DefStore autoload missing")
		return 1
	var expected := {
		CliffTypeDef.TABLE_NAME: 10,
		TerrainTileDef.TABLE_NAME: 50,
		WaterTypeDef.TABLE_NAME: 10,
		WeatherEffectDef.TABLE_NAME: 10,
	}
	for table_name in expected.keys():
		if not store.has_table(table_name):
			push_error("table not registered: %s" % table_name)
			return 1
		var n: int = store.count(table_name)
		if n < int(expected[table_name]):
			push_error("%s too few: %d" % [table_name, n])
			return 1
	var cldi: CliffTypeDef = store.get_row(CliffTypeDef.TABLE_NAME, "CLdi") as CliffTypeDef
	if cldi == null or cldi.ground_tile != "Ldrt":
		push_error("CLdi groundTile mismatch")
		return 1
	var ldrt: TerrainTileDef = store.get_row(TerrainTileDef.TABLE_NAME, "Ldrt") as TerrainTileDef
	if ldrt == null or ldrt.file != "Lords_Dirt" or not ldrt.buildable:
		push_error("Ldrt TerrainTileDef mismatch")
		return 1
	var lrok: TerrainTileDef = store.get_row(TerrainTileDef.TABLE_NAME, "Lrok") as TerrainTileDef
	if lrok == null or lrok.buildable:
		push_error("Lrok should be non-buildable")
		return 1
	var lsha: WaterTypeDef = store.get_row(WaterTypeDef.TABLE_NAME, "LSha") as WaterTypeDef
	if lsha == null or lsha.num_tex <= 0:
		push_error("LSha WaterTypeDef missing")
		return 1
	var rain: WeatherEffectDef = store.get_row(WeatherEffectDef.TABLE_NAME, "RAhr") as WeatherEffectDef
	if rain == null or rain.tex_file.is_empty():
		push_error("RAhr WeatherEffectDef missing")
		return 1
	print(
		"  TerrainArt tables OK cliffs=%d terrain=%d water=%d weather=%d"
		% [
			store.count(CliffTypeDef.TABLE_NAME),
			store.count(TerrainTileDef.TABLE_NAME),
			store.count(WaterTypeDef.TABLE_NAME),
			store.count(WeatherEffectDef.TABLE_NAME),
		]
	)
	return 0


func _test_catalog_asset_map() -> int:
	var tiles := Wc3TerrainTileCatalog.new()
	tiles.load_default()
	var cliffs := Wc3CliffCatalog.new()
	cliffs.load_default()
	if cliffs.ground_tile_for_cliff_id("CLdi") != "Ldrt":
		push_error("CliffCatalog CLdi ground mismatch")
		return 1
	if cliffs.cliff_model_dir("CLdi") != "Cliffs":
		push_error("CliffCatalog model dir mismatch")
		return 1
	var cliff_png: String = cliffs.png_for_cliff_id("CLdi")
	if cliff_png.is_empty():
		push_error("png_for_cliff_id empty")
		return 1
	var tile_png: String = tiles.png_for_tile_id("Ldrt")
	if tile_png.is_empty() or not tile_png.ends_with("Lords_Dirt.png"):
		push_error("png_for_tile_id Ldrt bad: %s" % tile_png)
		return 1
	if tiles.is_buildable("Lrok"):
		push_error("Lrok should not be buildable via TerrainTiles")
		return 1
	var lordaeron := tiles.tile_ids_for_tileset("L")
	if lordaeron.is_empty() or not "Ldrt" in lordaeron:
		push_error("tile_ids_for_tileset(L) missing Ldrt")
		return 1
	var cliff_ids := cliffs.cliff_ids_for_tileset("L")
	if cliff_ids.is_empty() or not "CLdi" in cliff_ids:
		push_error("cliff_ids_for_tileset(L) missing CLdi")
		return 1
	print("  Catalog asset map OK cliff=%s tile=%s" % [cliff_png.get_file(), tile_png.get_file()])
	return 0


func _test_water_params_from_def() -> int:
	var p := Wc3WaterParams.load_for_tileset("L")
	if p.water_id != "LSha":
		push_error("water_id want LSha got %s" % p.water_id)
		return 1
	if p.num_tex <= 0:
		push_error("LSha num_tex empty")
		return 1
	if p.tex_file_prefix.find("Water") < 0:
		push_error("tex_file_prefix bad: %s" % p.tex_file_prefix)
		return 1
	print("  WaterParams from Def OK id=%s frames=%d" % [p.water_id, p.frame_pngs.size()])
	return 0
