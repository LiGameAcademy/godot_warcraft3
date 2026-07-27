extends SceneTree
## 诊断：草地崖周围边界格的四角纹理与 atlas mask。


const DocScript := preload("res://editor/scripts/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt", "Lgrs", "Lrok"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
		"default_tile_index": 0,
	})
	# 草地悬崖 CLgr = index 1，中心升 2 层
	var cx := 16
	var cy := 16
	for _s in range(2):
		doc.paint_cliff_corner(cx, cy, "3", 1)

	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	var tp_h: int = int(doc.as_build_dict()["tilepointHeight"])
	var ground: Array = doc.as_build_dict()["groundTextures"]
	var layers: Array = doc.as_build_dict()["layerHeights"]
	print("groundTilesets=", doc.as_build_dict()["groundTilesets"])
	print("=== groundTextures (0=Ldrt 1=Lgrs) ===")
	for y in range(cy - 3, cy + 4):
		var row := ""
		for x in range(cx - 3, cx + 4):
			row += "%d " % int(ground[y * tp_w + x])
		print(row)
	print("=== boundary tile masks (grass=1) ===")
	var terrain := MapTerrainLayer.new()
	var transition_tiles := 0
	for iy in range(cy - 3, cy + 3):
		for ix in range(cx - 3, cx + 3):
			if Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var bl := int(ground[iy * tp_w + ix])
			var br := int(ground[iy * tp_w + ix + 1])
			var tl := int(ground[(iy + 1) * tp_w + ix])
			var tr := int(ground[(iy + 1) * tp_w + ix + 1])
			# Present 强制后的角点
			var cat := Wc3CliffCatalog.new()
			cat.load_default()
			var c2g: PackedInt32Array = cat.build_cliff_to_ground_map(
				doc.as_build_dict()["cliffTilesets"],
				doc.as_build_dict()["groundTilesets"]
			)
			var cliff_tex: Array = doc.as_build_dict()["cliffTextures"]
			bl = terrain.corner_texture(ground, layers, cliff_tex, c2g, tp_w, tp_h, ix, iy)
			br = terrain.corner_texture(ground, layers, cliff_tex, c2g, tp_w, tp_h, ix + 1, iy)
			tl = terrain.corner_texture(ground, layers, cliff_tex, c2g, tp_w, tp_h, ix, iy + 1)
			tr = terrain.corner_texture(ground, layers, cliff_tex, c2g, tp_w, tp_h, ix + 1, iy + 1)
			if bl == br and br == tl and tl == tr:
				continue
			var mask: MapTerrainLayer.CornerMask = terrain.corner_mask_for_type(bl, br, tl, tr, 1)
			transition_tiles += 1
			print(
				"tile(%d,%d) corners=%d/%d/%d/%d atlas=%d ped=%d"
				% [ix, iy, bl, br, tl, tr, mask.atlas, mask.pedagogical]
			)
	terrain.free()
	if transition_tiles < 1:
		push_error("expected dirt/grass transition tiles near cliff")
		quit(1)
		return
	print("cliff_ground_transition tiles=%d OK" % transition_tiles)
	quit(0)
