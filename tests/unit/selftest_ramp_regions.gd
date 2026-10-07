extends SceneTree
const Regions = preload("res://packages/map/logic/ramp/wc3_ramp_regions.gd")
const Plan = preload("res://packages/map/logic/ramp/wc3_ramp_surface_plan.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var candidates := {Vector2i(0,0): true, Vector2i(1,0): true, Vector2i(2,0): true, Vector2i(8,0): true}
	var regions := Regions.build(candidates, {Vector2i.ZERO: true})
	check(regions.size() == 1 and regions[0].cells.size() == 3, "Connected chain only")
	check(regions[0].boundary.size() == 8, "Three-cell strip has eight boundary edges")
	check(Regions.build(candidates, {}).is_empty(), "Unseeded components retain originals")
	candidates[Vector2i(3,1)] = true
	regions = Regions.build(candidates, {Vector2i(3,1): true})
	check(regions[0].cells.size() == 4, "Shared corner participates in region")
	var reverse := {}
	var keys := candidates.keys()
	keys.reverse()
	for key in keys:
		reverse[key] = true
	check(Regions.build(reverse, {Vector2i.ZERO: true})[0].cells == regions[0].cells, "Membership independent of traversal and seed")
	var doc = preload("res://documents/map_document.gd").new()
	check(doc.load_json("res://tests/fixtures/editor/ramp-user-222.wc3map.json") == OK, "Load 222")
	var hf: Wc3Heightfield = doc.heightfield
	var flags := hf.flags_packed.duplicate()
	var heights := hf.layer_heights.duplicate()
	var catalog := Wc3CliffCatalog.new()
	catalog.load_default()
	var ramps := Wc3RampLogic.collect_placements(hf, {}, catalog)
	var baseline := Plan.build(hf, ramps)
	check(baseline.original_placements.size() > 0, "222 retains original models")
	# Inject a duplicate resolved placement: overlapping ownership must replace
	# complete connected footprints, never leave half of either model mounted.
	ramps.placements.append(baseline.original_placements[0])
	var plan := Plan.build(hf, ramps)
	check(not plan.fallback_regions.is_empty(), "Overlapping models seed fallback")
	for p in ramps.placements:
		if not p.has_glb:
			continue
		var hits := 0
		var footprint := Wc3RampCollect.placement_footprint_tiles(p)
		for tile in footprint:
			if plan.fallback_tiles.has(tile):
				hits += 1
				check(plan.dig[tile.y*(hf.width-1)+tile.x] == 0 and tile in plan.ground_tiles, "Fallback restores ground ownership")
		check(hits == 0 or hits == footprint.size(), "No partially replaced model")
		check((p in plan.original_placements) == (hits == 0), "Mounted model ownership matches region")
	check(hf.flags_packed == flags and hf.layer_heights == heights, "Saved terrain is unchanged")
	var count := 0
	for value in plan.routes.values():
		count += value
	check(count == (hf.width-1)*(hf.height-1), "Every cell counted exactly once")
	print("selftest_ramp_regions: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
