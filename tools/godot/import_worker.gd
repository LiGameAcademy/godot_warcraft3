extends SceneTree

const SkeletonCompiler: GDScript = preload("import_skeleton_compiler.gd")
const MaterialCompiler: GDScript = preload("import_material_compiler.gd")
const VisibilityCompiler: GDScript = preload("import_geoset_visibility.gd")

## 无状态 Godot 编译后端的第一版。
##
## 用法：
##   godot --headless --path apps/game -s res://tools/godot/import_worker.gd -- \
##     --task D:/.../bake-task.json --result D:/.../worker-result.json
##
## worker 只负责 GLTF → PackedScene → 磁盘重载验证；来源解析、分类、
## profile 决策和任务调度由 JavaScript 导入器负责。

var _task_path: String = ""
var _result_path: String = ""


func _initialize() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = 0
	while i < args.size():
		var arg: String = str(args[i])
		if arg == "--task" and i + 1 < args.size():
			i += 1
			_task_path = str(args[i])
		elif arg.begins_with("--task="):
			_task_path = arg.substr("--task=".length())
		elif arg == "--result" and i + 1 < args.size():
			i += 1
			_result_path = str(args[i])
		elif arg.begins_with("--result="):
			_result_path = arg.substr("--result=".length())
		i += 1
	if _result_path.is_empty() and not _task_path.is_empty():
		_result_path = _task_path.get_basename() + ".worker-result.json"


func _run() -> void:
	var result: Dictionary = {
		"result_version": 1,
		"ok": false,
		"asset_id": "",
		"diagnostics": [],
	}
	if _task_path.is_empty():
		_fail(result, "missing_task", "缺少 --task 参数")
		_finish(result, 2)
		return
	var task_text: String = FileAccess.get_file_as_string(_task_path)
	if task_text.is_empty():
		_fail(result, "task_read_failed", "无法读取任务文件：%s" % _task_path)
		_finish(result, 2)
		return
	var parsed: Variant = JSON.parse_string(task_text)
	if not parsed is Dictionary:
		_fail(result, "task_json_invalid", "任务文件不是 JSON 对象")
		_finish(result, 2)
		return
	var task: Dictionary = parsed
	result["asset_id"] = str(task.get("asset_id", ""))
	var validation: Array[Dictionary] = _validate_task(task)
	if not validation.is_empty():
		result["diagnostics"] = validation
		_finish(result, 2)
		return

	var gltf_path: String = _as_resource_path(str(task["geometry_path"]))
	var output_path: String = _as_resource_path(str(task["output_scene"]))
	var ir_path: String = str(task["ir_path"])
	var ir: Variant = JSON.parse_string(FileAccess.get_file_as_string(_as_resource_path(ir_path)))
	if not ir is Dictionary or ir.get("schema_version") != 1 or ir.get("identity", {}).get("asset_id") != task["asset_id"]:
		_fail(result, "ir_invalid", "IR 缺失、版本不支持或资产身份不匹配")
		_finish(result, 2)
		return
	var doc: GLTFDocument = GLTFDocument.new()
	result["source_sha256"] = str(ir.get("source", {}).get("source_hash", ""))
	var state: GLTFState = GLTFState.new()
	var append_error: Error = doc.append_from_file(gltf_path, state)
	if append_error != OK:
		_fail(result, "gltf_load_failed", "GLTFDocument.append_from_file failed: %s" % append_error)
		_finish(result, 1)
		return
	var generated: Node = doc.generate_scene(state)
	if generated == null:
		_fail(result, "gltf_scene_failed", "GLTFDocument.generate_scene returned null")
		_finish(result, 1)
		return
	var root: Node3D
	if generated is Node3D:
		root = generated as Node3D
	else:
		root = Node3D.new()
		root.name = str(task["asset_id"]).get_file()
		root.add_child(generated)
	root.set_meta("wc3_import_profile", str(task["profile"]))
	root.set_meta("wc3_model_ir_path", ir_path)
	root.set_meta("wc3_import_worker_version", "1")
	var compiled: Dictionary = SkeletonCompiler.compile(root, ir)
	if not compiled.ok:
		result["diagnostics"] = compiled.diagnostics
		root.free()
		_finish(result, 1)
		return
	result["skeleton_compile"] = compiled
	var material_result: Dictionary = MaterialCompiler.compile(root, ir, ir_path.get_base_dir())
	result["material_compile"] = material_result
	compiled.diagnostics.append_array(material_result.diagnostics)
	var visibility_result: Dictionary = VisibilityCompiler.compile(root, ir)
	result["geoset_compile"] = visibility_result
	compiled.diagnostics.append_array(visibility_result.diagnostics)
	var before: Dictionary = _inventory(root)

	var packed: PackedScene = PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		_fail(result, "scene_pack_failed", "PackedScene.pack failed: %s" % pack_error)
		root.free()
		_finish(result, 1)
		return
	var parent: String = output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var save_error: Error = ResourceSaver.save(packed, output_path)
	root.free()
	if save_error != OK:
		_fail(result, "scene_save_failed", "ResourceSaver.save failed: %s" % save_error)
		_finish(result, 1)
		return

	var reloaded: Resource = ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if not reloaded is PackedScene:
		_fail(result, "scene_reload_failed", "无法重新加载生成的 PackedScene")
		_finish(result, 1)
		return
	var instance: Node = (reloaded as PackedScene).instantiate()
	# Keep overrides alive until their owning rendering instances finish teardown.
	var retained_materials: Array[Material] = []
	for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if material != null:
				retained_materials.append(material)
	var after: Dictionary = _inventory(instance)
	instance.free()
	if before != after:
		_fail(result, "scene_structure_changed", "保存重载后节点、网格或动画数量变化")
		_finish(result, 1)
		return
	result["ok"] = true
	result["scope"] = "geometry_skeleton_sockets"
	result["deliverable"] = false
	result["inventory"] = after
	result["output_scene"] = ProjectSettings.globalize_path(output_path)
	result["output_sha256"] = FileAccess.get_sha256(output_path)
	result["profile"] = str(task["profile"])
	result["diagnostics"] = compiled.diagnostics + [{"code": "partial_compile", "severity": "warning", "message": "材质和特效尚未完整编译；挂点仅支持非全局序列的离散显隐"}]
	_finish(result, 0)


func _validate_task(task: Dictionary) -> Array[Dictionary]:
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
	if value.begins_with("res://"):
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


func _finish(result: Dictionary, exit_code: int) -> void:
	if not _result_path.is_empty():
		var result_dir: String = _result_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(result_dir)
		var file: FileAccess = FileAccess.open(_result_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
		else:
			push_error("import_worker: 无法写入结果文件")
			exit_code = 2
	quit(exit_code)
