extends RefCounted
const State := preload("res://addons/rts_map/logic/ramp/wc3_ramp_cell_state.gd")
const Regions := preload("res://addons/rts_map/logic/ramp/wc3_ramp_regions.gd")
const Seam := preload("res://addons/rts_map/logic/ramp/wc3_ramp_seam_plan.gd")
## One build-scoped plan consumed by terrain, cliff and ramp presentation.
## Full flagged unsupported cells use the existing textured ground triangulator.
## Incomplete flags retain their base surface; no saved data is silently rewritten.
static func build(hf: Wc3Heightfield, ramps: Wc3RampCollectResult) -> Dictionary:
	var seam := Seam.build(hf, ramps)
	var result := {"tiles": seam.tiles, "boost": seam.boost,
		"entrances": Wc3RampLogic.plan_entrance_tiles(hf, ramps),
		"dig": Wc3RampLogic.plan_dig_mask(hf, ramps), "unhandled": [], "counts": {},
		"routes": {"non_ramp": 0, "supported": 0, "invalid": 0, "fallback": 0},
		"cells": {}, "fallback_tiles": {}, "ground_tiles": []}
	var entrances := {}
	for tile in result.entrances:
		entrances[tile] = true
	var ground_tiles: Array[Vector2i] = []
	ground_tiles.assign(result.entrances)
	result.ground_tiles = ground_tiles
	var route_names := ["non_ramp", "supported", "invalid", "fallback"]
	for y in range(hf.height - 1):
		for x in range(hf.width - 1):
			var indices := [y*hf.width+x, y*hf.width+x+1, (y+1)*hf.width+x, (y+1)*hf.width+x+1]
			var levels: Array = []
			var flags: Array = []
			for i in indices:
				levels.append(int(hf.layer_heights[i]))
				flags.append(int(hf.flags_packed[i]))
			var kind := State.classify(levels, flags)
			result.counts[kind] = int(result.counts.get(kind, 0)) + 1
			var tile := Vector2i(x,y)
			var covered: bool = result.dig[y*(hf.width-1)+x] != 0
			var policy := State.resolve(levels, flags, entrances.has(tile), covered)
			var route_name: String = route_names[policy.route]
			result.routes[route_name] += 1
			if policy.route == State.Route.NON_RAMP:
				continue
			policy["state"] = State.canonical_key(levels,flags)
			policy["kind"] = kind
			policy["tile"] = tile
			result.cells[tile] = policy
			if policy.route == State.Route.FALLBACK:
				result.fallback_tiles[tile] = true
				result.tiles[tile] = true
				if not entrances.has(tile):
					result.ground_tiles.append(tile)
				result.unhandled.append(policy)
			elif policy.route == State.Route.INVALID:
				result.unhandled.append(policy)
	_resolve_regions(result, hf, ramps)
	return result


static func _resolve_regions(result: Dictionary, hf: Wc3Heightfield, ramps: Wc3RampCollectResult) -> void:
	var candidates := {}
	var seeds: Dictionary = result.fallback_tiles.duplicate()
	var ownership := {}
	for tile in result.cells:
		var route: int = result.cells[tile].route
		if route == State.Route.SUPPORTED or route == State.Route.FALLBACK:
			candidates[tile] = true
	# A resolved asset is admissible only for a single-level footprint with one owner.
	# Overlapping models or a wider layer range seed the entire connected region.
	for p in ramps.placements:
		if p == null or not p.has_glb:
			continue
		var footprint := Wc3RampCollect.placement_footprint_tiles(p)
		var low := 2147483647
		var high := -2147483648
		for tile in footprint:
			candidates[tile] = true
			ownership[tile] = int(ownership.get(tile,0)) + 1
			for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
				var point: Vector2i = tile+offset
				var level := int(hf.layer_heights[point.y*hf.width+point.x])
				low = mini(low,level)
				high = maxi(high,level)
			if ownership[tile] > 1:
				seeds[tile] = true
		if high-low != 1:
			for tile in footprint:
				seeds[tile] = true
	var regions := Regions.build(candidates,seeds)
	result["fallback_regions"] = regions
	var ground := {}
	for tile in result.ground_tiles:
		ground[tile] = true
	for region_index in range(regions.size()):
		for tile in regions[region_index].cells:
			result.fallback_tiles[tile] = true
			result.tiles[tile] = true
			result.dig[tile.y*(hf.width-1)+tile.x] = 0
			if not ground.has(tile):
				result.ground_tiles.append(tile)
				ground[tile] = true
			var policy: Dictionary = result.cells[tile]
			if policy.route != State.Route.FALLBACK:
				var names := ["non_ramp","supported","invalid","fallback"]
				result.routes[names[policy.route]] -= 1
				result.routes.fallback += 1
				policy["previous_reason"] = policy.reason
				policy.reason = "connected_region"
			policy.route = State.Route.FALLBACK
			policy.owner = "ground"
			policy["region"] = region_index
	var originals: Array[Wc3RampPlacement] = []
	for p in ramps.placements:
		if p == null or not p.has_glb:
			continue
		var replaced := false
		for tile in Wc3RampCollect.placement_footprint_tiles(p):
			replaced = replaced or result.fallback_tiles.has(tile)
		if not replaced:
			originals.append(p)
	result["original_placements"] = originals
	result.unhandled.clear()
	for policy in result.cells.values():
		if policy.route == State.Route.INVALID or policy.route == State.Route.FALLBACK:
			result.unhandled.append(policy)
