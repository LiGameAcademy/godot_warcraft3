extends SceneTree

## 同族 rarity：Wc3AnimPlayer.collect_family / pick_family。
## godot --headless --path . -s res://tests/unit/selftest_anim_family_rarity.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_footman_stand_family()
	_test_footman_attack_no_defend()
	_test_weighted_prefers_common()
	if failed == 0:
		print("selftest_anim_family_rarity: PASS")
		quit(0)
	else:
		push_error("selftest_anim_family_rarity: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _footman_ap() -> AnimationPlayer:
	var cache := MapModelCache.new()
	var proto: Node3D = cache.instance_glb(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		_fail("Footman instance 失败")
		return null
	root.add_child(proto)
	var ap := Wc3AnimPlayer.ensure_on(proto)
	if ap == null:
		_fail("无 AnimationPlayer")
		proto.queue_free()
		return null
	# 无 bake meta 时从 animkeys 补 rarity，便于未 force-rebake 的环境
	_ensure_rarity_from_animkeys(ap, "res://assets/asset-converted/Units/Human/Footman/Footman.animkeys.json")
	return ap


func _ensure_rarity_from_animkeys(ap: AnimationPlayer, animkeys_path: String) -> void:
	if ap == null or not FileAccess.file_exists(animkeys_path):
		return
	var raw := FileAccess.get_file_as_string(animkeys_path)
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		return
	var seqs: Array = (data as Dictionary).get("sequences", [])
	for seq_v in seqs:
		if not (seq_v is Dictionary):
			continue
		var seq: Dictionary = seq_v
		var rarity := float(seq.get("rarity", 0))
		var keys: Array[String] = [
			str(seq.get("mdx_name", "")),
			str(seq.get("name", "")),
		]
		for key in keys:
			if key.is_empty():
				continue
			var want_c := AnimPlayback.compact_seq_name(key)
			for n in ap.get_animation_list():
				if AnimPlayback.compact_seq_name(str(n)) != want_c:
					continue
				var anim := ap.get_animation(str(n))
				if anim == null:
					continue
				if not anim.has_meta(Wc3AnimPlayer.META_RARITY):
					anim.set_meta(Wc3AnimPlayer.META_RARITY, rarity)
				break


func _test_footman_stand_family() -> void:
	var ap := _footman_ap()
	if ap == null:
		return
	var members: PackedStringArray = ap.call("collect_family", "Stand")
	if members.size() < 2:
		_fail("Stand 族应变体≥2，实际 %s" % str(members))
		ap.get_parent().queue_free()
		return
	var saw_r4 := false
	for m in members:
		var leaf := AnimPlayback.anim_leaf(str(m)).to_lower()
		if leaf.contains("defend") or leaf.contains("victory") or leaf.contains("work"):
			_fail("Stand 族不应含姿态后缀: %s" % m)
			ap.get_parent().queue_free()
			return
		if int(ap.call("seq_rarity", str(m))) == 4:
			saw_r4 = true
	if not saw_r4:
		_fail("期望 Stand-2 rarity=4（animkeys / bake meta） members=%s" % str(members))
		ap.get_parent().queue_free()
		return
	print("  stand_family OK n=%d %s" % [members.size(), members])
	ap.get_parent().queue_free()


func _test_footman_attack_no_defend() -> void:
	var ap := _footman_ap()
	if ap == null:
		return
	var members: PackedStringArray = ap.call("collect_family", "Attack")
	if members.is_empty():
		_fail("Attack 族为空")
		ap.get_parent().queue_free()
		return
	for m in members:
		var leaf := AnimPlayback.anim_leaf(str(m)).to_lower()
		if leaf.contains("defend"):
			_fail("Attack 族含 Defend: %s" % m)
			ap.get_parent().queue_free()
			return
	var resolved := AnimPlayback.resolve(ap.get_parent(), "Attack", ap)
	var leaf_r := AnimPlayback.anim_leaf(resolved).to_lower()
	if resolved.is_empty() or not leaf_r.begins_with("attack") or leaf_r.contains("defend"):
		_fail("resolve Attack 失败: %s" % resolved)
		ap.get_parent().queue_free()
		return
	print("  attack_family OK → %s" % resolved)
	ap.get_parent().queue_free()


func _test_weighted_prefers_common() -> void:
	var ap := _footman_ap()
	if ap == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts: Dictionary = {}
	var n := 400
	for i in n:
		var pick: String = str(ap.call("pick_family", "Stand", rng))
		var leaf := AnimPlayback.anim_leaf(pick)
		counts[leaf] = int(counts.get(leaf, 0)) + 1
	var best_leaf := ""
	var best_n := -1
	var best_r := 999.0
	for m in ap.call("collect_family", "Stand"):
		var leaf := AnimPlayback.anim_leaf(str(m))
		var c: int = int(counts.get(leaf, 0))
		if c > best_n:
			best_n = c
			best_leaf = leaf
			best_r = float(ap.call("seq_rarity", str(m)))
	if best_r > 0.5:
		_fail(
			"加权应偏好 rarity≈0，最多=%s count=%d rarity=%s dist=%s"
			% [best_leaf, best_n, best_r, str(counts)]
		)
		ap.get_parent().queue_free()
		return
	print("  weighted_prefers_common OK top=%s/%d dist=%s" % [best_leaf, best_n, str(counts)])
	ap.get_parent().queue_free()
