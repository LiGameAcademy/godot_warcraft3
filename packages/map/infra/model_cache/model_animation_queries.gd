extends RefCounted
## 动画名称、待机回退与骨骼运动判断。


const _MIN_SKELETAL_TRACKS: int = 6


## AnimationPlayer 动画名解析：精确 → 叶名大小写不敏感 → 驼峰/去空格 → 库前缀。
static func _resolve_animation_name(ap: AnimationPlayer, anim_name: String) -> String:
	if ap == null or anim_name.is_empty():
		return ""
	if ap.has_animation(anim_name):
		return anim_name
	var want: String = _anim_leaf_name(anim_name).to_lower()
	var want_c: String = AnimPlayback.compact_seq_name(anim_name)
	for n: String in ap.get_animation_list():
		var full: String = str(n)
		var leaf: String = _anim_leaf_name(full)
		if leaf.to_lower() == want:
			return full
		if AnimPlayback.compact_seq_name(full) == want_c:
			return full
	return ""


static func _scene_has_skeletal_stand(n: Node) -> bool:
	var ap: AnimationPlayer = _find_animation_player(n)
	if ap == null:
		return false
	var stand: String = _pick_stand_name(ap)
	if stand.is_empty():
		return false
	return _is_skeletal_motion(ap.get_animation(stand))


static func _pick_stand_name(ap: AnimationPlayer) -> String:
	var names: PackedStringArray = ap.get_animation_list()
	if names.is_empty():
		return ""
	# 精确 Stand / stand（含 AnimationLibrary 前缀 lib/Stand）
	for n: String in names:
		var leaf: String = _anim_leaf_name(str(n))
		if leaf == "Stand" or leaf == "stand":
			return str(n)
	# Stand 变体：Stand - 1 / Stand Ready / Stand Work…
	for n: String in names:
		var leaf2: String = _anim_leaf_name(str(n))
		var low: String = leaf2.to_lower()
		if low.begins_with("stand"):
			return str(n)
	return ""


## 无 Stand 时回退：Walk / Portrait / 其它非战斗动作；绝不首选 Attack。
static func _pick_idle_fallback(ap: AnimationPlayer) -> String:
	var names: PackedStringArray = ap.get_animation_list()
	if names.is_empty():
		return ""
	var prefer: Array[String] = ["walk", "portrait", "stand", "ready", "idle"]
	for key: String in prefer:
		for n: String in names:
			var low: String = _anim_leaf_name(str(n)).to_lower()
			if low.begins_with(key) or low.contains(key):
				if _is_combat_anim_name(low):
					continue
				return str(n)
	for n: String in names:
		var low2: String = _anim_leaf_name(str(n)).to_lower()
		if not _is_combat_anim_name(low2):
			return str(n)
	return str(names[0])


static func _anim_leaf_name(full: String) -> String:
	# Godot 4：库内动画名为 "LibraryName/AnimName"
	var slash: int = full.rfind("/")
	if slash >= 0 and slash + 1 < full.length():
		return full.substr(slash + 1)
	return full


static func _is_combat_anim_name(low: String) -> bool:
	return (
		low.begins_with("attack")
		or low.begins_with("spell")
		or low.begins_with("death")
		or low.begins_with("decay")
		or low.begins_with("dissipate")
		or low.begins_with("birth")
		or low.begins_with("morph")
	)


static func _is_skeletal_motion(anim: Animation) -> bool:
	if anim == null or anim.length < 0.05:
		return false
	var move_tracks: int = 0
	for ti: int in range(anim.get_track_count()):
		var tt: Animation.TrackType = anim.track_get_type(ti)
		if tt == Animation.TYPE_POSITION_3D or tt == Animation.TYPE_ROTATION_3D:
			move_tracks += 1
			if move_tracks >= _MIN_SKELETAL_TRACKS:
				return true
	return false


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found:
			return found
	return null


## 优先播 Stand（及 Stand -1 等变体），否则空闲回退；循环。
## random_phase：多实例错开相位，避免蝙蝠/鸟群齐刷刷扑翅。
static func autoplay_stand(root: Node, random_phase: bool = true) -> bool:
	if root == null:
		return false
	var ap: AnimationPlayer = _find_animation_player(root)
	if ap == null:
		return false
	# 节点已入树时写 autoplay 无效果且会警告；直接 stop + play 即可盖掉 GLTF 默认轨。
	ap.stop()
	var chosen: String = _pick_stand_name(ap)
	if chosen.is_empty():
		chosen = _pick_idle_fallback(ap)
	if chosen.is_empty():
		return false
	if not play_animation(root, chosen, true):
		return false
	if random_phase and not str(ap.current_animation).is_empty():
		var anim_len: float = ap.current_animation_length
		if anim_len > 0.05:
			ap.seek(randf() * anim_len, true)
	return true


## 模型上全部动画名（含 Death / Birth 等；不限骨骼 Stand）。
static func list_animations(root: Node, _for_preview: bool = false) -> PackedStringArray:
	var ap: AnimationPlayer = _find_animation_player(root)
	if ap == null:
		return PackedStringArray()
	return ap.get_animation_list()


## 播放指定动画；loop=true 时强制线性循环（预览用）。
static func play_animation(root: Node, anim_name: String, loop: bool = true) -> bool:
	if root == null or anim_name.is_empty():
		return false
	var ap: AnimationPlayer = _find_animation_player(root)
	if ap == null or not ap.has_animation(anim_name):
		return false
	ap.active = true
	var anim: Animation = ap.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = (
			Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		)
	ap.play(anim_name)
	return true
