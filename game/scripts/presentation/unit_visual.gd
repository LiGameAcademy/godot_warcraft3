class_name UnitVisual
extends Node

## 单位移动态表现：Walk ↔ Stand（+ PE2 sequence）。
## 由 GameDirector 挂到单位上。
##
## 为何独立于 UnitNavigator：
## - Navigator 只负责路点/朝向；换动画系统时不应改移动代码。
## - 建筑走 BuildingVisual 阶段机；地面单位走本节点，职责不混。

## Walk↔Stand 交叉淡入（秒）。过短仍像硬切，过长会脚滑。
const BLEND_TO_WALK := 0.2
const BLEND_TO_STAND := 0.28

var _cache: MapModelCache = null
var _moving: bool = false
var _logical: String = ""


func bind_cache(cache: MapModelCache) -> void:
	_cache = cache


func is_moving_anim() -> bool:
	return _moving


## moving=true → Walk；false → Stand。重复调用同态不重播，避免每帧 restart。
func set_locomotion(moving: bool) -> void:
	if _moving == moving and not _logical.is_empty():
		return
	_moving = moving
	if moving:
		_play_logical("Walk", BLEND_TO_WALK)
	else:
		_play_logical("Stand", BLEND_TO_STAND)


func _play_logical(logical: String, blend: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var resolved := BuildingVisual.resolve_animation(body, logical)
	if resolved.is_empty() and logical == "Walk" and _cache != null:
		resolved = _resolve_walk_prefix(body)
	if resolved.is_empty():
		if logical == "Stand":
			_play_stand_fallback(body, blend)
		return
	if _play_with_blend(body, resolved, blend):
		_logical = logical
		Wc3Pe2Particles.apply_sequence(body, logical)


func _play_stand_fallback(body: Node, blend: float) -> void:
	var resolved := BuildingVisual.resolve_animation(body, "Stand")
	if resolved.is_empty() and _cache != null:
		# 与 MapModelCache.autoplay_stand 同源挑选，但走 blend 而非硬切
		var names := _cache.list_animations(body)
		for n in names:
			var leaf := _anim_leaf(str(n)).to_lower()
			if leaf == "stand" or leaf.begins_with("stand"):
				if leaf.contains("work") or leaf.contains("upgrade") or leaf.contains("ready"):
					continue
				resolved = str(n)
				break
	if resolved.is_empty():
		return
	if _play_with_blend(body, resolved, blend):
		_logical = "Stand"
		Wc3Pe2Particles.apply_sequence(body, "Stand")


func _play_with_blend(body: Node, anim_name: String, blend: float) -> bool:
	var ap := _find_animation_player(body)
	if ap == null or not ap.has_animation(anim_name):
		if _cache != null:
			return _cache.play_animation(body, anim_name, true)
		return false
	ap.active = true
	var anim := ap.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	# custom_blend：从当前姿势交叉淡入到目标动画
	ap.play(anim_name, maxf(blend, 0.0))
	return true


## 无精确 Walk 时取叶子名以 walk 开头、且非战斗/死亡的第一条。
func _resolve_walk_prefix(body: Node) -> String:
	if _cache == null:
		return ""
	var names := _cache.list_animations(body)
	for n in names:
		var leaf := _anim_leaf(str(n)).to_lower()
		if not leaf.begins_with("walk"):
			continue
		if leaf.contains("attack") or leaf.contains("death") or leaf.contains("spell"):
			continue
		return str(n)
	return ""


func _anim_leaf(anim_path: String) -> String:
	var i := anim_path.rfind("/")
	return anim_path.substr(i + 1) if i >= 0 else anim_path


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_animation_player(c)
		if f:
			return f
	return null
