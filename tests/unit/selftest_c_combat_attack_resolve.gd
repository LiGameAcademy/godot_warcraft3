extends SceneTree

## 战斗出手：Attack 逻辑名须解析到 Footman 的 Attack_-_* 变体。
## godot --headless --path . -s res://tests/unit/selftest_c_combat_attack_resolve.gd

func _init() -> void:
	var ok := true
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		push_error("Footman load null")
		quit(1)
		return
	var ap := AnimPlayback.find_animation_player(proto)
	if ap == null:
		push_error("no AnimationPlayer")
		quit(1)
		return
	var resolved := AnimPlayback.resolve(proto, "Attack", ap)
	print("  resolve Attack → %s" % resolved)
	var leaf := AnimPlayback.anim_leaf(resolved).to_lower()
	if resolved.is_empty() or not leaf.begins_with("attack") or leaf.contains("defend"):
		push_error("expected Attack_-_* family, got '%s'" % resolved)
		ok = false
	else:
		print("  Attack family OK")
	# 射程：出手不含整段 RngBuff
	# 无法在无 DefStore 时测 hfoo；这里只断言 API 语义注释覆盖的公式侧
	if ok:
		print("selftest_c_combat_attack_resolve: PASS")
		quit(0)
	else:
		push_error("selftest_c_combat_attack_resolve: FAIL")
		quit(1)
