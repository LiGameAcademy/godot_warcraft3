extends SceneTree
## D-4 selftest: runtime apply_team_color 8 队染色。
## 验证 map_model_cache.apply_team_color 把 _rep1 material 替换为 ShaderMaterial
## + teamcolor 切色 + glow 隐藏。
## 5/5：
##   1. Footman .scn 加载后默认无 ShaderMaterial（中立红待 runtime 切）
##   2. apply_team_color(0) 后 0 号 teamcolor mesh 的 material 变 ShaderMaterial
##   3. apply_team_color(5) 切到 5 号，颜色 uniform 变（team_color_fallback 不同）
##   4. 8 队（0-7）全跑无 crash + 切色有效
##   5. hide_team_glow=true 兼容路径不 crash
##
## godot --headless --path . -s res://tests/unit/selftest_d_team_color.gd

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_footman_load_default()
	_test_apply_team_color_0()
	_test_apply_team_color_5_changes_color()
	_test_apply_team_color_all_8()
	_test_hide_team_glow()

	if passed == total:
		print("selftest_d_team_color: PASS")
		quit(0)
	else:
		push_error("selftest_d_team_color: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: Footman .scn 加载默认无 ShaderMaterial（中立红待 runtime 切）
func _test_footman_load_default() -> void:
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var proto: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	if proto == null:
		push_error("test_1 FAIL: Footman load null")
		return
	# 数 _rep1 StandardMaterial3D 数量
	var rep1_count := _count_rep1_materials(proto)
	if rep1_count < 1:
		push_error("test_1 FAIL: expected >= 1 _rep1 material, got %d" % rep1_count)
		return
	# 默认无 ShaderMaterial（runtime 才切）
	var shader_count := _count_shader_materials(proto)
	if shader_count != 0:
		push_error("test_1 FAIL: default should have 0 ShaderMaterial, got %d" % shader_count)
		return
	print("  Footman default: %d _rep1 StandardMaterial, 0 ShaderMaterial (OK, runtime 切)" % rep1_count)
	passed += 1


# Test 2: apply_team_color(0) 后变 ShaderMaterial
func _test_apply_team_color_0() -> void:
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var proto: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	if proto == null:
		return
	var cache := MapModelCache.new()
	cache.apply_team_color(proto, 0, true)
	# 现在应该有 ShaderMaterial（wc3_team_color_underlay）
	var shader_count := _count_shader_materials(proto)
	if shader_count < 1:
		push_error("test_2 FAIL: apply_team_color(0) should create ShaderMaterial, got %d" % shader_count)
		return
	# 验证 ShaderMaterial 用了 wc3_team_color_underlay.gdshader
	var sh: Shader = load("res://assets/shaders/wc3_team_color_underlay.gdshader")
	var uses_correct := false
	for sm in _iter_shader_materials(proto):
		if sm.shader == sh:
			uses_correct = true
			break
	if not uses_correct:
		push_error("test_2 FAIL: ShaderMaterial not using wc3_team_color_underlay")
		return
	print("  apply_team_color(0): %d ShaderMaterial, all using wc3_team_color_underlay" % shader_count)
	passed += 1


# Test 3: apply_team_color(5) 切到 5 号，颜色 uniform 变
func _test_apply_team_color_5_changes_color() -> void:
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var proto_a: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	var proto_b: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	if proto_a == null or proto_b == null:
		return
	var cache := MapModelCache.new()
	cache.apply_team_color(proto_a, 0, true)
	cache.apply_team_color(proto_b, 5, true)
	# 两个 proto 的 team_color_fallback 应该不同
	var color_a: Color = _get_team_color_uniform(proto_a)
	var color_b: Color = _get_team_color_uniform(proto_b)
	if color_a == color_b:
		push_error("test_3 FAIL: apply_team_color(0) vs (5) gave same color %s" % str(color_a))
		return
	# 0 号（红）= (1, 0, 0, 1) 或类似
	if color_a.r < 0.5:
		push_error("test_3 FAIL: color 0 should be red-ish, got %s" % str(color_a))
		return
	print("  apply_team_color(0)=%s, (5)=%s" % [str(color_a), str(color_b)])
	passed += 1


# Test 4: 8 队（0-7）全跑无 crash
func _test_apply_team_color_all_8() -> void:
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var cache := MapModelCache.new()
	for i in range(8):
		var proto: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
		if proto == null:
			push_error("test_4 FAIL: load null at i=%d" % i)
			return
		cache.apply_team_color(proto, i, true)
		# 至少有 1 个 ShaderMaterial
		var shader_count := _count_shader_materials(proto)
		if shader_count < 1:
			push_error("test_4 FAIL: i=%d shader_count=%d" % [i, shader_count])
			return
	print("  8 队（0-7）apply_team_color 全跑 OK, 每次产生 ShaderMaterial")
	passed += 1


# Test 5: hide_team_glow=true 兼容路径不 crash（旧误识别大面片）
func _test_hide_team_glow() -> void:
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var proto: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	if proto == null:
		return
	var add_count_before := _count_additive_meshes(proto)
	var cache := MapModelCache.new()
	cache.apply_team_color(proto, 0, true)
	var add_count_after := _count_additive_meshes(proto)
	if add_count_after > add_count_before:
		push_error("test_5 FAIL: additive count increased after hide_team_glow")
		return
	print("  hide_team_glow compat: %d → %d Additive mesh (no crash)" % [add_count_before, add_count_after])
	passed += 1


# 辅助：数 _rep1 StandardMaterial3D（key 含 "_rep1"）
func _count_rep1_materials(root: Node) -> int:
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null:
				continue
			var key := (str(mat.resource_name) + " " + str(mat.get_name())).to_lower()
			if key.contains("_rep1"):
				count += 1
	return count


# 辅助：数 ShaderMaterial 数量
func _count_shader_materials(root: Node) -> int:
	var count := 0
	for sm in _iter_shader_materials(root):
		count += 1
	return count


func _iter_shader_materials(root: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.get_surface_override_material_count()):
			var m = mi.get_surface_override_material(si)
			if m is ShaderMaterial:
				out.append(m)
	return out


# 辅助：拿第一个 ShaderMaterial 的 team_color_fallback uniform
func _get_team_color_uniform(root: Node) -> Color:
	for sm in _iter_shader_materials(root):
		var v = sm.get_shader_parameter("team_color_fallback")
		if v != null and v is Color:
			return v
	return Color(0, 0, 0, 0)


# 辅助：数 Additive blend mesh（可能为 0，Footman 不一定有）
func _count_additive_meshes(root: Node) -> int:
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				count += 1
				break
	return count
