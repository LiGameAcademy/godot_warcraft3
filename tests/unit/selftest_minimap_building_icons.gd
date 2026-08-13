extends SceneTree
## godot --headless --path . -s res://tests/unit/selftest_minimap_building_icons.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ids := PackedStringArray([
		"ngol", "nmer", "ntav", "ngme", "nmrk", "nmh0", "nmh1"
	])
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	var cmd := CommandButtonCatalog.get_shared()

	var tree := Engine.get_main_loop() as SceneTree
	var ds: Node = tree.root.get_node_or_null("Wc3DefStore") if tree != null else null
	print("DefStore node=%s" % ds)
	if ds != null:
		ds.ensure_table(UnitBalanceDef.TABLE_NAME)
		var bal: Resource = ds.get_row(UnitBalanceDef.TABLE_NAME, "ngol")
		if bal is UnitBalanceDef:
			print("ngol UnitBalance.isbldg=%s" % (bal as UnitBalanceDef).isbldg)
		else:
			print("ngol row missing or wrong type: %s" % bal)

	var ok := 0
	var bad := 0
	for id in ids:
		var info: Dictionary = cat.lookup(id)
		var is_bldg := bool(info.get("is_building", false))
		var art_info := str(info.get("art", ""))
		var tex_cat: Texture2D = cat.unit_art_texture(id)
		var row: Dictionary = cmd.get_unit_ui(id)
		var art_cmd := str(row.get("art", ""))
		var tex_cmd: Texture2D = null
		if not art_cmd.is_empty():
			var p := art_cmd.replace("\\", "/")
			var lower := p.to_lower()
			if lower.ends_with(".blp") or lower.ends_with(".tga"):
				p = p.substr(0, p.length() - 4) + ".png"
			elif not lower.ends_with(".png"):
				p = p + ".png"
			tex_cmd = RuntimeAssets.load_converted_texture(p)
		var bv := BuildingVisual.is_building(id)
		print(
			(
				"%s catalog.is_building=%s BuildingVisual=%s art_info='%s' tex_cat=%s art_cmd='%s' tex_cmd=%s"
				% [
					id,
					is_bldg,
					bv,
					art_info,
					tex_cat != null,
					art_cmd,
					tex_cmd != null,
				]
			)
		)
		if bv and (tex_cat != null or tex_cmd != null):
			ok += 1
		else:
			bad += 1

	for logical in [
		"UI/MiniMap/minimap-gold.png",
		"UI/MiniMap/minimap-neutralbuilding.png",
	]:
		var t := RuntimeAssets.load_converted_texture(logical)
		print("category %s → %s" % [logical, t != null])

	print("RESULT ok=%d bad=%d" % [ok, bad])
	quit(0 if bad == 0 else 1)
