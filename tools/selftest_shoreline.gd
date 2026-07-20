extends SceneTree
## 自测：斜坡不画水 + 泡沫每实例朝向不同。


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
	var n_s: int = (collected.get("straight", []) as Array).size()
	var n_o: int = (collected.get("outside", []) as Array).size()
	var n_i: int = (collected.get("inside", []) as Array).size()

	var sample: Array = collected.get("straight", []) as Array
	var dir_keys: Dictionary = {}
	for i in range(sample.size()):
		var e: Vector3 = sample[i].get("emit_dir", Vector3.ZERO)
		var key := "%d,%d" % [roundi(e.x), roundi(e.z)]
		dir_keys[key] = true
	print(
		"selftest Shore foam: S=%d OC=%d IC=%d uniqueDirs=%d ok"
		% [n_s, n_o, n_i, dir_keys.size()]
	)

	var root := Node3D.new()
	var placed: int = Foam.build_systems(root, collected)
	var group0 := root.get_child(0) as Node3D
	var unique_basis := 0
	if group0:
		var seen: Dictionary = {}
		for c in group0.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var z := mi.transform.basis.z
			var k := "%d,%d" % [roundi(z.x), roundi(z.z)]
			seen[k] = true
		unique_basis = seen.size()
	print(
		"selftest Shore foam systems points=%d groups=%d uniqueBasis=%d"
		% [placed, root.get_child_count(), unique_basis]
	)
	root.free()
	quit(0)
