class_name UnitVisual
extends Node

## 单位移动态表现：Walk ↔ Stand（+ 负资源 Gold/Lumber 变体 + PE2）。
## 由 GameDirector 挂到单位上。
##
## 为何独立于 UnitNavigator：
## - Navigator 只负责路点/朝向；换动画系统时不应改移动代码。
## - 建筑走 BuildingVisual 阶段机；地面单位走本节点，职责不混。
## - 农民负金时播 Stand_Gold / Walk_Gold，靠 geoset 轨显示背袋。

enum Carry {
	NONE = 0,
	GOLD = 1,
	LUMBER = 2,
}

## Walk↔Stand 交叉淡入（秒）。过短仍像硬切，过长会脚滑。
const BLEND_TO_WALK := 0.2
const BLEND_TO_STAND := 0.28
## 负资源外观切换：必须立刻（金袋 geoset 不能等 blend）。
const BLEND_CARRY_SWITCH := 0.0

var _cache: MapModelCache = null
var _moving: bool = false
var _carry: int = Carry.NONE
var _logical: String = ""
## 伐木站桩：播 Attack Lumber，期间忽略 locomotion
var _chopping: bool = false


func bind_cache(cache: MapModelCache) -> void:
	_cache = cache


func is_moving_anim() -> bool:
	return _moving


func get_carry() -> int:
	return _carry


func is_chopping() -> bool:
	return _chopping


## 切换负资源外观（金袋 / 木材）。强制重播当前位移态对应动画。
## force=true：即使状态未变也重播（出矿/交货瞬间）。
func set_carry(carry: int, force: bool = false) -> void:
	var want := _logical_for(_moving, carry)
	# 仅当「已声称的 carry」且「实际播到的逻辑名」都匹配才跳过；
	# 避免 Gold 回退成 Walk 后把 _logical 卡死、金袋永远不刷。
	if not force and _carry == carry and _logical == want and not _logical.is_empty():
		return
	var carry_changed := _carry != carry
	_carry = carry
	_logical = ""
	if _chopping:
		# 砍伐中只更新 carry 状态，动画仍由 Attack Lumber 主导
		return
	# 负资源开/关：0 blend，否则走路几步才看到金袋/空手
	var blend := BLEND_CARRY_SWITCH if carry_changed or force else (
		BLEND_TO_WALK if _moving else BLEND_TO_STAND
	)
	_play_logical(_logical_for(_moving, _carry), blend)


## moving=true → Walk[_Gold|_Lumber]；false → Stand[…]。同态不重播。
func set_locomotion(moving: bool) -> void:
	# 位移必须打断砍伐姿态，否则会「边播 Attack Lumber 边走路」
	if _chopping and moving:
		_chopping = false
		_logical = ""
	elif _chopping:
		_moving = moving
		return
	var want := _logical_for(moving, _carry)
	if _moving == moving and _logical == want and not _logical.is_empty():
		return
	_moving = moving
	# 负资源态下切 Walk/Stand 也尽量短，避免金袋晚一拍
	var blend := BLEND_TO_WALK if moving else BLEND_TO_STAND
	if _carry != Carry.NONE:
		blend = minf(blend, 0.05)
	_play_logical(want, blend)


## 建造站桩：播 Stand Work（人族施工）。结束时恢复 Stand/Walk。
func set_building_work(active: bool) -> void:
	if active:
		_chopping = false
		_moving = false
		_logical = ""
		_play_logical("Stand_Work", 0.1)
		if _logical != "Stand_Work" and _logical != "Stand Work":
			var body := get_parent() as Node3D
			var resolved := BuildingVisual.resolve_animation(body, "Stand Work")
			if not resolved.is_empty() and _play_with_blend(body, resolved, 0.1):
				_logical = "Stand Work"
	else:
		if _logical == "Stand_Work" or _logical == "Stand Work":
			_logical = ""
			_play_logical(_logical_for(_moving, _carry), BLEND_TO_STAND)


## 伐木站桩：播 Attack Lumber（回退 Attack）。结束时恢复 Walk/Stand。
## 已在砍伐中再次 set(true)：保持循环（多击攒木），不打断。
func set_chopping(active: bool) -> void:
	if _chopping == active:
		if active and (_logical == "Attack_Lumber" or _logical == "Attack"):
			return
		if not active:
			return
	_chopping = active
	if active:
		_moving = false
		_logical = ""
		_play_logical("Attack_Lumber", 0.08)
	else:
		_logical = ""
		_play_logical(_logical_for(_moving, _carry), BLEND_TO_WALK if _moving else BLEND_TO_STAND)


func _logical_for(moving: bool, carry: int) -> String:
	var base := "Walk" if moving else "Stand"
	match carry:
		Carry.GOLD:
			return "%s_Gold" % base
		Carry.LUMBER:
			return "%s_Lumber" % base
		_:
			return base


func _play_logical(logical: String, blend: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var resolved := BuildingVisual.resolve_animation(body, logical)
	# Stand_Gold / Walk_Gold / Attack_Lumber 等：再试空格写法
	if resolved.is_empty() and logical.contains("_"):
		resolved = BuildingVisual.resolve_animation(body, logical.replace("_", " "))
	if resolved.is_empty() and logical == "Walk" and _cache != null:
		resolved = _resolve_walk_prefix(body)
	var played_as := logical
	if resolved.is_empty():
		if logical == "Attack_Lumber":
			resolved = BuildingVisual.resolve_animation(body, "Attack")
			played_as = "Attack"
		# 负资源动画缺失时回退空手，避免完全不动；勿把 _logical 标成 Gold（否则再也刷不回金袋）
		elif logical.ends_with("_Gold") or logical.ends_with("_Lumber"):
			var fallback := "Walk" if _moving else "Stand"
			resolved = BuildingVisual.resolve_animation(body, fallback)
			played_as = fallback
		if resolved.is_empty() and logical.begins_with("Stand"):
			_play_stand_fallback(body, blend)
			return
		if resolved.is_empty():
			return
	if _play_with_blend(body, resolved, blend):
		_logical = played_as
		# PE2：优先完整逻辑名，失败时用手空态
		var pe2 := played_as
		if pe2.begins_with("Attack"):
			pe2 = "Attack"
		elif pe2.ends_with("_Gold") or pe2.ends_with("_Lumber"):
			pe2 = "Walk" if _moving else "Stand"
		Wc3Pe2Particles.apply_sequence(body, pe2)


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
				if leaf.contains("gold") or leaf.contains("lumber"):
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
		if leaf.contains("gold") or leaf.contains("lumber"):
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
