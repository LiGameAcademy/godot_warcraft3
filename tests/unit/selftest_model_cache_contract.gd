extends SceneTree
## Public loading/cache behavior trace; timings are logged separately, including the first call.
var _checks: int = 0
var _failures: int = 0
var _trace: Array = []
var _root_dir: String = "user://model-cache-contract"

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	_root_dir += "-" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root_dir))
	var compiled: Dictionary[String, String] = {}
	for name: String in ["sync", "preload_a", "preload_b", "preview", "unit_fm1", "unit_fm2", "glow"]:
		var prototype: Node3D = _fixture(name)
		var packed: PackedScene = PackedScene.new()
		_check(packed.pack(prototype) == OK, "pack fixture " + name)
		var saved: String = _root_dir.path_join(name + ".scn")
		_check(ResourceSaver.save(packed, saved) == OK, "save fixture " + name)
		compiled["contract/" + name + ".scn"] = ProjectSettings.globalize_path(saved)
		prototype.free()
	var content: String = ProjectSettings.globalize_path(_root_dir.path_join("assets"))
	DirAccess.make_dir_recursive_absolute(content)
	_check(ContentPaths.install_compiled_scenes(compiled, content) == OK, "mount fixture publications")
	var cache: MapModelCache = MapModelCache.new()
	var path: String = _path("sync")
	_trace.append(["empty", cache.has_cached(""), cache.glb_has_mesh(""), cache.glb_has_animation(""), cache.mesh_parts_from_glb("")])
	var started: int = Time.get_ticks_usec()
	var a: Node3D = cache.instance_glb(path)
	_check(a != null, "synchronous scene instance")
	_trace.append(["sync", _describe(a), _stats(cache), cache.glb_has_animation(path), cache.has_model_scene(path)])
	print("MODEL_CACHE_CONTRACT_SAMPLE phase=sync_first elapsed_ms=", float(Time.get_ticks_usec() - started) / 1000.0)
	var b: Node3D = cache.instance_glb(path)
	var before_b: Array = _describe(b)
	var parts: Array = cache.mesh_parts_from_glb(path)
	_check(parts.size() == 1, "Stand hides the stump before static extraction")
	_check(is_same(parts, cache.mesh_parts_from_glb(path)), "static cache hit returns the same array")
	_trace.append(["hits", _describe(b), _stats(cache), parts.size(), cache.get_proto(path) != null])
	a.free()
	_check(_describe(b) == before_b, "A destruction cannot change B")
	b.free()
	cache.reset_load_stats()
	var preview: Node3D = cache.instance_glb_preview(_path("preview"))
	_trace.append(["preview", _describe(preview), _stats(cache)])
	preview.free()
	var hud: Node3D = cache.instance_glb_hud(path)
	_trace.append(["hud", _describe(hud), _stats(cache)])
	hud.free()
	for name: String in ["unit_fm1", "unit_fm2", "glow"]:
		var sample: Node3D = cache.instance_glb(_path(name), true)
		_trace.append([name, _describe(sample)])
		sample.free()
	await _preload(cache)
	_check(cache.preload_pending_count() == 0, "all preload work consumed")
	var source: Node3D = _fixture("source")
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	_check(document.append_from_scene(source, state) == OK, "export source fixture")
	var glb_path: String = _root_dir.path_join("source.glb")
	_check(document.write_to_filesystem(state, glb_path) == OK, "write embedded GLB fixture")
	source.free()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(glb_path)
	var raw: String = "contract/raw.glb"
	cache.store_bytes(raw, bytes)
	_check(cache.has_bytes_cached(raw) and cache.take_cached_bytes(raw) == bytes, "byte storage is lossless")
	_check(cache.take_cached_bytes(raw) == bytes, "take is a non-consuming read in the existing API")
	var from_bytes: Node3D = cache.instance_glb_from_bytes(raw, bytes)
	_trace.append(["bytes", _describe(from_bytes), _stats(cache)])
	from_bytes.free()
	var byte_hit: Node3D = cache.instance_glb_from_bytes(raw, bytes)
	_trace.append(["bytes_hit", _describe(byte_hit), _stats(cache)])
	byte_hit.free()
	var byte_preview: Node3D = cache.instance_glb_from_bytes_preview("contract/raw_preview.glb", bytes)
	_trace.append(["bytes_preview", _describe(byte_preview), _stats(cache)])
	byte_preview.free()
	var prototype: Node3D = cache.get_proto(raw)
	var prototype_id: int = prototype.get_instance_id()
	var survivor: Node3D = cache.instance_glb(raw)
	cache.evict(raw)
	_check(not is_instance_id_valid(prototype_id) and not cache.has_cached(raw) and not cache.has_bytes_cached(raw), "eviction clears its owned caches")
	_check(survivor.get_child_count() > 0, "eviction cannot destroy handed-out instances")
	survivor.free()
	cache.request_preload(_path("preload_a"))
	cache.cancel_preloads()
	_trace.append(["cancel", cache.preload_pending_count(), cache.is_preload_pending(_path("preload_a"))])
	_trace.append(["classification", MapModelCache.glb_path_uses_unit_soft_blend("Units/Human/Footman/Footman.gltf"), MapModelCache.glb_path_uses_unit_soft_blend("Units/Human/TownHall/TownHall.gltf")])
	var output: String = OS.get_cmdline_user_args()[0]
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(_trace))
	file.close()
	cache = null
	print("MODEL_CACHE_CONTRACT_%s checks=%d failures=%d" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)

func _preload(cache: MapModelCache) -> void:
	cache.reset_load_stats()
	cache.request_preload_many(PackedStringArray([_path("preload_a"), _path("preload_b")]))
	_trace.append(["preload_requested", cache.preload_pending_count(), cache.is_preload_pending(_path("preload_a"))])
	if DisplayServer.get_name() == "headless":
		_trace.append(["preload_budget_zero", cache.poll_preloads(0), cache.preload_pending_count()])
		_trace.append(["preload_budget_one", cache.poll_preloads(1), cache.preload_pending_count()])
	var deadline: int = Time.get_ticks_msec() + 10000
	while cache.preload_pending_count() > 0 and Time.get_ticks_msec() < deadline:
		cache.poll_preloads(1)
		await process_frame
	for name: String in ["preload_a", "preload_b"]:
		var node: Node3D = cache.instance_glb(_path(name))
		_trace.append([name, _describe(node), cache.get_proto(_path(name)) != null])
		node.free()
	_trace.append(["preload_stats", _stats(cache)])

func _path(name: String) -> String:
	return "res://assets/asset-converted/contract/" + name + ".gltf"

func _stats(cache: MapModelCache) -> Array:
	return [cache.last_scn_hits, cache.last_gltf_loads, cache.last_cache_hits]

func _fixture(name: String) -> Node3D:
	var model: Node3D = Node3D.new()
	model.name = name
	for index: int in range(2):
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "Geoset_%d" % index
		mesh.mesh = BoxMesh.new()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.resource_local_to_scene = true
		material.resource_name = "Material_fm1" if name == "unit_fm1" else "Material_fm2" if name == "unit_fm2" else "Material_fm3" if name == "glow" else "Material"
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if name in ["unit_fm1", "unit_fm2", "glow"] else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.albedo_color = Color(0.25, 0.75, 0.5, 0.6)
		mesh.set_surface_override_material(0, material)
		model.add_child(mesh)
		mesh.owner = model
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library: AnimationLibrary = AnimationLibrary.new()
	var stand: Animation = Animation.new()
	stand.length = 1
	var track: int = stand.add_track(Animation.TYPE_VALUE)
	stand.track_set_path(track, NodePath("Geoset_1:visible"))
	stand.track_insert_key(track, 0, false)
	library.add_animation("Stand", stand)
	player.add_animation_library("", library)
	model.add_child(player)
	player.owner = model
	return model

func _describe(model: Node3D) -> Array:
	var result: Array = []
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var row: Array = [str(node.name), mesh.visible, str(mesh.transform), mesh.mesh.get_surface_count() if mesh.mesh != null else 0]
		if mesh.mesh != null:
			for surface: int in range(mesh.mesh.get_surface_count()):
				var material: Material = mesh.get_active_material(surface)
				if material is StandardMaterial3D:
					var standard: StandardMaterial3D = material as StandardMaterial3D
					row.append([str(standard.resource_name), standard.transparency, standard.cull_mode, standard.blend_mode, standard.depth_draw_mode, str(standard.albedo_color), standard.alpha_scissor_threshold])
		result.append(row)
	return result
