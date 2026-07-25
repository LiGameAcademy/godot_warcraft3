extends SceneTree
## 复现：从层 2 升到层 5（+3）后 cliff_slices / 缺模 / 是否报错。


const DocScript := preload("res://editor/scripts/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"main_tileset_name": "Lordaeron Summer",
		"ground_tilesets": ["Ldrt"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
	})
	var cliffs := Wc3CliffCatalog.new()
	cliffs.load_default()

	var cx := 16
	var cy := 16
	# 单点连升 3 层（工具 "3"）
	for _step in range(3):
		doc.paint_cliff_corner(cx, cy, "3", 0)

	var layers: Array = doc.as_build_dict()["layerHeights"]
	var heights: Array = doc.as_build_dict()["heights"]
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	print("=== layers around (%d,%d) after +3 ===" % [cx, cy])
	for y in range(cy - 2, cy + 3):
		var row := ""
		for x in range(cx - 2, cx + 3):
			var i := y * tp_w + x
			row += "%d " % int(layers[i])
		print(row)
	# 对角必须被抬到 3，否则单格层差=3 → 碎柱
	var diag := int(layers[(cy - 1) * tp_w + (cx - 1)])
	if diag != 3:
		push_error("expected diagonal cake layer 3, got %d" % diag)
		quit(1)
		return
	print("=== heights (wc3) ===")
	for y in range(cy - 2, cy + 3):
		var row := ""
		for x in range(cx - 2, cx + 3):
			var i := y * tp_w + x
			row += "%d " % int(heights[i])
		print(row)
	print("=== ground_tiles (should ~0) ===")
	for y in range(cy - 2, cy + 3):
		var row := ""
		for x in range(cx - 2, cx + 3):
			var i := y * tp_w + x
			var layer := int(layers[i])
			var final_h := float(heights[i])
			var g := (final_h - float(layer - 2) * 128.0) / 128.0
			row += "%.2f " % g
		print(row)

	var missing_tags: Dictionary = {}
	var slice_count := 0
	for iy in range(cy - 3, cy + 3):
		for ix in range(cx - 3, cx + 3):
			if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var slices: Array = Wc3CliffLogic.cliff_slices_at(layers, tp_w, ix, iy)
			var i00 := iy * tp_w + ix
			var corners := "%d/%d/%d/%d" % [
				int(layers[i00]),
				int(layers[i00 + 1]),
				int(layers[i00 + tp_w]),
				int(layers[i00 + tp_w + 1]),
			]
			var tag_strs: PackedStringArray = PackedStringArray()
			for s in slices:
				var tag: String = str(s.get("tag", ""))
				var base: int = int(s.get("base_layer", 0))
				tag_strs.append("%s@%d" % [tag, base])
				slice_count += 1
				var model_dir := cliffs.cliff_model_dir("CLdi")
				var glb := cliffs.resolve_glb(model_dir, tag, 0)
				if glb.is_empty():
					missing_tags[tag] = true
					push_error("MISSING tile(%d,%d) corners=%s tag=%s" % [ix, iy, corners, tag])
			print("tile(%d,%d) %s -> %s" % [ix, iy, corners, " ".join(tag_strs)])

	var _pls: Array[Wc3CliffPlacement] = Wc3CliffLogic.collect_placements(doc.heightfield, cliffs)
	var collected: Wc3CliffBuildResult = Wc3CliffBuilder.build_from_placements(
		_pls, cliffs,
		doc.heightfield.center_offset, doc.heightfield.tile_size
	)
	print(
		"builder placed=%d missing=%d groups=%d slices=%d missing_tags=%s"
		% [
			collected.placed_cliffs,
			collected.missing,
			collected.groups.size(),
			slice_count,
			str(missing_tags.keys()),
		]
	)

	# ????????
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
	})
	var verts: Array = [
		Vector2i(cx, cy),
		Vector2i(cx + 1, cy), Vector2i(cx - 1, cy),
		Vector2i(cx, cy + 1), Vector2i(cx, cy - 1),
	]
	for _step2 in range(3):
		for v in verts:
			doc.paint_cliff_corner(int(v.x), int(v.y), "3", 0)
	layers = doc.as_build_dict()["layerHeights"]
	print("=== cross brush layers ===")
	for y in range(cy - 3, cy + 4):
		var row2 := ""
		for x in range(cx - 3, cx + 4):
			row2 += "%d " % int(layers[y * tp_w + x])
		print(row2)
	_pls = Wc3CliffLogic.collect_placements(doc.heightfield, cliffs)
	collected = Wc3CliffBuilder.build_from_placements(
		_pls, cliffs,
		doc.heightfield.center_offset, doc.heightfield.tile_size
	)
	print(
		"cross builder placed=%d missing=%d"
		% [collected.placed_cliffs, collected.missing]
	)

	quit(1 if not missing_tags.is_empty() or collected.missing > 0 else 0)
