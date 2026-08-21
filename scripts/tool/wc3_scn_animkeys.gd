extends RefCounted
## bake:scn：animkeys.json → Animation.loop_mode / Sequence meta / Event Method Track。
## 不写原始 Hermite 局部 TRS（glTF 已烤世界矩阵轨）。

const EVENTS_SCRIPT := preload("res://scripts/presentation/wc3_model/mdx_anim_events.gd")
const EVENTS_NODE := "MdxEvents"
const META_MDX_NAME := "wc3_mdx_name"
const META_RARITY := "wc3_rarity"
const META_MOVE_SPEED := "wc3_move_speed"
const META_LOOPING := "wc3_seq_looping"
const FIRE_METHOD := "fire"


static func apply(root: Node, data: Dictionary) -> Dictionary:
	var result := {"ok": false, "sequences": 0, "event_keys": 0}
	if root == null or data.is_empty():
		return result
	var ap := _find_ap(root)
	if ap == null:
		return result
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		anim_root = root
	var sequences: Array = data.get("sequences", [])
	var events: Array = data.get("events", [])
	var host: Node = null
	if not events.is_empty():
		host = _ensure_events_node(root)
	var event_path := NodePath()
	if host != null:
		event_path = anim_root.get_path_to(host)
	for seq_v in sequences:
		if typeof(seq_v) != TYPE_DICTIONARY:
			continue
		var seq: Dictionary = seq_v
		var resolved := _resolve_anim(ap, str(seq.get("name", "")).strip_edges())
		if resolved.is_empty():
			continue
		var anim := ap.get_animation(resolved)
		if anim == null:
			continue
		_apply_sequence_meta(anim, seq)
		if host != null and not str(event_path).is_empty():
			result["event_keys"] = int(result["event_keys"]) + _apply_event_track(
				anim, event_path, seq, events
			)
		result["sequences"] = int(result["sequences"]) + 1
	_set_owner_recursive(root, root)
	result["ok"] = true
	return result


static func _apply_sequence_meta(anim: Animation, seq: Dictionary) -> void:
	var looping := bool(seq.get("looping", true))
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	anim.set_meta(META_LOOPING, looping)
	anim.set_meta(META_MDX_NAME, str(seq.get("mdx_name", "")))
	anim.set_meta(META_RARITY, int(seq.get("rarity", 0)))
	anim.set_meta(META_MOVE_SPEED, float(seq.get("move_speed", 0.0)))


static func _apply_event_track(
	anim: Animation, event_path: NodePath, seq: Dictionary, events: Array
) -> int:
	var interval: Variant = seq.get("interval", [])
	if typeof(interval) != TYPE_ARRAY or (interval as Array).size() < 2:
		return 0
	var start_ms := float((interval as Array)[0])
	var end_ms := float((interval as Array)[1])
	if end_ms <= start_ms:
		return 0
	_remove_tracks_with_path(anim, event_path, Animation.TYPE_METHOD)
	var keys: Array[Dictionary] = []
	for ev_v in events:
		if typeof(ev_v) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_v
		var ename := str(ev.get("name", "")).strip_edges()
		if ename.is_empty():
			continue
		var frames_v: Variant = ev.get("frames", [])
		if typeof(frames_v) != TYPE_ARRAY:
			continue
		for fr_v in frames_v as Array:
			var fr := float(fr_v)
			if fr < start_ms or fr > end_ms:
				continue
			var t := (fr - start_ms) / 1000.0
			if anim.length > 0.0:
				t = clampf(t, 0.0, anim.length)
			keys.append({"t": t, "name": ename})
	if keys.is_empty():
		return 0
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	# Godot 同一 Method Track 同一时间只能 1 个 key。同帧多 EventObject：各占一条轨，同一时刻各 fire 一次。
	var lanes: Array = []
	var time_eps := 1e-6
	for kv in keys:
		var t := float(kv["t"])
		var placed := false
		for lane_v in lanes:
			var lane: Array = lane_v
			var last_t := float((lane[lane.size() - 1] as Dictionary)["t"])
			if t - last_t > time_eps:
				lane.append(kv)
				placed = true
				break
		if not placed:
			lanes.append([kv])
	var inserted := 0
	for lane_v2 in lanes:
		var lane2: Array = lane_v2
		var ti := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(ti, event_path)
		anim.track_set_imported(ti, false)
		for item_v in lane2:
			var item: Dictionary = item_v
			anim.track_insert_key(
				ti,
				float(item["t"]),
				{"method": FIRE_METHOD, "args": [str(item["name"])]},
				0
			)
			inserted += 1
	return inserted


static func _ensure_events_node(root: Node) -> Node:
	var existing := root.find_child(EVENTS_NODE, true, false)
	if existing != null:
		if existing.get_script() != EVENTS_SCRIPT:
			existing.set_script(EVENTS_SCRIPT)
		return existing
	var host := Node.new()
	host.name = EVENTS_NODE
	host.set_script(EVENTS_SCRIPT)
	root.add_child(host)
	return host


static func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			return c as AnimationPlayer
	return null


static func _resolve_anim(ap: AnimationPlayer, anim_name: String) -> String:
	if ap == null or anim_name.is_empty():
		return ""
	if ap.has_animation(anim_name):
		return anim_name
	var want := AnimPlayback.compact_seq_name(anim_name)
	for n in ap.get_animation_list():
		if AnimPlayback.compact_seq_name(str(n)) == want:
			return str(n)
	return ""


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
