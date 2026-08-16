class_name AnimPlayback
extends RefCounted

## 动画解析与播放：空格/`_` 名解析、loop / ping-pong 策略、PE2。
## 无单位业务态；UnitVisual / BuildingVisual 调用本层。
##
## AnimationPlayer：**优先由调用方注入**（UnitVisual 缓存）；未传时才查找。
## 查找仅作冷路径回退（建筑 apply_phase、一次性工具），勿在每帧热路径依赖。

const _TAG := "AnimPlayback"

## 回退查找：root 自身或子树中第一个 AnimationPlayer（冷路径）。
## 命中后写入 root meta，同节点再次查找 O(1)。
const META_ANIM_PLAYER := &"wc3_animation_player"


static func find_animation_player(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n as AnimationPlayer
	if n.has_meta(META_ANIM_PLAYER):
		var cached: Variant = n.get_meta(META_ANIM_PLAYER)
		if cached is AnimationPlayer and is_instance_valid(cached):
			return cached as AnimationPlayer
		n.remove_meta(META_ANIM_PLAYER)
	var found: Array[Node] = n.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"find_animation_player 未找到 host=%s" % str(n.name)
		)
		return null
	var ap := found[0] as AnimationPlayer
	n.set_meta(META_ANIM_PLAYER, ap)
	return ap


static func bind_animation_player(host: Node, ap: AnimationPlayer) -> void:
	if host == null:
		return
	if ap == null or not is_instance_valid(ap):
		if host.has_meta(META_ANIM_PLAYER):
			host.remove_meta(META_ANIM_PLAYER)
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "bind 清除 host=%s" % str(host.name))
		return
	host.set_meta(META_ANIM_PLAYER, ap)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"bind host=%s ap=%s" % [str(host.name), str(ap.name)]
	)


static func anim_leaf(anim_path: String) -> String:
	var i := anim_path.rfind("/")
	return anim_path.substr(i + 1) if i >= 0 else anim_path


## 在 AnimationPlayer 中解析「Stand Upgrade First」↔「Stand_Upgrade_First」。
## `ap` 已注入则不再查找；否则在 root 下回退查找。
static func resolve(
	root: Node, logical_name: String, ap: AnimationPlayer = null
) -> String:
	if logical_name.is_empty():
		return ""
	if ap == null:
		ap = find_animation_player(root)
	if ap == null:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"resolve 无 AnimationPlayer logical=%s root=%s"
			% [logical_name, str(root.name) if root else "null"]
		)
		return ""
	var candidates: Array[String] = [
		logical_name,
		logical_name.replace(" ", "_"),
		logical_name.replace(" ", ""),
	]
	if logical_name.contains("_"):
		candidates.append(logical_name.replace("_", " "))
	var names := ap.get_animation_list()
	for cand in candidates:
		var cand_l := cand.to_lower()
		for n in names:
			var leaf := anim_leaf(str(n))
			if leaf == cand or leaf.to_lower() == cand_l:
				return str(n)
	var want_l := logical_name.to_lower().strip_edges()
	if want_l == "stand":
		for n in names:
			var leaf2 := anim_leaf(str(n)).to_lower()
			if leaf2 == "stand":
				return str(n)
			if not leaf2.begins_with("stand"):
				continue
			if (
				leaf2.begins_with("stand_work")
				or leaf2.begins_with("standwork")
				or leaf2.contains("upgrade")
				or leaf2.contains("ready")
				or leaf2.contains("channel")
				or leaf2.contains("hit")
			):
				continue
			return str(n)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"resolve 未匹配 logical=%s（已试 %s）" % [logical_name, str(candidates)]
	)
	return ""


## 按 activity+stance 解析；失败时按回退链再试。
static func resolve_activity(
	root: Node,
	activity: int,
	stance: int = 0,
	fallbacks: Array = [],
	ap: AnimationPlayer = null
) -> Dictionary:
	var logical: String = AnimSequenceResolver.sequence_name(activity, stance)
	var resolved := resolve(root, logical, ap)
	var played_as := logical.replace(" ", "_")
	if resolved.is_empty():
		for fb in fallbacks:
			var name := str(fb)
			resolved = resolve(root, name, ap)
			if not resolved.is_empty():
				played_as = name.replace(" ", "_")
				logical = name.replace("_", " ")
				break
	return {
		"ok": not resolved.is_empty(),
		"resolved": resolved,
		"logical": logical,
		"played_as": played_as,
	}


## 播放已解析动画名。ping-pong 序列强制 LOOP_NONE。
## 返回 { ok, resolved, ping_pong }。`ap` 优先注入。
static func play(
	root: Node,
	anim_name: String,
	blend: float = 0.0,
	cache: Variant = null,
	force_loop: int = -1,
	ap: AnimationPlayer = null
) -> Dictionary:
	var out := {"ok": false, "resolved": anim_name, "ping_pong": false}
	if root == null or anim_name.is_empty():
		return out
	var ping: bool = AnimSequenceResolver.needs_ping_pong(anim_name)
	out["ping_pong"] = ping
	var loop := not ping
	if force_loop == 0:
		loop = false
	elif force_loop == 1:
		loop = true
		ping = false
		out["ping_pong"] = false
	if ap == null:
		ap = find_animation_player(root)
	if ap == null or not ap.has_animation(anim_name):
		if cache != null and cache.has_method("play_animation"):
			out["ok"] = cache.call("play_animation", root, anim_name, loop)
			if bool(out["ok"]):
				AppLog.debug(
					AppLog.Layer.PRESENT,
					_TAG,
					"play via cache anim=%s loop=%s ping=%s" % [anim_name, loop, ping]
				)
			else:
				AppLog.warn(
					AppLog.Layer.PRESENT,
					_TAG,
					"play 失败 anim=%s（无 AP / cache 失败）" % anim_name
				)
		else:
			AppLog.warn(
				AppLog.Layer.PRESENT,
				_TAG,
				"play 失败 anim=%s ap=%s" % [anim_name, ap != null]
			)
		return out
	ap.active = true
	var anim := ap.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = (
			Animation.LOOP_NONE if ping or not loop else Animation.LOOP_LINEAR
		)
	ap.play(anim_name, maxf(blend, 0.0))
	out["ok"] = true
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"play anim=%s blend=%.2f loop=%s ping=%s" % [anim_name, blend, loop, ping]
	)
	return out


## 解析逻辑名并播放；附带 PE2。`ap` 优先注入，整次调用复用。
static func play_logical(
	root: Node,
	logical: String,
	blend: float = 0.0,
	cache: Variant = null,
	activity_hint: int = 0,
	fallbacks: Array = [],
	ap: AnimationPlayer = null
) -> Dictionary:
	if ap == null:
		ap = find_animation_player(root)
	var resolved := resolve(root, logical, ap)
	var played_as := logical.replace(" ", "_")
	if resolved.is_empty():
		for fb in fallbacks:
			resolved = resolve(root, str(fb), ap)
			if not resolved.is_empty():
				played_as = str(fb).replace(" ", "_")
				AppLog.debug(
					AppLog.Layer.PRESENT,
					_TAG,
					"play_logical 回退 logical=%s → %s" % [logical, played_as]
				)
				break
	var out := {
		"ok": false,
		"resolved": resolved,
		"played_as": played_as,
		"ping_pong": false,
	}
	if resolved.is_empty():
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"play_logical 无可用动画 logical=%s fallbacks=%s"
			% [logical, str(fallbacks)]
		)
		return out
	var played := play(root, resolved, blend, cache, -1, ap)
	out["ok"] = bool(played.get("ok", false))
	out["ping_pong"] = bool(played.get("ping_pong", false))
	if out["ok"]:
		Wc3Pe2Particles.apply_sequence(
			root, AnimSequenceResolver.pe2_hint(played_as.replace("_", " "), activity_hint)
		)
	return out
