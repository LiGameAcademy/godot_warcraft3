class_name UnitVisual
extends Node


## 地面单位表现组件：Stance（姿态）× Activity（活动）驱动 Sequence。
## 挂在单位根节点上；Navigator / Harvest / Build 只调本 API。
## 命名与播放走 AnimSequenceResolver / AnimPlayback。
## 农民施工锤由 bake（export_model_scenes Stand_Work* 轨修复）保证，本组件不再改骨/改轨。
## Carry 与 AnimSequenceResolver.Stance 的 DEFAULT/GOLD/LUMBER 同值，便于旧调用。

const _TAG := "UnitVisual"

## 负资源姿态。
enum Carry {
	NONE = 0, ## 无。
	GOLD = 1, ## 金矿。
	LUMBER = 2, ## 木材。
}

# Walk↔Stand 交叉淡入（秒）。
const BLEND_TO_WALK := 0.2 ## 行走淡入。
const BLEND_TO_STAND := 0.28 ## 站立淡入。
const BLEND_CARRY_SWITCH := 0.0 ## 负资源姿态切换淡入。

var _cache: MapModelCache = null ## 模型缓存。
var _ap: AnimationPlayer = null ## 动画播放器。
var _stance: int = AnimSequenceResolver.Stance.DEFAULT ## 姿态。
var _moving: bool = false ## 是否移动。
var _chopping: bool = false ## 是否砍伐。
var _combat_attack: bool = false ## 是否战斗出手。
var _building_work: bool = false ## 是否施工。
var _logical: String = "" ## 逻辑名。
var _activity: int = AnimSequenceResolver.Activity.IDLE ## 活动。
var _soft_loop = null ## 软循环。


## 绑定模型缓存。
func bind_cache(cache: MapModelCache) -> void:
	_cache = cache


## 绑定动画播放器（推荐在刷单位时传入）；未绑定则首次播放时查找并缓存。
func bind_animation_player(ap: AnimationPlayer) -> void:
	_ap = ap
	var body := _host()
	if body != null:
		AnimPlayback.bind_animation_player(body, ap)


## 获取软循环。
func _get_soft_loop():
	if _soft_loop == null:
		_soft_loop = AnimSoftLoop.new()
	return _soft_loop


func _animation_player() -> AnimationPlayer:
	if _ap != null and is_instance_valid(_ap):
		return _ap
	var body := _host()
	if body == null:
		return null
	_ap = AnimPlayback.find_animation_player(body)
	return _ap


## 是否移动动画。
func is_moving_anim() -> bool:
	return _moving


## 获取负资源姿态（= Stance）。
func get_carry() -> int:
	return _stance


## 获取姿态。
func get_stance() -> int:
	return _stance


## 是否砍伐。
func is_chopping() -> bool:
	return _chopping


## 设置负资源姿态（金袋 / 木材）。force=true：即使未变也重播。
func set_carry(carry: int, force: bool = false) -> void:
	set_stance(carry, force)


## 设置姿态。
func set_stance(stance: int, force: bool = false) -> void:
	var want := _sequence_for(_current_activity(), stance)
	if not force and _stance == stance and _logical == want and not _logical.is_empty():
		return
	var stance_changed := _stance != stance
	_stance = stance
	_logical = ""
	if _chopping or _building_work or _combat_attack:
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"set_stance=%s 延迟（chop/work/attack）" % stance
		)
		return
	var blend := BLEND_CARRY_SWITCH if stance_changed or force else (
		BLEND_TO_WALK if _moving else BLEND_TO_STAND
	)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"set_stance=%s force=%s blend=%.2f" % [stance, force, blend]
	)
	_play_current(blend)


## 设置移动。
func set_locomotion(moving: bool) -> void:
	if (_chopping or _building_work or _combat_attack) and moving:
		_chopping = false
		_building_work = false
		_combat_attack = false
		_logical = ""
	elif _chopping or _building_work or _combat_attack:
		# 砍伐 / 施工 / 战斗出手中：只记移动态，不抢播 Walk/Stand。
		_moving = moving
		return
	var activity := (
		AnimSequenceResolver.Activity.MOVE if moving
		else AnimSequenceResolver.Activity.IDLE
	)
	var want := _sequence_for(activity, _stance)
	if _moving == moving and _logical == want and not _logical.is_empty():
		return
	_moving = moving
	var blend := BLEND_TO_WALK if moving else BLEND_TO_STAND
	if _stance != AnimSequenceResolver.Stance.DEFAULT:
		blend = minf(blend, 0.05)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"set_locomotion moving=%s blend=%.2f" % [moving, blend]
	)
	_play_current(blend)


## 设置施工（仅切换 Activity → Stand Work*；锤子可见性由 bake 轨保证）。
func set_building_work(active: bool) -> void:
	if active:
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "set_building_work=true stance=%s" % _stance)
		_chopping = false
		_building_work = true
		_moving = false
		_logical = ""
		_play_current(0.1)
	else:
		if not _building_work and _activity != AnimSequenceResolver.Activity.WORK:
			return
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "set_building_work=false")
		_building_work = false
		if _activity == AnimSequenceResolver.Activity.WORK:
			_logical = ""
			_play_current(BLEND_TO_STAND)


## 设置砍伐。
func set_chopping(active: bool) -> void:
	if _chopping == active:
		if active and _activity == AnimSequenceResolver.Activity.ATTACK:
			return
		if not active:
			return
	_chopping = active
	AppLog.debug(AppLog.Layer.PRESENT, _TAG, "set_chopping=%s" % active)
	if active:
		_combat_attack = false
		_moving = false
		_logical = ""
		_play_current(0.08)
	else:
		_logical = ""
		_play_current(BLEND_TO_WALK if _moving else BLEND_TO_STAND)


## 战斗出手动画（非伐木）。
func set_combat_attack(active: bool) -> void:
	if _combat_attack == active:
		if active and _activity == AnimSequenceResolver.Activity.ATTACK:
			return
		if not active:
			return
	_combat_attack = active
	if active:
		_chopping = false
		_moving = false
		_logical = ""
		_play_current(0.08)
	else:
		_logical = ""
		_play_current(BLEND_TO_WALK if _moving else BLEND_TO_STAND)


## 获取当前活动。
func _current_activity() -> int:
	if _chopping or _combat_attack:
		return AnimSequenceResolver.Activity.ATTACK
	if _building_work:
		return AnimSequenceResolver.Activity.WORK
	if _moving:
		return AnimSequenceResolver.Activity.MOVE
	return AnimSequenceResolver.Activity.IDLE


## 获取播放用姿态（砍伐强制 Lumber）。
func _play_stance() -> int:
	if _chopping:
		return AnimSequenceResolver.Stance.LUMBER
	return _stance


## 获取序列名。
func _sequence_for(activity: int, stance: int) -> String:
	return AnimSequenceResolver.sequence_name_underscored(activity, stance)


## 播放当前序列。
func _play_current(blend: float) -> void:
	var body := _host()
	if body == null:
		return
	var activity := _current_activity()
	var stance := _play_stance()
	var logical := AnimSequenceResolver.sequence_name(activity, stance)
	var fallbacks: Array = []
	if activity == AnimSequenceResolver.Activity.ATTACK and stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append("Attack")
	elif stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append(AnimSequenceResolver.activity_base(activity))
	if activity == AnimSequenceResolver.Activity.WORK and stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append("Stand Work")
		fallbacks.append("Stand_Work")
	if activity == AnimSequenceResolver.Activity.MOVE and stance == AnimSequenceResolver.Stance.DEFAULT:
		var walk_fb := _resolve_walk_prefix(body)
		if not walk_fb.is_empty():
			fallbacks.append(walk_fb)
	if activity == AnimSequenceResolver.Activity.IDLE:
		fallbacks.append("Stand")

	var ap := _animation_player()
	var played := AnimPlayback.play_logical(
		body, logical, blend, _cache, activity, fallbacks, ap
	)
	if not bool(played.get("ok", false)):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"play 失败 logical=%s activity=%s stance=%s" % [logical, activity, stance]
		)
		if activity == AnimSequenceResolver.Activity.IDLE:
			_play_stand_fallback(body, blend)
		return

	_activity = activity
	_logical = str(played.get("played_as", logical.replace(" ", "_")))
	var resolved := str(played.get("resolved", ""))
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"play ok logical=%s → %s activity=%s stance=%s ping=%s"
		% [logical, _logical, activity, stance, bool(played.get("ping_pong", false))]
	)
	if bool(played.get("ping_pong", false)) and not resolved.is_empty() and ap != null:
		_get_soft_loop().begin(ap, resolved, _soft_loop_should_continue)
	else:
		if _soft_loop != null:
			_soft_loop.clear()
	# Work / 负资源：立刻定格 geosetvis（斧/金袋/木材），避免沿用上一动画末帧显隐
	if _cache != null and _cache.has_method("snap_geoset_visibility_for"):
		if (
			activity == AnimSequenceResolver.Activity.WORK
			or stance == AnimSequenceResolver.Stance.GOLD
			or stance == AnimSequenceResolver.Stance.LUMBER
		):
			_cache.call("snap_geoset_visibility_for", body, resolved if not resolved.is_empty() else _logical)


## 软循环是否继续。
func _soft_loop_should_continue() -> bool:
	if _moving or _building_work or _chopping:
		return false
	return AnimSequenceResolver.needs_ping_pong(
		AnimSequenceResolver.sequence_name(AnimSequenceResolver.Activity.IDLE, _stance)
	)


## 获取主机。
func _host() -> Node3D:
	return get_parent() as Node3D


func _play_stand_fallback(body: Node, blend: float) -> void:
	var ap := _animation_player()
	var resolved := AnimPlayback.resolve(body, "Stand", ap)
	if resolved.is_empty() and _cache != null:
		var names := _cache.list_animations(body)
		for n in names:
			var leaf := AnimPlayback.anim_leaf(str(n)).to_lower()
			if leaf == "stand" or leaf.begins_with("stand"):
				if leaf.contains("work") or leaf.contains("upgrade") or leaf.contains("ready"):
					continue
				if leaf.contains("gold") or leaf.contains("lumber"):
					continue
				resolved = str(n)
				break
	if resolved.is_empty():
		AppLog.warn(AppLog.Layer.PRESENT, _TAG, "Stand fallback 也失败")
		return
	var played := AnimPlayback.play(body, resolved, blend, _cache, -1, ap)
	if bool(played.get("ok", false)):
		_activity = AnimSequenceResolver.Activity.IDLE
		_logical = "Stand"
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "Stand fallback → %s" % resolved)
		Wc3Pe2Particles.apply_sequence(body, "Stand")
		if _soft_loop != null:
			_soft_loop.clear()


func _resolve_walk_prefix(body: Node) -> String:
	if _cache == null:
		return ""
	var names := _cache.list_animations(body)
	for n in names:
		var leaf := AnimPlayback.anim_leaf(str(n)).to_lower()
		if not leaf.begins_with("walk"):
			continue
		if leaf.contains("attack") or leaf.contains("death") or leaf.contains("spell"):
			continue
		if leaf.contains("gold") or leaf.contains("lumber"):
			continue
		return str(n)
	return ""
