extends SceneTree
## 自测：斜坡跳过 + 简化岸浪 MultiMesh。


const Foam := preload("res://scripts/map/wc3_shore_foam.gd")
const Builder := preload("res://scripts/map/wc3_shoreline_builder.gd")
const Params := preload("res://scripts/map/wc3_water_params.gd")
const WaterMesh := preload("res://scripts/map/wc3_water_mesh.gd")


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
	print(
		"selftest Water: tiles=%d skipRamp=%d"
		% [int(built.get("cell_count", 0)), int(built.get("skipped_ramp", 0))]
	)

	var collected: Dictionary = Builder.collect_foam_placements(
		hf as Dictionary, params, 0.0, true, true
	)
	var list: Array = collected.get("placements", []) as Array
	var cliff_n := 0
	for rec in list:
		if bool(rec.get("cliff", false)):
			cliff_n += 1
	print("selftest Shore: emitters=%d cliff=%d ok" % [list.size(), cliff_n])

	var root := Node3D.new()
	var n: int = Foam.build_systems(root, list)
	print("selftest Shore instances=%d children=%d" % [n, root.get_child_count()])
	if n <= 0:
		push_error("selftest: foam build failed")
		root.free()
		quit(1)
		return
	root.free()
	quit(0)
