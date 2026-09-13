extends Node
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15:
			push_error(label)
# Independent oracle: rotate a source point in WC3 XY, then change coordinates.
func expected(point: Vector3, angle: float) -> Vector3:
	var x := cos(angle) * point.x - sin(angle) * point.y
	var y := sin(angle) * point.x + cos(angle) * point.y
	return Vector3(x, point.z, -y) * 0.01
func verify_basis(basis: Basis, angle: float, scale_data: Dictionary, label: String) -> void:
	for p in [Vector3(71, 23, 11), Vector3(-17, 83, 41)]:
		var scaled: Vector3 = p * Vector3(scale_data.get("x", 1.0), scale_data.get("y", 1.0), scale_data.get("z", 1.0))
		var actual: Vector3 = basis * Vector3(p.x, p.z, -p.y)
		check(actual.distance_to(expected(scaled, angle)) < 0.0001, label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var catalog := Wc3IdCatalog.new()
	catalog.load_default()
	var cache := MapModelCache.new()
	var doodads := MapDoodadLayer.new()
	doodads.setup(catalog, cache)
	add_child(doodads)
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map-parsed/losttemple/doodads.json")).doodads
	var sampled := {}
	var old_wrong := 0
	for d in entries:
		var angle := float(d.angle)
		verify_basis(doodads._doodad_transform(d).basis, angle, d.scale, "LT batch " + str(d.creationNumber))
		if absf(angle_difference(PI - angle, angle)) > 0.001:
			old_wrong += 1
		if sampled.has(d.id):
			continue
		sampled[d.id] = true
		doodads.add_one(d, null)
		var model := doodads.get_child(doodads.get_child_count() - 1) as Node3D
		# Cached scene roots are unit scale; converted model scale lives below them.
		var imported: Vector3 = model.get_meta("doodad_base_scale")
		verify_basis(model.basis.scaled(Vector3.ONE * (0.01 / imported.x)), angle, d.scale, "LT single " + str(d.id))
	# Include non-cardinal angles and nonuniform scaling independent of map samples.
	for angle in [0.0, PI / 2, PI, 3 * PI / 2, 0.37, -0.61]:
		var d := {"angle": angle, "scale": {"x": 1.5, "y": 0.75, "z": 2.0}}
		var model := Node3D.new()
		model.scale = Vector3.ONE * 0.01
		doodads._apply_doodad_xform(model, d, true)
		verify_basis(model.basis, angle, d.scale, "single arbitrary angle")
		verify_basis(doodads._doodad_transform(d).basis, angle, d.scale, "batch arbitrary angle")
		model.free()
	var units := MapUnitLayer.new()
	units.setup(catalog, cache)
	add_child(units)
	var unit_entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map-parsed/losttemple/units.json")).units
	for u in unit_entries:
		var unit := units.add_one(u, null)
		check(not unit.get_meta("is_placeholder", true), "LT original unit loaded " + str(u.typeId))
		verify_basis(unit.basis.scaled(Vector3.ONE * 0.01), float(u.angle), {}, "LT unit " + str(u.creationNumber))
		var model := (unit as Unit).model_node()
		check(model.basis.x.normalized().distance_to(Vector3.RIGHT) < 0.0001, "LT model root has no extra yaw " + str(u.typeId))
	await get_tree().process_frame
	await get_tree().process_frame
	for unit in units.get_children():
		var u: Dictionary = unit.get_meta("unit_data", {})
		verify_basis(unit.basis.scaled(Vector3.ONE * 0.01), float(u.angle), {}, "unit heading survives animation startup")
	print("selftest_lt_facing: %s checks=%d failures=%d units=%d doodads=%d sampled_doodad_types=%d old_formula_mismatches=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, unit_entries.size(), entries.size(), sampled.size(), old_wrong])
	get_tree().quit(0 if failures == 0 else 1)
