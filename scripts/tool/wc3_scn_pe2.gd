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
			n += _inject_rate_and_bursts(anim, p, rel, str(anim_name), interval)
			p.set_meta("pe2_timeline_baked", true)
			# Persist idle state for direct scene preview before an AP starts.
			if Wc3Pe2Particles._normalize_seq_key(str(anim_name)) == "stand":
				p.emitting = bool(keys[0]["on"])
				var ratio_track := anim.find_track(NodePath("%s:amount_ratio" % rel), Animation.TYPE_VALUE)
				if ratio_track >= 0 and anim.track_get_key_count(ratio_track) > 0:
					p.amount_ratio = float(anim.track_get_key_value(ratio_track, 0))
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
	if bool(p.get_meta("pe2_squirt", false)):
		return [{"t": 0.0, "on": false}]
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
		# Animated rates use amount_ratio (zero included), otherwise a ramp out of
		# zero would remain blocked until its next positive endpoint.
		var on := vis >= 0.5 and (rate > 0.01 or not rate_keys.is_empty())
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


static func _inject_rate_and_bursts(anim: Animation, p: GPUParticles3D, rel: NodePath, anim_name: String, interval: Vector2) -> int:
	var ratio_path := NodePath("%s:amount_ratio" % rel)
	_remove_tracks_with_path(anim, ratio_path, Animation.TYPE_VALUE)
	_remove_tracks_with_path(anim, rel, Animation.TYPE_METHOD)
	var rate_keys: Array = p.get_meta(Wc3Pe2Particles.META_RATE_KEYS, [])
	var static_rate := float(p.get_meta(Wc3Pe2Particles.META_STATIC_RATE, 0.0))
	var multiplier := float(p.get_meta("pe2_rate_multiplier", 1.0))
	var active := Wc3Pe2Particles.emitting_for_sequence(p, anim_name)
	if bool(p.get_meta("pe2_squirt", false)):
		if not active:
			return 0
		var bursts: Array = rate_keys
		if bursts.is_empty():
			bursts = [{"frame": interval.x, "value": static_rate}]
		var method_track := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(method_track, rel)
		var vis_keys: Array = p.get_meta(Wc3Pe2Particles.META_VIS_KEYS, [])
		for key in bursts:
			var frame := float(key.get("frame", 0.0))
			if frame < interval.x or frame > interval.y:
				continue
			var count := roundi(maxf(0.0, float(key.get("value", 0.0))) * multiplier)
			var visible := Wc3Pe2Particles._sample_track(vis_keys, int(frame), int(interval.x), int(interval.y), 1.0) >= 0.5
			if count > 0 and visible:
				var time := minf((frame - interval.x) / 1000.0, anim.length)
				# AnimPlayback seeks to zero after play(), skipping method keys exactly
				# at zero. Put start bursts inside the first simulation tick instead.
				if time == 0.0 and anim.length > 0.0:
					time = minf(0.000001, anim.length * 0.5)
				anim.track_insert_key(method_track, time, {"method": &"emit_burst", "args": [count]})
		return 1
	var ti := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(ti, ratio_path)
	anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
	anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
	var frames: Dictionary = {interval.x: true}
	for key in rate_keys:
		var frame := float(key.get("frame", 0.0))
		if frame >= interval.x and frame <= interval.y:
			frames[frame] = true
	var interpolation := int(p.get_meta("pe2_rate_interpolation", 0))
	if interpolation != 0 and not rate_keys.is_empty():
		# Bake scalar curves at 60 Hz plus exact source keys; no runtime JSON reads.
		var duration := minf(anim.length, maxf(0.0, interval.y - interval.x) / 1000.0)
		for i in range(ceili(duration * 60.0) + 1):
			frames[minf(interval.x + float(i) * 1000.0 / 60.0, interval.y)] = true
	var ordered: Array = frames.keys()
	ordered.sort()
	for frame in ordered:
		var rate := static_rate if rate_keys.is_empty() else _sample_rate(rate_keys, float(frame), interval, interpolation)
		var ratio := clampf(rate * multiplier * p.lifetime / float(p.amount), 0.0, 1.0) if active else 0.0
		anim.track_insert_key(ti, minf((float(frame) - interval.x) / 1000.0, anim.length), ratio)
	return 1


static func _sample_rate(keys: Array, frame: float, interval: Vector2, interpolation: int) -> float:
	var previous: Dictionary = {}
	for raw in keys:
		var key: Dictionary = raw
		var time := float(key.get("frame", 0.0))
		if time < interval.x or time > interval.y:
			continue
		if time <= frame:
			previous = key
			continue
		if previous.is_empty():
			return 0.0
		var a := float(previous.get("value", 0.0))
		var b := float(key.get("value", 0.0))
		var t := (frame - float(previous["frame"])) / (time - float(previous["frame"]))
		if interpolation == 1:
			return maxf(0.0, lerpf(a, b, t))
		if interpolation == 2:
			var out_tan := float(previous.get("out_tan", 0.0))
			var in_tan := float(key.get("in_tan", 0.0))
			return maxf(0.0, (2*t*t*t - 3*t*t + 1)*a + (t*t*t - 2*t*t + t)*out_tan + (-2*t*t*t + 3*t*t)*b + (t*t*t - t*t)*in_tan)
		if interpolation == 3:
			var out_tan := float(previous.get("out_tan", a))
			var in_tan := float(key.get("in_tan", b))
			return maxf(0.0, pow(1-t, 3)*a + 3*pow(1-t, 2)*t*out_tan + 3*(1-t)*t*t*in_tan + t*t*t*b)
		return maxf(0.0, a)
	return maxf(0.0, float(previous.get("value", 0.0)))


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
