extends SceneTree

## 单位 _fm2 软混合：水元素等不应被 Alpha Scissor 硬切。
## godot --headless --path . -s res://tests/unit/selftest_unit_fm2_material.gd

const GLB := "res://assets/asset-converted/Units/Human/WaterElemental/WaterElemental.gltf"

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_path_heuristic()
	_test_water_elemental_fm2()
	if failed == 0:
		print("selftest_unit_fm2_material: PASS")
		quit(0)
	else:
		push_error("selftest_unit_fm2_material: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_path_heuristic() -> void:
	if not MapModelCache.glb_path_uses_unit_soft_blend("Units/Human/WaterElemental/WaterElemental.gltf"):
		_fail("WaterElemental 路径应启用 unit soft blend")
	if MapModelCache.glb_path_uses_unit_soft_blend("Units/Human/TownHall/TownHall.gltf"):
		_fail("TownHall 不应启用 unit soft blend")


func _test_water_elemental_fm2() -> void:
	var cache := MapModelCache.new()
	var root: Node3D = cache.instance_glb(GLB, true)
	if root == null:
		_fail("无法实例化 WaterElemental")
		return
	var fm2_found := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(si)
			if not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			var key := str(sm.resource_name).to_lower()
			if not key.contains("_fm2"):
				continue
			fm2_found = true
			var tex_key := ""
			if sm.albedo_texture != null:
				tex_key = str(sm.albedo_texture.resource_path).to_lower()
			var waterish := (
				tex_key.contains("water")
				or str(root.name).to_lower().contains("water")
				or GLB.to_lower().contains("water")
			)
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				_fail("WaterElemental _fm2 仍为 Alpha Scissor")
			if waterish:
				if sm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
					_fail(
						"水体 _fm2 期望 TRANSPARENCY_ALPHA，实际 transparency=%d"
						% sm.transparency
					)
				if sm.albedo_color.a > 0.7:
					_fail("水体 _fm2 albedo.a 应被压低，实际 %.2f" % sm.albedo_color.a)
			elif sm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				_fail(
					"单位 _fm2 期望 DEPTH_PRE_PASS，实际 transparency=%d"
					% sm.transparency
				)
			if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
				_fail("WaterElemental _fm2 期望双面 cull_disabled")
	if not fm2_found:
		_fail("未找到 WaterElemental _fm2 材质")
	root.free()
