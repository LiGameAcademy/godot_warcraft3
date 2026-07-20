class_name HeightfieldMeshBuilder
extends RefCounted
## heightfield 元数据与格点采样（几何由 Terrain / Water 各自构建）。


static func sample_vert(ix: int, iy: int, h: float, center: Vector2, tile_size: float) -> Vector3:
	var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)


static func read_heightfield_meta(hf: Dictionary) -> Dictionary:
	var co: Dictionary = hf.get("centerOffset", {})
	return {
		"width": int(hf.get("tilepointWidth", 0)),
		"height": int(hf.get("tilepointHeight", 0)),
		"tile_size": float(hf.get("tileSize", Wc3Coords.TILE_SIZE)),
		"center": Vector2(float(co.get("x", 0.0)), float(co.get("y", 0.0))),
		"heights": hf.get("heights", []) as Array,
		"water_heights": hf.get("waterHeights", []) as Array,
		"ground_textures": hf.get("groundTextures", []) as Array,
		"ground_variations": hf.get("groundVariations", []) as Array,
		"cliff_textures": hf.get("cliffTextures", []) as Array,
		"cliff_variations": hf.get("cliffVariations", []) as Array,
		"layer_heights": hf.get("layerHeights", []) as Array,
		"flags": hf.get("flagsPacked", []) as Array,
		"ground_tilesets": hf.get("groundTilesets", []) as Array,
		"cliff_tilesets": hf.get("cliffTilesets", []) as Array,
		"main_tileset": str(hf.get("mainTileset", "")),
	}
