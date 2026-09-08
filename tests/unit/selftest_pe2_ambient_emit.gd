extends SceneTree

## Stand/Walk 常驻 PE2 在 apply_sequence 后必须 emitting（水元素脚底）。
## godot --headless --path . -s res://tests/unit/selftest_pe2_ambient_emit.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_water_stand_emitting()
	_test_ambient_key_helper()
	if failed == 0:
		print("selftest_pe2_ambient_emit: PASS")
		quit(0)
	else:
		push_error("selftest_pe2_ambient_emit: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_ambient_key_helper() -> void:
	if not Wc3Pe2Particles._is_ambient_loop_key("stand"):
		_fail("stand 应为 ambient")
		return
	if not Wc3Pe2Particles._is_ambient_loop_key("stand2"):
		_fail("stand2 应为 ambient")
		return
	if not Wc3Pe2Particles._is_ambient_loop_key("walk"):
		_fail("walk 应为 ambient")
		return
	if Wc3Pe2Particles._is_ambient_loop_key("standwork"):
		_fail("standwork 不应为 ambient")
		return
	if Wc3Pe2Particles._is_ambient_loop_key("attack"):
		_fail("attack 不应为 ambient")
		return
	print("  ambient_key_helper OK")


func _test_water_stand_emitting() -> void:
	var path := "res://assets/asset-converted/Units/Human/WaterElemental/WaterElemental.gltf"
	if not Wc3Pe2Particles.has_emitters(path):
		_fail("WaterElemental 应有 pe2 emitters")
		return
	var cache := MapModelCache.new()
	var root := cache.instance_glb(path, true)
	if root == null:
		_fail("instance_glb WaterElemental 失败")
		return
	get_root().add_child(root)
	cache.autoplay_stand(root)
	Wc3Pe2Particles.attach_to(root, path)
	Wc3Pe2Particles.apply_sequence(root, "Stand")
	var foot := 0
	var foot_on := 0
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		var nm := str(p.name)
		if nm != "BlizParticle03" and nm != "BlizParticle04":
			continue
		foot += 1
		if p.emitting:
			foot_on += 1
		else:
			_fail("%s Stand 后应 emitting=true" % nm)
	if foot < 2:
		_fail("应找到 BlizParticle03/04，实际 %d" % foot)
		return
	if foot_on < 2:
		return
	print("  water_stand_emitting OK (%d)" % foot_on)
	root.queue_free()
