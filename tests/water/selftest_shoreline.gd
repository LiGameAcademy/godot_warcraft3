extends SceneTree
## 自测：斜坡下铺水 + WavesDepth + S/OC/IC 岸浪 MultiMesh。


const Foam := preload("res://scripts/map/presentation/water/wc3_shore_foam.gd")
const Builder := preload("res://scripts/map/presentation/water/wc3_shoreline_builder.gd")
const Params := preload("res://scripts/map/presentation/water/wc3_water_params.gd")
const WaterMesh := preload("res://scripts/map/presentation/water/wc3_water_mesh.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("selftest: missing %s" % path)
		quit(1)
		return
	var hf: Variant = JSON.parse_string(f.get_as_text())
	if typeof(hf) != TYPE_DICTIONARY:
		push_error("selftest: bad JSON")
		quit(1)
		return

	var params = Params.load_for_tileset("I")
	var built: Dictionary = WaterMesh.build(hf as Dictionary, params, 0.0)
	var tiles := int(built.get("cell_count", 0))
	var under_ramp := int(built.get("under_ramp", 0))
	print("selftest Water: tiles=%d underRamp=%d" % [tiles, under_ramp])
	if tiles <= 0:
		push_error("selftest: expected water tiles")
		quit(1)
		return
	if under_ramp <= 0:
		push_error("selftest: expected water under ramp tiles (HiveWE parity)")
		quit(1)
		return

	var collected: Dictionary = Builder.collect_foam_placements(
		hf as Dictionary, params, 0.0, true, true, {}, 0.10, 0.38, 0.08
	)
	var list: Array = collected.get("placements", []) as Array
	var n_s := int(collected.get("count_s", 0))
	var n_oc := int(collected.get("count_oc", 0))
	var n_ic := int(collected.get("count_ic", 0))
	var n_l1 := int(collected.get("count_cliff_l1", 0))
	var n_l2 := int(collected.get("count_cliff_l2", 0))
	print(
		"selftest Shore: S=%d OC=%d IC=%d contour=%d cliffL1=%d cliffL2+=%d shallowSkip=%d"
		% [
			n_s,
			n_oc,
			n_ic,
			int(collected.get("count_contour", 0)),
			n_l1,
			n_l2,
			int(collected.get("skipped_shallow", 0)),
		]
	)
	if n_s <= 0 or n_oc <= 0:
		push_error("selftest: expected S and OC placements")
		quit(1)
		return
	if int(collected.get("count_contour", 0)) <= 0:
		push_error("selftest: expected WavesDepth contour placements (rapids)")
		quit(1)
		return
	if list.size() != n_s + n_oc + n_ic:
		push_error("selftest: kind counts mismatch list size")
		quit(1)
		return

	var root := Node3D.new()
	var n: int = Foam.build_systems(root, list)
	print("selftest Shore instances=%d children=%d" % [n, root.get_child_count()])
	if n <= 0 or root.get_child_count() < 2:
		push_error("selftest: foam build failed (need ≥2 MultiMesh kinds)")
		root.free()
		quit(1)
		return
	root.free()
	quit(0)
