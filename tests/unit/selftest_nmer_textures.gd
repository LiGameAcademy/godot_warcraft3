extends SceneTree
## godot --headless --path . -s res://tests/unit/selftest_nmer_textures.gd
## 回归：nmer（雇佣兵营地）.scn 不得缺贴图（曾出现 8x8/null 坏烘焙）。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logical := "Buildings/Other/Mercenary/Mercenary.gltf"
	var scn_path := RuntimeAssets.resolve_model_scene(logical)
	print("scn='%s'" % scn_path)
	var packed := RuntimeAssets.load_packed_scene(scn_path)
	if packed == null:
		print("FAIL load_packed_scene")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	var cache := MapModelCache.new()
	cache.apply_team_color(model, 0, true)
	var bad := 0
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(si)
			var w := _tex_width(mat)
			print("mesh=%s w=%d" % [mi.name, w])
			# 主贴图至少应大于占位（坏 scn 曾是 null 或 8x8）
			if w < 32:
				bad += 1
	print("RESULT bad=%d" % bad)
	quit(0 if bad == 0 else 1)


func _tex_width(mat: Material) -> int:
	if mat is StandardMaterial3D:
		var t: Texture2D = (mat as StandardMaterial3D).albedo_texture
		return t.get_width() if t != null else 0
	if mat is ShaderMaterial:
		var sh := mat as ShaderMaterial
		var d: Variant = sh.get_shader_parameter("diffuse_tex")
		if d is Texture2D:
			return (d as Texture2D).get_width()
	return 0
