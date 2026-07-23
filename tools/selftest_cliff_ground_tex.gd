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

	var tp_w: int = int(doc.hf["tilepointWidth"])
	var ground: Array = doc.hf["groundTextures"]
	var layers: Array = doc.hf["layerHeights"]
	print("groundTilesets=", doc.hf["groundTilesets"])
	print("=== groundTextures (0=Ldrt 1=Lgrs) ===")
	for y in range(cy - 3, cy + 4):
		var row := ""
		for x in range(cx - 3, cx + 4):
			row += "%d " % int(ground[y * tp_w + x])
		print(row)
	print("=== boundary tile masks (grass=1) ===")
	for iy in range(cy - 3, cy + 3):
		for ix in range(cx - 3, cx + 3):
			if Wc3CliffTiles.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var bl := int(ground[iy * tp_w + ix])
			var br := int(ground[iy * tp_w + ix + 1])
			var tl := int(ground[(iy + 1) * tp_w + ix])
			var tr := int(ground[(iy + 1) * tp_w + ix + 1])
			if bl == br and br == tl and tl == tr:
				continue
			var mask: Dictionary = Wc3TerrainAutotile.corner_mask_for_type(bl, br, tl, tr, 1)
			print(
				"tile(%d,%d) corners=%d/%d/%d/%d atlas=%d ped=%d"
				% [ix, iy, bl, br, tl, tr, int(mask["atlas"]), int(mask["pedagogical"])]
			)
	print("=== boundary tile masks AFTER corner_texture (grass=1) ===")
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var cts: Array = doc.cliff_tilesets()
	var gs: Array = doc.ground_tilesets()
	var cliff_to_ground := PackedInt32Array()
	# mirror autotile helper
	cliff_to_ground.resize(cts.size())
	cliff_to_ground.fill(-1)
	for i in range(cts.size()):
		var gid := tiles.ground_tile_for_cliff_id(str(cts[i]))
		for gi in range(gs.size()):
			if str(gs[gi]) == gid:
				cliff_to_ground[i] = gi
				break
	print("cliff_to_ground=", cliff_to_ground)
	var cliff_tex: Array = doc.hf["cliffTextures"]
	var tp_h: int = int(doc.hf["tilepointHeight"])
	for iy in range(cy - 3, cy + 3):
		for ix in range(cx - 3, cx + 3):
			if Wc3CliffTiles.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var bl2 := Wc3TerrainAutotile._corner_texture(
				ground, layers, cliff_tex, cliff_to_ground, tp_w, tp_h, ix, iy
			)
			var br2 := Wc3TerrainAutotile._corner_texture(
				ground, layers, cliff_tex, cliff_to_ground, tp_w, tp_h, ix + 1, iy
			)
			var tl2 := Wc3TerrainAutotile._corner_texture(
				ground, layers, cliff_tex, cliff_to_ground, tp_w, tp_h, ix, iy + 1
			)
			var tr2 := Wc3TerrainAutotile._corner_texture(
				ground, layers, cliff_tex, cliff_to_ground, tp_w, tp_h, ix + 1, iy + 1
			)
			if bl2 == br2 and br2 == tl2 and tl2 == tr2:
				continue
			var mask2: Dictionary = Wc3TerrainAutotile.corner_mask_for_type(bl2, br2, tl2, tr2, 1)
			print(
				"tile(%d,%d) ct=%d/%d/%d/%d atlas=%d"
				% [ix, iy, bl2, br2, tl2, tr2, int(mask2["atlas"])]
			)
	quit(0)
