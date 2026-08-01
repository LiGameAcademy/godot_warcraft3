extends SceneTree
## 自测：brazierOmni PE2 旁路 JSON 可挂载到 GLB 实例。

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := Wc3IdCatalog.new()
	catalog.load_default()
	var cache := MapModelCache.new()
	var glb := catalog.converted_glb_path("LObz", 0)
	if glb.is_empty():
		push_error("selftest pe2: LObz GLB path empty")
		quit(1)
		return
	if not _Pe2.has_emitters(glb):
		push_error("selftest pe2: missing emitters for %s" % glb)
		quit(1)
		return
	var node := cache.instance_glb(glb)
	if node == null:
		push_error("selftest pe2: instance_glb failed")
		quit(1)
		return
	var n: int = int(_Pe2.attach_to(node, glb))
	if n < 2:
		push_error("selftest pe2: expected >=2 emitters, got %d" % n)
		quit(1)
		return
	var pe2 := node.get_node_or_null("Pe2Root")
	if pe2 == null:
		# 挂在 MODEL_SCALE 子节点下
		pe2 = node.find_child("Pe2Root", true, false)
	if pe2 == null or pe2.get_child_count() < 2:
		push_error("selftest pe2: Pe2Root incomplete")
		quit(1)
		return
	var parent_s: Vector3 = (pe2.get_parent() as Node3D).scale if pe2.get_parent() is Node3D else Vector3.ONE
	var pe2_s: Vector3 = (pe2 as Node3D).scale
	var scaled := (
		(absf(parent_s.x - 0.01) < 1e-3)
		or (absf(pe2_s.x - 0.01) < 1e-3)
	)
	if not scaled:
		push_error("selftest pe2: Pe2Root not under MODEL_SCALE (parent=%s pe2=%s)" % [parent_s, pe2_s])
		quit(1)
		return
	var flame := pe2.get_node_or_null("BlizParticle01") as GPUParticles3D
	if flame == null or not flame.emitting:
		push_error("selftest pe2: BlizParticle01 missing/not emitting")
		quit(1)
		return
	print(
		"selftest PE2: LObz emitters=%d flame_amount=%d parent=%s ok"
		% [n, flame.amount, pe2.get_parent().name]
	)
	node.free()
	quit(0)
