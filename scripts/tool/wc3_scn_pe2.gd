extends RefCounted
## bake:scn：pe2.json → Pe2Root（GPUParticles3D）+ AnimationPlayer :emitting / position。
## 贴图内嵌 ImageTexture，不 ExtResource 进 .gdignore 的 asset-converted。
## Pe2Root 挂在 MODEL_SCALE=0.01 模型根下（与网格同空间）。
## 有 bone 的发射器 → BoneAttachment3D（跟杖尖等），emitting 仍由 Animation 轨脉冲。
## 层：tool（headless bake）；运行时由表现层 AnimationPlayer 驱动。

static func apply(root: Node, glb_path: String) -> Dictionary:
	var result := {"ok": false, "emitters": 0, "tracks": 0, "bones": 0}
	if root == null or glb_path.is_empty():
		return result
	_remove_existing_pe2(root)
	if not Wc3Pe2Particles.has_emitters(glb_path):
		result["ok"] = true
		return result
	var pe2: Node3D = Wc3Pe2Particles.build_root_from_glb(glb_path)
	if pe2 == null:
		result["ok"] = true
		return result
	var parent: Node3D = root as Node3D
	if parent != null:
		parent = Wc3Pe2Particles.resolve_model_root(parent)
	if parent == null:
		pe2.free()
		return result
	parent.add_child(pe2)
	_set_owner_recursive(pe2, root)
	result["bones"] = Wc3Pe2Particles.bind_emitters_to_bones(root, pe2)
	_set_owner_recursive(pe2, root)
	result["emitters"] = _count_particles(pe2)
	result["tracks"] = _inject_tracks(root, pe2, glb_path)
	Wc3Pe2Particles.apply_sequence(root, "Stand")
	result["ok"] = true
	return result


static func _remove_existing_pe2(root: Node) -> void:
	var existing := root.find_child(Wc3Pe2Particles.PE2_ROOT_NAME, true, false)
	if existing == null:
		return
	var p := existing.get_parent()
	if p != null:
		p.remove_child(existing)
	existing.free()


static func _inject_tracks(root: Node, pe2_root: Node, glb_path: String = "") -> int:
	var ap := _find_ap(root)
	if ap == null:
		return 0
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		anim_root = root
	var particles: Array[GPUParticles3D] = []
	# 绑骨后可能在 Attach_*/Tip 下，不在 Pe2Root 里
	_collect_particles(root, particles)
	if particles.is_empty():
		return 0
	var seqs: Array = []
	if not glb_path.is_empty():
		seqs = Wc3Pe2Particles.load_payload(glb_path).get("sequences", []) as Array
	var n := 0
	for anim_name in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		if anim == null:
			continue
		var interval := _seq_interval(seqs, str(anim_name))
		for p in particles:
			var rel := anim_root.get_path_to(p)
			if str(rel).is_empty() or str(rel) == ".":
				continue
			var keys := _emitting_keys(p, str(anim_name), interval, anim.length)
			# 必须写入「全关」轨：否则切到 Death 时 Stand 粒子仍粘在上一剪辑的 emitting=true。
			# （旧逻辑用 _keys_ever_on 跳过全关 → 火球 Death 看不到爆开、尾烟不停。）
			if keys.is_empty():
				keys = [{"t": 0.0, "on": false}]
			var emit_path := NodePath("%s:emitting" % str(rel))
			_remove_tracks_with_path(anim, emit_path, Animation.TYPE_VALUE)
			var ti := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(ti, emit_path)
			anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
			anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			for kv in keys:
				anim.track_insert_key(ti, float(kv["t"]), bool(kv["on"]))
			n += 1
			# 绑骨：跟 BoneAttachment，不要世界空间 position 轨
			if bool(p.get_meta(Wc3Pe2Particles.META_BONE_BOUND, false)):
				continue
			var by_seq: Variant = p.get_meta(Wc3Pe2Particles.META_PIVOT_BY_SEQ, {})
			if not (by_seq is Dictionary) or (by_seq as Dictionary).is_empty():
				continue
			_remove_tracks_with_path(anim, rel, Animation.TYPE_POSITION_3D)
			var pi := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pi, rel)
			anim.track_insert_key(pi, 0.0, Wc3Pe2Particles.pivot_for_sequence(p, str(anim_name)))
			n += 1
	return n


static func _seq_interval(seqs: Array, anim_name: String) -> Vector2:
	var want := AnimPlayback.compact_seq_name(anim_name)
	for s in seqs:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		if AnimPlayback.compact_seq_name(str(d.get("name", ""))) != want:
			continue
		var iv: Variant = d.get("interval", [])
		if typeof(iv) != TYPE_ARRAY or (iv as Array).size() < 2:
			return Vector2.ZERO
		return Vector2(float((iv as Array)[0]), float((iv as Array)[1]))
	return Vector2.ZERO


## vis/rate 关键帧写进 clip：Birth 扬尘 333ms 才开，不是整段 emitting=true。
static func _emitting_keys(p: GPUParticles3D, anim_name: String, interval: Vector2, anim_len: float) -> Array:
	var base_on := Wc3Pe2Particles.emitting_for_sequence(p, anim_name)
	if not base_on:
		return [{"t": 0.0, "on": false}]
	var start_ms := interval.x
	var end_ms := interval.y
	if end_ms <= start_ms:
		return [{"t": 0.0, "on": true}]
	var vis_keys: Array = p.get_meta(Wc3Pe2Particles.META_VIS_KEYS, []) as Array
	var rate_keys: Array = p.get_meta(Wc3Pe2Particles.META_RATE_KEYS, []) as Array
	var static_rate := float(p.get_meta(Wc3Pe2Particles.META_STATIC_RATE, 1.0))
	var frames: Dictionary = {start_ms: true}
	for k in vis_keys:
		if typeof(k) != TYPE_DICTIONARY:
			continue
		var fr := float((k as Dictionary).get("frame", 0))
		if fr >= start_ms and fr <= end_ms:
			frames[fr] = true
	for k2 in rate_keys:
		if typeof(k2) != TYPE_DICTIONARY:
			continue
		var fr2 := float((k2 as Dictionary).get("frame", 0))
		if fr2 >= start_ms and fr2 <= end_ms:
			frames[fr2] = true
	var ordered: Array = frames.keys()
	ordered.sort()
	var out: Array = []
	var last_on := -1
	for fr_v in ordered:
		var fr := float(fr_v)
		var vis := Wc3Pe2Particles._sample_track(vis_keys, int(fr), int(start_ms), int(end_ms), 1.0)
		var rate := static_rate
		if not rate_keys.is_empty():
			rate = Wc3Pe2Particles._sample_track(rate_keys, int(fr), int(start_ms), int(end_ms), 0.0)
		var on := vis >= 0.5 and rate > 0.01
		var t := (fr - start_ms) / 1000.0
		if anim_len > 0.0:
			t = clampf(t, 0.0, anim_len)
		var on_i := 1 if on else 0
		if on_i == last_on:
			continue
		last_on = on_i
		out.append({"t": t, "on": on})
	if out.is_empty():
		out.append({"t": 0.0, "on": true})
	return out


static func _collect_particles(n: Node, out: Array[GPUParticles3D]) -> void:
	if n is GPUParticles3D:
		out.append(n as GPUParticles3D)
	for c in n.get_children():
		_collect_particles(c, out)


static func _count_particles(n: Node) -> int:
	var acc: Array[GPUParticles3D] = []
	_collect_particles(n, acc)
	return acc.size()


static func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			return c as AnimationPlayer
	return null


static func _remove_tracks_with_path(anim: Animation, track_path: NodePath, ttype: int) -> void:
	var want := str(track_path)
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != ttype:
			continue
		if str(anim.track_get_path(i)) == want:
			anim.remove_track(i)


static func _set_owner_recursive(n: Node, owner: Node) -> void:
	if n != owner:
		n.owner = owner
	for c in n.get_children():
		_set_owner_recursive(c, owner)
