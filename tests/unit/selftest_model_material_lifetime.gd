extends SceneTree

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var prototype: Node3D = _fixture()
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(prototype) == OK, "Fixture must pack")
	var cache: MapModelCache = MapModelCache.new()
	cache._scene_cache["material-fixture"] = prototype
	cache.register_external_packed("material-fixture", packed)
	var first_started: int = Time.get_ticks_usec()
	for iteration: int in range(12):
		var started: int = Time.get_ticks_usec()
		var a: Node3D = cache.instance_glb("material-fixture")
		var b: Node3D = cache.instance_glb("material-fixture")
		_check(a.get_child_count() == 2 and b.get_child_count() == 2, "Packing preserves both geosets")
		var before: Array = _capture(b)
		_check(a.get_child(1).get_active_material(0) != b.get_child(1).get_active_material(0),
			"Hidden local material must be isolated between instances")
		var parts: Array = cache.mesh_parts_from_glb("material-fixture")
		_check(parts.size() == 1, "Static extraction keeps the visible canopy, not the hidden stump")
		var hidden: WeakRef = weakref(a.get_child(1).get_active_material(0))
		a.free()
		_check(hidden.get_ref() == null, "Destroying an instance releases its unretained hidden material")
		_check(parts[0].mesh != null and parts[0].material != null, "Extracted geometry and material remain alive")
		_check(_capture(b) == before, "Destroying A cannot change B mesh, material, visibility or transform")
		_check((prototype.get_child(0) as MeshInstance3D).mesh != null,
			"Destroying a clone cannot detach the cached prototype")
		b.free()
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		print("MODEL_MATERIAL_LIFETIME_SAMPLE iteration=", iteration, " elapsed_ms=", elapsed_ms)

	print("MODEL_MATERIAL_LIFETIME_SYNC elapsed_ms=", float(Time.get_ticks_usec() - first_started) / 1000.0)
	var queued: Node3D = packed.instantiate() as Node3D
	root.add_child(queued)
	var queued_id: int = queued.get_instance_id()
	queued.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_id_valid(queued_id), "Queued destruction completes")
	var prototype_id: int = prototype.get_instance_id()
	var cache_reference: WeakRef = weakref(cache)
	cache = null
	_check(cache_reference.get_ref() == null and not is_instance_id_valid(prototype_id),
		"Cache release destroys its off-tree prototype without retaining the root")
	print("MODEL_MATERIAL_LIFETIME_ASSERTIONS_%s checks=%d failures=%d" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)

func _fixture() -> Node3D:
	var model: Node3D = Node3D.new()
	model.name = "MaterialFixture"
	for index: int in range(2):
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "Canopy" if index == 0 else "Stump"
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.resource_local_to_scene = true
		material.albedo_color = Color(0.3, 0.8, 0.2)
		mesh.mesh = BoxMesh.new()
		mesh.set_surface_override_material(0, material)
		mesh.visible = index == 0
		model.add_child(mesh)
		mesh.owner = model
	return model

func _capture(model: Node3D) -> Array:
	var result: Array = []
	for child: Node in model.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child as MeshInstance3D
			result.append([mesh.mesh, mesh.get_active_material(0), mesh.visible, mesh.transform])
	return result
