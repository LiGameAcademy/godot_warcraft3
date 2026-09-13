extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var failures := 0
	var cache := MapModelCache.new()
	var prototype := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	prototype.add_child(mesh)
	# 原型缓存的所有权边界；绕过磁盘转换以单独验证生命周期。
	cache._scene_cache["fixture"] = prototype
	var instance := prototype.duplicate()
	add_child(instance)
	var reference: WeakRef = weakref(cache)
	cache = null
	if reference.get_ref() != null:
		failures += 1
		push_error("CACHE LIFETIME: 缓存对象未释放")
	if is_instance_valid(prototype):
		failures += 1
		push_error("CACHE LIFETIME: 原型节点泄漏")
		prototype.free()
	if not is_instance_valid(instance) or instance.get_child_count() != 1:
		failures += 1
		push_error("CACHE LIFETIME: 实例被误释放")
	print("selftest_model_cache_lifetime: %s (3 checks)" % ["PASS" if failures == 0 else "FAIL"])
	get_tree().quit(0 if failures == 0 else 1)
