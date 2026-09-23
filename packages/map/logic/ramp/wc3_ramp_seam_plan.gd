extends RefCounted
## Project extension for incomplete ramp brush states: one boundary contract for
## ground, straight cliffs and CliffTrans, without modifying the saved heightfield.
static func build(hf: Wc3Heightfield, ramps: Wc3RampCollectResult) -> Dictionary:
	var boost := Wc3RampLogic.plan_entrance_height_boost(hf, ramps)
	var tiles := {}
	for tile in Wc3RampLogic.plan_entrance_tiles(hf, ramps):
		tiles[tile] = true
	for p in ramps.placements:
		if p == null or not p.has_glb:
			continue
		for tile in Wc3RampCollect.placement_footprint_tiles(p):
			tiles[tile] = true
		var middle: Array[Vector2i] = []
		if p.axis == Wc3RampLogic.AXIS_V:
			middle = [Vector2i(p.ix, p.iy + 1), Vector2i(p.ix + 1, p.iy + 1)]
		else:
			middle = [Vector2i(p.ix + 1, p.iy), Vector2i(p.ix + 1, p.iy + 1)]
		for point in middle:
			var index := point.y * hf.width + point.x
			if (int(hf.flags_packed[index]) & Wc3Coords.FLAG_RAMP) != 0 and int(hf.layer_heights[index]) == p.base_layer:
				boost[index] = 1
	return {"tiles": tiles, "boost": boost}
