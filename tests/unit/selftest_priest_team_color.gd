extends SceneTree

## 牧师：G0=_fm1 MASK@0.75；G1=队色 underlay（alpha mix）。
## godot --headless --path . -s res://tests/unit/selftest_priest_team_color.gd

const PRIEST := "res://assets/asset-converted/Units/Human/Priest/Priest.gltf"
const TOWN := "res://assets/asset-converted/Buildings/Human/TownHall/TownHall.gltf"

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_priest_fm1_and_underlay()
	_test_underlay("TownHall", TOWN)
	if failed == 0:
		print("selftest_priest_team_color: PASS")
		quit(0)
	else:
		push_error("selftest_priest_team_color: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_priest_fm1_and_underlay() -> void:
	var cache := MapModelCache.new()
	var unit_soft := MapModelCache.glb_path_uses_unit_soft_blend(
		PRIEST.trim_prefix("res://assets/asset-converted/")
	)
	var root := cache.instance_glb(PRIEST, unit_soft)
	if root == null:
		_fail("Priest: instance_glb null")
		return
	cache.apply_team_color(root, 0, false)
	var found_underlay := false
	var found_fm1_mask := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat is ShaderMaterial:
				var shm := mat as ShaderMaterial
				if shm.shader != null and str(shm.shader.resource_path).to_lower().contains(
					"wc3_team_color_underlay"
				):
					found_underlay = true
			elif mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var key := (str(sm.resource_name) + " " + str(sm.get_name())).to_lower()
				if key.contains("_fm1"):
					if (
						sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						and absf(sm.alpha_scissor_threshold - 0.75) < 0.001
					):
						found_fm1_mask = true
					else:
						_fail(
							(
								"Priest _fm1 期望 MASK@0.75，实际 transparency=%d cutoff=%.3f"
								% [sm.transparency, sm.alpha_scissor_threshold]
							)
						)
	if not found_underlay:
		_fail("Priest: expected team-color underlay shader")
	else:
		print("Priest: underlay alpha-mix OK")
	if not found_fm1_mask:
		_fail("Priest: expected _fm1 MASK@0.75 body material")
	else:
		print("Priest: _fm1 MASK@0.75 OK")
	root.free()


func _test_underlay(label: String, glb: String) -> void:
	var cache := MapModelCache.new()
	var unit_soft := MapModelCache.glb_path_uses_unit_soft_blend(
		glb.trim_prefix("res://assets/asset-converted/")
	)
	var root := cache.instance_glb(glb, unit_soft)
	if root == null:
		_fail("%s: instance_glb null" % label)
		return
	cache.apply_team_color(root, 0, false)
	var found := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if not (mat is ShaderMaterial):
				continue
			var shm := mat as ShaderMaterial
			if shm.shader == null:
				continue
			if not str(shm.shader.resource_path).to_lower().contains("wc3_team_color_underlay"):
				continue
			found = true
	if not found:
		_fail("%s: expected team-color underlay shader" % label)
	else:
		print("%s: underlay alpha-mix OK" % label)
	root.free()
