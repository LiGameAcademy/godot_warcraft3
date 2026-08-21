extends SceneTree

## 死亡：Death 播完必须进入 Decay Flesh 尸体 Geoset（Stand 下隐藏的片）。
## godot --headless --path . -s res://tests/unit/selftest_death_anim.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_footman_death_from_defend()
	_test_footman_corpse_geoset()
	_test_footman_decay_bone()
	if failed == 0:
		print("selftest_death_anim: PASS")
		quit(0)
	else:
		push_error("selftest_death_anim: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _geoset_visible(root: Node, gi: int) -> bool:
	var exact := "Geoset_%d" % gi
	var prefix := exact + "_"
	for n in root.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		if nm == exact or nm.begins_with(prefix):
			if (n as Node3D).visible:
				return true
	return false


func _wrap_unit(model: Node3D) -> Unit:
	var unit := Unit.new()
	model.name = Unit.MODEL_NODE_NAME
	unit.add_child(model)
	return unit


func _test_footman_death_from_defend() -> void:
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		_fail("Footman gltf 加载失败")
		return
	var unit := _wrap_unit(proto)
	root.add_child(unit)
	var ap := AnimPlayback.find_animation_player(unit)
	unit.bind_animation_player(ap)
	unit.set_stance(AnimSequenceResolver.Stance.DEFEND)
	unit.play_death()
	if ap == null:
		_fail("Footman 无 AnimationPlayer")
		unit.queue_free()
		return
	if not ap.is_playing():
		_fail("play_death 后 AnimationPlayer 应在播放")
		unit.queue_free()
		return
	var leaf := AnimPlayback.anim_leaf(str(ap.current_animation)).replace(" ", "_").to_lower()
	if not leaf.begins_with("death"):
		_fail("顶盾下死亡应播 Death，实际 %s" % ap.current_animation)
		unit.queue_free()
		return
	print("  footman_death_from_defend OK anim=%s len=%.2f" % [ap.current_animation, ap.current_animation_length])
	unit.queue_free()


func _test_footman_corpse_geoset() -> void:
	var cache := MapModelCache.new()
	var proto: Node3D = cache.instance_glb(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		_fail("Footman cache instance 失败")
		return
	var unit := _wrap_unit(proto)
	root.add_child(unit)
	cache.snap_stand_geoset_visibility(unit)
	if _geoset_visible(unit, 2):
		_fail("Stand 下 Geoset_2（尸体）应隐藏")
		unit.queue_free()
		return
	unit.bind_cache(cache)
	unit.bind_animation_player(AnimPlayback.find_animation_player(unit))
	unit.play_death()
	if _geoset_visible(unit, 2):
		_fail("Death 进行中 Geoset_2 仍应隐藏")
		unit.queue_free()
		return
	unit.enter_corpse_state()
	if not _geoset_visible(unit, 2):
		_fail("enter_corpse_state 后 Geoset_2 尸体片应可见")
		unit.queue_free()
		return
	var ap := AnimPlayback.find_animation_player(unit)
	if ap == null or not ap.is_playing():
		_fail("Decay Flesh 应正在播放，不要定格")
		unit.queue_free()
		return
	var assigned := str(ap.current_animation)
	if assigned.is_empty():
		assigned = str(ap.assigned_animation)
	var leaf := AnimPlayback.anim_leaf(assigned).replace(" ", "_").to_lower()
	if not leaf.begins_with("decay") or leaf.contains("bone"):
		_fail("尸体态应变 Decay Flesh 并播放，实际 %s" % assigned)
		unit.queue_free()
		return
	if ap.speed_scale < 0.5:
		_fail("Decay Flesh 不应 freeze speed_scale=%s" % ap.speed_scale)
		unit.queue_free()
		return
	print("  footman_corpse_geoset OK decay=%s" % assigned)
	unit.queue_free()


func _test_footman_decay_bone() -> void:
	var cache := MapModelCache.new()
	var proto: Node3D = cache.instance_glb(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		_fail("Footman cache instance 失败 (bone)")
		return
	var unit := _wrap_unit(proto)
	root.add_child(unit)
	unit.bind_cache(cache)
	unit.bind_animation_player(AnimPlayback.find_animation_player(unit))
	unit.play_death()
	unit.enter_corpse_state()
	unit.enter_decay_bone()
	if _geoset_visible(unit, 2):
		_fail("Decay Bone 下 Geoset_2 应隐藏")
		unit.queue_free()
		return
	if not _geoset_visible(unit, 4):
		_fail("Decay Bone 下 Geoset_4 骨架/血泊应可见")
		unit.queue_free()
		return
	var ap := AnimPlayback.find_animation_player(unit)
	var leaf := ""
	if ap != null:
		leaf = AnimPlayback.anim_leaf(str(ap.current_animation)).replace(" ", "_").to_lower()
	if not leaf.begins_with("decay") or not leaf.contains("bone"):
		_fail("应播 Decay Bone，实际 %s" % (ap.current_animation if ap else "?"))
		unit.queue_free()
		return
	print("  footman_decay_bone OK")
	unit.queue_free()
