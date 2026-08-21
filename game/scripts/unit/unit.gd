class_name Unit
extends Node3D

## 单位实体根：玩法入口 + Stance×Activity → 模型门面播放。
##
## ## 树形
## ```
## Unit（本脚本）
## ├── Model（Wc3ModelScene / 占位）
## ├── UnitNavigator / Controllers…
## └── Selectable / …
## ```
##
## ## 分层
## - Navigator / Harvest / Combat / Build 调本 API（或 `Unit.of(body)`）。
## - 实际播动画优先走子节点 [Wc3ModelScene] → [Wc3AnimPlayer]；无门面时回退 [AnimPlayback]。
## - 命名规则见 [AnimSequenceResolver]。
##
## ## 职责边界
## - **做**：meta/`unit_data` 宿主、负资源/顶盾姿态、移动/砍伐/出手/施工/死亡→尸体链、`corpse_expired`。
## - **不做**：翻子树找 Mesh/挂点；扣血；技能数值。挂点请 `Wc3ModelScene.find_socket`。
##
## 农民施工锤由 bake（`Stand_Work*` 轨）保证，本组件不再改骨/改轨。
## Carry 与 Stance 的 DEFAULT/GOLD/LUMBER 同值，便于旧调用。

const _TAG := "Unit"
## 子节点名：bake `.scn` / GLB 实例或占位网格。
const MODEL_NODE_NAME := "Model"

## 无 Decay 序列时的尸体停留（有 Decay Flesh/Bone 则用动画片长）。
const CORPSE_LINGER_SEC := 8.0
## Death 若未 finished，按片长 + 裕量强制进 Decay。
const DEATH_ANIM_FALLBACK_SEC := 4.0
## 尸体链：Death → Decay Flesh → Decay Bone。
const _CORPSE_NONE := 0
const _CORPSE_DEATH := 1
const _CORPSE_FLESH := 2
const _CORPSE_BONE := 3
const _CORPSE_DONE := 4

## 尸体停留结束，应由 Director 走 MapLoader.remove_unit_instance；无订阅则 queue_free。
signal corpse_expired(unit: Node3D)

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
var _ap: AnimationPlayer = null ## 动画播放器（优先 Wc3AnimPlayer）。
var _model: Wc3ModelScene = null ## bake 模型门面缓存。
var _stance: int = AnimSequenceResolver.Stance.DEFAULT ## 姿态。
var _moving: bool = false ## 是否移动。
var _chopping: bool = false ## 是否砍伐。
var _combat_attack: bool = false ## 是否战斗出手。
var _dying: bool = false ## 是否死亡表现（Death → Decay）。
var _corpse_phase: int = _CORPSE_NONE ## 尸体链阶段。
var _corpse_watch_id: int = 0 ## 阶段切换时作废旧 timeout。
var _played_any_decay: bool = false ## 是否已播过 Flesh/Bone。
var _building_work: bool = false ## 是否施工。
var _logical: String = "" ## 逻辑名。
var _activity: int = AnimSequenceResolver.Activity.IDLE ## 活动。
var _soft_loop = null ## 软循环。


func _ready() -> void:
	set_process(false)


## 绑定模型缓存。
func bind_cache(cache: MapModelCache) -> void:
	_cache = cache


## 绑定动画播放器（推荐在刷单位时传入）；未绑定则首次播放时经 Wc3ModelScene / 查找缓存。
func bind_animation_player(ap: AnimationPlayer) -> void:
	_ap = ap
	var body := _host()
	if body != null:
		AnimPlayback.bind_animation_player(body, ap)
	var model := _model_scene()
	if model != null:
		model.bind_animation_player(ap)


## 从任意节点解析所属 Unit（自身 / 父 / 旧式 UnitVisual 子节点兼容已移除）。
static func of(node: Node) -> Unit:
	if node == null:
		return null
	if node is Unit:
		return node as Unit
	var p := node.get_parent()
	if p is Unit:
		return p as Unit
	return null


## 表现子节点（`Model`），无则回退 `Wc3ModelScene.find_on`。
func model_node() -> Node3D:
	var named := get_node_or_null(MODEL_NODE_NAME) as Node3D
	if named != null:
		return named
	var scene := _model_scene()
	return scene


## bake 模型门面；在子树中查找 .scn 根。
func _model_scene() -> Wc3ModelScene:
	if _model != null and is_instance_valid(_model):
		return _model
	_model = Wc3ModelScene.find_on(self)
	return _model


## 获取软循环。
func _get_soft_loop():
	if _soft_loop == null:
		_soft_loop = AnimSoftLoop.new()
	return _soft_loop


func _animation_player() -> AnimationPlayer:
	if _ap != null and is_instance_valid(_ap):
		return _ap
	var model := _model_scene()
	if model != null:
		_ap = model.animation_player()
		if _ap != null:
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
	if _dying or _chopping or _building_work or _combat_attack:
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"set_stance=%s 延迟（die/chop/work/attack）" % stance
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
	if _dying:
		return
	# 战斗出手中：不因 Navigator 抖动打断 Attack（首刀进距时常先 stop 再残留 moving=true）。
	if _combat_attack:
		_moving = moving
		return
	if (_chopping or _building_work) and moving:
		_chopping = false
		_building_work = false
		_logical = ""
	elif _chopping or _building_work:
		# 砍伐 / 施工中：只记移动态，不抢播 Walk/Stand。
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
	if _dying:
		return
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
	if _dying:
		return
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


## 死亡表现：Death → 完整播 Decay Flesh → Decay Bone（片长=尸体停留），然后移除。
func play_death() -> void:
	if _dying:
		return
	_dying = true
	_corpse_phase = _CORPSE_DEATH
	_played_any_decay = false
	_combat_attack = false
	_chopping = false
	_building_work = false
	_moving = false
	_logical = ""
	if _soft_loop != null:
		_soft_loop.clear()
	var body := _host()
	var ap := _animation_player()
	if ap != null:
		ap.active = true
		if ap.speed_scale < 1.0:
			ap.speed_scale = 1.0
	if body != null:
		var nav := body.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
	_play_current(0.0)
	if _activity != AnimSequenceResolver.Activity.DEATH:
		enter_corpse_state()
		return
	_connect_corpse_finished()
	set_process(true)
	_arm_corpse_watch(DEATH_ANIM_FALLBACK_SEC)


func _connect_corpse_finished() -> void:
	var ap := _animation_player()
	if ap == null:
		return
	if not ap.animation_finished.is_connected(_on_corpse_anim_finished):
		ap.animation_finished.connect(_on_corpse_anim_finished)


func _disconnect_corpse_finished() -> void:
	var ap := _animation_player()
	if ap == null:
		return
	if ap.animation_finished.is_connected(_on_corpse_anim_finished):
		ap.animation_finished.disconnect(_on_corpse_anim_finished)


func _anim_leaf_key(anim: StringName) -> String:
	return AnimPlayback.compact_seq_name(str(anim))


func _is_death_clip(anim: StringName) -> bool:
	if str(anim).is_empty():
		return true
	var leaf := _anim_leaf_key(anim)
	if leaf.begins_with("decay"):
		return false
	return leaf.begins_with("death") or leaf.begins_with("dissipate")


func _is_decay_flesh_clip(anim: StringName) -> bool:
	var leaf := _anim_leaf_key(anim)
	if leaf.contains("bone"):
		return false
	return leaf.begins_with("decay")


func _is_decay_bone_clip(anim: StringName) -> bool:
	var leaf := _anim_leaf_key(anim)
	return leaf.begins_with("decay") and leaf.contains("bone")


func _scene_tree() -> SceneTree:
	var t := get_tree()
	if t != null:
		return t
	return Engine.get_main_loop() as SceneTree


func _arm_corpse_watch(min_wait: float) -> void:
	_corpse_watch_id += 1
	var id := _corpse_watch_id
	var ap := _animation_player()
	var wait := min_wait
	if ap != null:
		wait = maxf(wait, ap.current_animation_length + 0.35)
	var tree := _scene_tree()
	if tree == null:
		return
	tree.create_timer(wait).timeout.connect(
		func() -> void:
			if id != _corpse_watch_id:
				return
			_advance_corpse_phase()
	)


func _process(_delta: float) -> void:
	if not _dying or _corpse_phase == _CORPSE_DONE or _corpse_phase == _CORPSE_NONE:
		set_process(false)
		return
	var ap := _animation_player()
	if ap == null:
		_advance_corpse_phase()
		return
	var cur := StringName(ap.current_animation)
	if not _clip_matches_phase(cur):
		return
	var alen := ap.current_animation_length
	var pos := ap.current_animation_position
	if ap.is_playing() and alen > 0.0 and pos < alen - 0.05:
		return
	# 刚切到新片时 seek(0) 可能尚未标 playing；未到片尾不要跳阶段。
	if (not ap.is_playing()) and alen > 0.0 and pos < alen - 0.05:
		return
	_advance_corpse_phase()


func _clip_matches_phase(anim: StringName) -> bool:
	match _corpse_phase:
		_CORPSE_DEATH:
			return _is_death_clip(anim)
		_CORPSE_FLESH:
			return _is_decay_flesh_clip(anim)
		_CORPSE_BONE:
			return _is_decay_bone_clip(anim)
		_:
			return false


func _on_corpse_anim_finished(anim: StringName) -> void:
	if not _dying or _corpse_phase == _CORPSE_DONE:
		return
	if not _clip_matches_phase(anim):
		return
	_advance_corpse_phase()


func _advance_corpse_phase() -> void:
	match _corpse_phase:
		_CORPSE_DEATH:
			enter_corpse_state()
		_CORPSE_FLESH:
			enter_decay_bone()
		_CORPSE_BONE:
			_finish_corpse()
		_:
			pass


## Death 播完 → 完整播放 Decay Flesh（尸体 Geoset 在此序列，勿定格）。
func enter_corpse_state() -> void:
	if not _dying:
		_dying = true
	if _corpse_phase >= _CORPSE_FLESH:
		return
	_corpse_phase = _CORPSE_FLESH
	if _play_decay_clip(["Decay Flesh", "Decay_Flesh", "DecayFlesh", "Decay"]):
		return
	enter_decay_bone()


## Decay Flesh 播完 → Decay Bone（片长即骨架停留；无此片则结束）。
func enter_decay_bone() -> void:
	if not _dying:
		return
	if _corpse_phase >= _CORPSE_BONE:
		return
	_corpse_phase = _CORPSE_BONE
	if _play_decay_clip(["Decay Bone", "Decay_Bone", "DecayBone"]):
		return
	_finish_corpse()


func _play_decay_clip(logical_names: Array) -> bool:
	var body := _host()
	if body == null:
		return false
	var ap := _animation_player()
	if ap != null:
		ap.speed_scale = 1.0
	var resolved := ""
	for name_v in logical_names:
		resolved = AnimPlayback.resolve(body, str(name_v), ap)
		if not resolved.is_empty():
			break
	if resolved.is_empty():
		return false
	var played := AnimPlayback.play(body, resolved, 0.0, _cache, 0, ap)
	if not bool(played.get("ok", false)):
		return false
	_played_any_decay = true
	_logical = AnimPlayback.anim_leaf(resolved).replace(" ", "_")
	if _cache != null:
		_cache.snap_geoset_visibility_for(body, resolved, 0.0)
	Wc3Pe2Particles.apply_sequence(body, AnimPlayback.anim_leaf(resolved).replace("_", " "))
	_connect_corpse_finished()
	set_process(true)
	_arm_corpse_watch(0.35)
	return true


func _finish_corpse() -> void:
	if _corpse_phase == _CORPSE_DONE:
		return
	_corpse_phase = _CORPSE_DONE
	_corpse_watch_id += 1
	set_process(false)
	_disconnect_corpse_finished()
	if _played_any_decay:
		_remove_corpse()
		return
	_schedule_corpse_remove()


func _schedule_corpse_remove() -> void:
	var tree := _scene_tree()
	if tree == null:
		_remove_corpse()
		return
	tree.create_timer(CORPSE_LINGER_SEC).timeout.connect(_remove_corpse)


func _remove_corpse() -> void:
	var body := _host()
	if body == null or not is_instance_valid(body):
		return
	if corpse_expired.get_connections().size() > 0:
		corpse_expired.emit(body)
		return
	body.queue_free()


## 战斗出手动画（非伐木）。
func set_combat_attack(active: bool) -> void:
	if _dying:
		return
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
		# 从 Walk 切入时 blend>0 会「揉」成怪姿；首刀必须硬切 Attack
		_play_current(0.0)
	else:
		_logical = ""
		_play_current(BLEND_TO_WALK if _moving else BLEND_TO_STAND)


## 获取当前活动。
func _current_activity() -> int:
	if _dying:
		return AnimSequenceResolver.Activity.DEATH
	if _chopping or _combat_attack:
		return AnimSequenceResolver.Activity.ATTACK
	if _building_work:
		return AnimSequenceResolver.Activity.WORK
	if _moving:
		return AnimSequenceResolver.Activity.MOVE
	return AnimSequenceResolver.Activity.IDLE


## 获取播放用姿态（砍伐强制 Lumber；死亡用默认 Death，无 Death Defend）。
func _play_stance() -> int:
	if _dying:
		return AnimSequenceResolver.Stance.DEFAULT
	if _chopping:
		return AnimSequenceResolver.Stance.LUMBER
	return _stance


## 获取序列名。
func _sequence_for(activity: int, stance: int) -> String:
	return AnimSequenceResolver.sequence_name_underscored(activity, stance)


## 播放当前序列（策略 → 逻辑名 → Wc3ModelScene / AnimPlayback）。
func _play_current(blend: float) -> void:
	var body := _host()
	if body == null:
		return
	var activity := _current_activity()
	var stance := _play_stance()
	var logical := AnimSequenceResolver.sequence_name(activity, stance)
	var fallbacks: Array = []
	if activity == AnimSequenceResolver.Activity.DEATH:
		fallbacks.append("Death")
		fallbacks.append("Dissipate")
	elif activity == AnimSequenceResolver.Activity.ATTACK and stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append("Attack")
	elif stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append(AnimSequenceResolver.activity_base(activity))
	if activity == AnimSequenceResolver.Activity.WORK and stance != AnimSequenceResolver.Stance.DEFAULT:
		fallbacks.append("Stand Work")
		fallbacks.append("Stand_Work")
		fallbacks.append("StandWork")
	if activity == AnimSequenceResolver.Activity.MOVE and stance == AnimSequenceResolver.Stance.DEFAULT:
		var walk_fb := _resolve_walk_prefix(body)
		if not walk_fb.is_empty():
			fallbacks.append(walk_fb)
	if activity == AnimSequenceResolver.Activity.IDLE:
		fallbacks.append("Stand")

	var model := _model_scene()
	var ap := _animation_player()
	var played: Dictionary
	if model != null:
		played = model.play_logical(logical, blend, _cache, activity, fallbacks)
	else:
		played = AnimPlayback.play_logical(
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
	# Work / 负资源：立刻定格 geosetvis（斧/金袋/木材）。Death 交给动画轨，结束再定格 Decay。
	var snap_root: Node = model if model != null else body
	if _cache != null and _cache.has_method("snap_geoset_visibility_for"):
		if (
			activity == AnimSequenceResolver.Activity.WORK
			or stance == AnimSequenceResolver.Stance.GOLD
			or stance == AnimSequenceResolver.Stance.LUMBER
		):
			_cache.call(
				"snap_geoset_visibility_for",
				snap_root,
				resolved if not resolved.is_empty() else _logical
			)


## 软循环是否继续。
func _soft_loop_should_continue() -> bool:
	if _moving or _building_work or _chopping:
		return false
	return AnimSequenceResolver.needs_ping_pong(
		AnimSequenceResolver.sequence_name(AnimSequenceResolver.Activity.IDLE, _stance)
	)


## 实体根即自身（原 UnitVisual 挂在模型下时曾用 get_parent）。
func _host() -> Node3D:
	return self


func _play_stand_fallback(body: Node, blend: float) -> void:
	var model := _model_scene()
	var ap := _animation_player()
	var play_root: Node = model if model != null else body
	var resolved := ""
	if model != null:
		resolved = model.resolve_logical("Stand")
	else:
		resolved = AnimPlayback.resolve(body, "Stand", ap)
	if resolved.is_empty() and _cache != null:
		var names := _cache.list_animations(play_root)
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
	var played: Dictionary
	if model != null:
		played = model.play_logical("Stand", blend, _cache, AnimSequenceResolver.Activity.IDLE, [])
	else:
		played = AnimPlayback.play(body, resolved, blend, _cache, -1, ap)
	if bool(played.get("ok", false)):
		_activity = AnimSequenceResolver.Activity.IDLE
		_logical = "Stand"
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "Stand fallback → %s" % resolved)
		Wc3Pe2Particles.apply_sequence(play_root, "Stand")
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
