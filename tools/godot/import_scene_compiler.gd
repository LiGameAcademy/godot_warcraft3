extends RefCounted

## 可在导出游戏中调用的同步编译核心；不退出进程或写命令行结果。
const COMPILER_VERSION: String = "2"
const SkeletonCompiler: GDScript = preload("import_skeleton_compiler.gd")
const MaterialCompiler: GDScript = preload("import_material_compiler.gd")
const VisibilityCompiler: GDScript = preload("import_geoset_visibility.gd")
const EffectCompiler: GDScript = preload("import_effect_compiler.gd")
const AnimationMetadata: GDScript = preload("import_animation_metadata.gd")

var _task_path: String = ""


func compile_task(task_path: String) -> Dictionary:
	_task_path = task_path
	var result: Dictionary = {
		"result_version": 1,
		"compiler_version": COMPILER_VERSION,
		"ok": false,
		"asset_id": "",
		"diagnostics": [],
	}
	if _task_path.is_empty():
		_fail(result, "missing_task", "缺少 --task 参数")
		return _finish(result, 2)
	var task_text: String = FileAccess.get_file_as_string(_task_path)
	if task_text.is_empty():
		_fail(result, "task_read_failed", "无法读取任务文件：%s" % _task_path)
		return _finish(result, 2)
	var parsed: Variant = JSON.parse_string(task_text)
	if not parsed is Dictionary:
		_fail(result, "task_json_invalid", "任务文件不是 JSON 对象")
		return _finish(result, 2)
	var task: Dictionary = parsed
	result["asset_id"] = str(task.get("asset_id", ""))
	var validation: Array[Dictionary] = validate_task(task)
	if not validation.is_empty():
		result["diagnostics"] = validation
		return _finish(result, 2)

	var gltf_path: String = _as_resource_path(str(task["geometry_path"]))
	var output_path: String = _as_resource_path(str(task["output_scene"]))
	var ir_path: String = _as_resource_path(str(task["ir_path"]))
	var ir: Variant = JSON.parse_string(FileAccess.get_file_as_string(_as_resource_path(ir_path)))
	if (
		not ir is Dictionary
		or ir.get("schema_version") != 1
		or not ir.get("identity") is Dictionary
		or ir.identity.get("asset_id") != task["asset_id"]
		or not ir.get("source", {}) is Dictionary
	):
		_fail(result, "ir_invalid", "IR 缺失、版本不支持或资产身份不匹配")
		return _finish(result, 2)
	var doc: GLTFDocument = GLTFDocument.new()
	result["source_sha256"] = str(ir.get("source", {}).get("source_hash", ""))
	var state: GLTFState = GLTFState.new()
	var append_error: Error = doc.append_from_file(gltf_path, state)
	if append_error != OK:
		_fail(result, "gltf_load_failed", "GLTFDocument.append_from_file failed: %s" % append_error)
		return _finish(result, 1)
	var generated: Node = doc.generate_scene(state)
	if generated == null:
		_fail(result, "gltf_scene_failed", "GLTFDocument.generate_scene returned null")
		return _finish(result, 1)
	var root: Node3D
	if generated is Node3D:
		root = generated as Node3D
	else:
		root = Node3D.new()
		root.name = str(task["asset_id"]).get_file()
		root.add_child(generated)
	root.set_meta("wc3_import_profile", str(task["profile"]))
	root.set_meta("wc3_model_ir_path", ir_path)
	root.set_meta("wc3_import_worker_version", COMPILER_VERSION)
	var compiled: Dictionary = SkeletonCompiler.compile(root, ir)
	if not compiled.ok:
		result["diagnostics"] = compiled.diagnostics
		root.free()
		return _finish(result, 1)
	result["skeleton_compile"] = compiled
	compiled.diagnostics.append_array(ir.get("diagnostics", []))
	var sequence_metadata: Dictionary = AnimationMetadata.compile(root, ir)
	result["animation_metadata"] = sequence_metadata
	compiled.diagnostics.append_array(sequence_metadata.diagnostics)
	var material_result: Dictionary = MaterialCompiler.compile(root, ir, ir_path.get_base_dir())
	result["material_compile"] = material_result
	compiled.diagnostics.append_array(material_result.diagnostics)
	var visibility_result: Dictionary = VisibilityCompiler.compile(root, ir)
	result["geoset_compile"] = visibility_result
	compiled.diagnostics.append_array(visibility_result.diagnostics)
	var effects: Dictionary = EffectCompiler.compile(root, ir, ir_path.get_base_dir())
	result["effect_compile"] = effects
	compiled.diagnostics.append_array(effects.diagnostics)
	for diagnostic: Dictionary in compiled.diagnostics:
		if str(diagnostic.get("severity", "")) == "error":
			result["diagnostics"] = compiled.diagnostics
			root.free()
			return _finish(result, 1)
	var before: Dictionary = _inventory(root)

	var packed: PackedScene = PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		_fail(result, "scene_pack_failed", "PackedScene.pack failed: %s" % pack_error)
		root.free()
		return _finish(result, 1)
	var parent: String = output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var save_error: Error = ResourceSaver.save(packed, output_path)
	root.free()
	if save_error != OK:
		_fail(result, "scene_save_failed", "ResourceSaver.save failed: %s" % save_error)
		return _finish(result, 1)

	var reloaded: Resource = ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not reloaded is PackedScene:
		_fail(result, "scene_reload_failed", "无法重新加载生成的 PackedScene")
		return _finish(result, 1)
	var instance: Node = (reloaded as PackedScene).instantiate()
	# Keep overrides alive until their owning rendering instances finish teardown.
	var retained_materials: Array[Material] = []
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		if mesh.material_override != null:
			retained_materials.append(mesh.material_override)
		if mesh.mesh == null:
			continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if material != null:
				retained_materials.append(material)
	var after: Dictionary = _inventory(instance)
	instance.free()
	if before != after:
		_fail(result, "scene_structure_changed", "保存重载后节点、网格或动画数量变化")
		return _finish(result, 1)
	result["ok"] = true
	result["scope"] = "geometry_skeleton_sockets"
	result["deliverable"] = false
	result["inventory"] = after
	result["output_scene"] = ProjectSettings.globalize_path(output_path)
	result["output_sha256"] = FileAccess.get_sha256(output_path)
	result["profile"] = str(task["profile"])
	result["diagnostics"] = compiled.diagnostics + [{"code": "partial_compile", "severity": "warning", "message": "材质和特效尚未完整编译；挂点仅支持非全局序列的离散显隐"}]
	return _finish(result, 0)


static func validate_task(task: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if int(task.get("task_version", 0)) != 1:
		errors.append({"code": "task_version", "severity": "error", "message": "不支持的 task_version"})
	for key: String in ["asset_id", "ir_path", "geometry_path", "output_scene"]:
		if str(task.get(key, "")).strip_edges().is_empty():
			errors.append({"code": "missing_%s" % key, "severity": "error", "message": "缺少字段 %s" % key})
	var profile: String = str(task.get("profile", ""))
	if profile != "fidelity" and profile != "enhanced":
		errors.append({"code": "profile", "severity": "error", "message": "profile 必须是 fidelity 或 enhanced"})
	return errors


func _as_resource_path(value: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return value
	if value.is_absolute_path():
		return ProjectSettings.localize_path(value)
	return _task_path.get_base_dir().path_join(value).simplify_path()


func _inventory(scene: Node) -> Dictionary:
	var counts: Dictionary = {"nodes": 0, "meshes": 0, "surfaces": 0, "bones": 0, "animations": 0}
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		counts.nodes += 1
		if node is MeshInstance3D and node.mesh != null:
			counts.meshes += 1
			counts.surfaces += node.mesh.get_surface_count()
		if node is Skeleton3D:
			counts.bones += node.get_bone_count()
		if node is AnimationPlayer:
			counts.animations += node.get_animation_list().size()
		for child: Node in node.get_children():
			pending.append(child)
	return counts


func _fail(result: Dictionary, code: String, message: String) -> void:
	result["diagnostics"] = [{"code": code, "severity": "error", "message": message}]
	push_error("import_worker: %s" % message)


func _finish(result: Dictionary, exit_code: int) -> Dictionary:
	return {"result": result, "exit_code": exit_code}
