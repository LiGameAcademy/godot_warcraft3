extends RefCounted
## bake:scn：*.ribbon.json → RibbonRoot（Wc3RibbonEmitter）+ AnimationPlayer 闸门/平移轨。
## 层：tool（headless bake）。

const _Presenter := preload("res://scripts/presentation/wc3_model/wc3_ribbon_presenter.gd")
const _EmitterScript := preload("res://scripts/presentation/wc3_model/wc3_ribbon_emitter.gd")


static func apply(root: Node, glb_path: String) -> Dictionary:
	var result := {"ok": false, "ribbons": 0, "tracks": 0}
	if root == null or glb_path.is_empty():
		return result
	_remove_existing(root)
	if not _Presenter.has_ribbons(glb_path):
		result["ok"] = true
		return result
	var host: Node3D = _Presenter.build_root_from_glb(glb_path)
	if host == null:
		result["ok"] = true
		return result
	var parent: Node3D = root as Node3D
	if parent != null:
		parent = Wc3Pe2Particles.resolve_model_root(parent)
	if parent == null:
		host.free()
		return result
	parent.add_child(host)
	_set_owner_recursive(host, root)
	result["ribbons"] = host.get_child_count()
	result["tracks"] = _inject_tracks(root, host, glb_path)
	_Presenter.apply_sequence(root, "Birth")
	result["ok"] = true
	return result


static func _remove_existing(root: Node) -> void:
	var existing := root.find_child(_Presenter.RIBBON_ROOT_NAME, true, false)
	if existing == null:
		return
	var p := existing.get_parent()
	if p != null:
		p.remove_child(existing)
	existing.free()


static func _inject_tracks(root: Node, ribbon_root: Node, glb_path: String) -> int:
	var ap := _find_ap(root)
	if ap == null:
		return 0
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		anim_root = root
	var emitters: Array[Node] = []
	_collect_emitters(ribbon_root, emitters)
	if emitters.is_empty():
		return 0
	var seqs: Array = _Presenter.load_payload(glb_path).get("sequences", []) as Array
	# pe2 sidecar 也有 sequences；ribbon.json 可能无 → 回落 pe2
	if seqs.is_empty():
		seqs = Wc3Pe2Particles.load_payload(glb_path).get("sequences", []) as Array
	var n := 0
	for anim_name in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		if anim == null:
			continue
		var interval := _seq_interval(seqs, str(anim_name))
		for em in emitters:
			var rel := anim_root.get_path_to(em)
			if str(rel).is_empty() or str(rel) == ".":
				continue
			var on := _emitting_for_anim(em, str(anim_name))
			var emit_path := NodePath("%s:ribbon_emitting" % str(rel))
			_remove_tracks_with_path(anim, emit_path, Animation.TYPE_VALUE)
			var ti := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(ti, emit_path)
			anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
			anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			anim.track_insert_key(ti, 0.0, on)
			n += 1
			# Birth 内 Translation 摆动（水元素 Ribbon）
			var trans_meta: Variant = em.get_meta("wc3_ribbon_translation", null)
			if not (trans_meta is Dictionary):
				continue
			var keys: Array = (trans_meta as Dictionary).get("keys", []) as Array
			if keys.is_empty() or interval.y <= interval.x:
				continue
			_remove_tracks_with_path(anim, rel, Animation.TYPE_POSITION_3D)
			var pi := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pi, rel)
			var base_pos := (em as Node3D).position
			var wrote := false
			for k in keys:
				if typeof(k) != TYPE_DICTIONARY:
					continue
				var fr := float((k as Dictionary).get("frame", 0))
				if fr < interval.x - 0.5 or fr > interval.y + 0.5:
					continue
				var vec: Array = (k as Dictionary).get("vector", [0, 0, 0]) as Array
				var t := (fr - interval.x) / 1000.0
				if anim.length > 0.0:
					t = clampf(t, 0.0, anim.length)
				var off := Vector3(
					float(vec[0]) if vec.size() > 0 else 0.0,
					float(vec[1]) if vec.size() > 1 else 0.0,
					float(vec[2]) if vec.size() > 2 else 0.0
				)
				anim.track_insert_key(pi, t, base_pos + off)
				wrote = true
			if wrote:
				n += 1
			else:
				anim.remove_track(pi)
	return n


static func _emitting_for_anim(em: Node, anim_name: String) -> bool:
	if bool(em.get_meta("wc3_ribbon_always_on", false)):
		return true
	var seqs: PackedStringArray = em.get_meta(
		"wc3_ribbon_active_sequences", PackedStringArray()
	) as PackedStringArray
	var want := AnimPlayback.compact_seq_name(anim_name)
	for s in seqs:
		if AnimPlayback.compact_seq_name(str(s)) == want:
			return true
		var a := str(s).strip_edges().to_lower()
		var b := want.strip_edges().to_lower()
		if a.get_slice(" ", 0) == b.get_slice(" ", 0):
			return true
	return false


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


static func _collect_emitters(n: Node, out: Array[Node]) -> void:
	if n.get_script() == _EmitterScript:
		out.append(n)
	for c in n.get_children():
		_collect_emitters(c, out)


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
