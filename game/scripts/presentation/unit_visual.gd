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
## 建造站桩：播 Stand Work（锤子 geoset），期间忽略 locomotion
var _building_work: bool = false
## Stand_Gold/Lumber 来回播（源 MDX 首尾不闭合，不能硬循环）
var _pong_anim: String = ""
var _pong_back: bool = false
var _pong_ap: AnimationPlayer = null


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
	if _chopping or _building_work:
		# 砍伐/建造中只更新 carry 状态，动画仍由 Attack Lumber / Stand Work 主导
		return
	# 负资源开/关：0 blend，否则走路几步才看到金袋/空手
	var blend := BLEND_CARRY_SWITCH if carry_changed or force else (
		BLEND_TO_WALK if _moving else BLEND_TO_STAND
	)
	_play_logical(_logical_for(_moving, _carry), blend)


## moving=true → Walk[_Gold|_Lumber]；false → Stand[…]。同态不重播。
func set_locomotion(moving: bool) -> void:
	# 位移必须打断砍伐 / 建造站桩，否则会「边播 Work 边走路」
	if (_chopping or _building_work) and moving:
		_chopping = false
		_building_work = false
		_logical = ""
	elif _chopping or _building_work:
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


## 建造站桩：播 Stand Work（人族施工）；负资源时 Stand Work Gold / Lumber（保留背袋/木头）。
## 锤子 mesh = BoneAttachment Geoset_0_Group_20（原绑 AxHandle01）；施工时改绑左手。
const _HAMMER_BA_NAME := "Geoset_0_Group_20"
const _HAMMER_BONE_WORK := "Bone_Hand_L"
const _HAMMER_BONE_IDLE := "AxHandle01"
const _META_HAMMER_BONE := "hammer_bone_restore"


func set_building_work(active: bool) -> void:
	if active:
		_chopping = false
		_building_work = true
		_moving = false
		_logical = ""
		var body := get_parent() as Node3D
		var work := _work_logical_for(_carry)
		var resolved := _resolve_work_animation(body, work)
		if not resolved.is_empty() and _play_with_blend(body, resolved, 0.1):
			_logical = work
			Wc3Pe2Particles.apply_sequence(body, work.replace("_", " "))
		else:
			_play_logical(work, 0.1)
		_patch_work_tool_anim_tracks(body)
		_snap_work_geosets()
		_reveal_work_tools(body)
		process_priority = -20
		set_process(true)
	else:
		if not _building_work and not _is_work_logical(_logical):
			return
		_building_work = false
		process_priority = 0
		set_process(false)
		_retarget_hammer_attachment(get_parent(), false)
		if _is_work_logical(_logical):
			_logical = ""
			_play_logical(_logical_for(_moving, _carry), BLEND_TO_STAND)


func _work_logical_for(carry: int) -> String:
	match carry:
		Carry.GOLD:
			return "Stand_Work_Gold"
		Carry.LUMBER:
			return "Stand_Work_Lumber"
		_:
			return "Stand_Work"


func _is_work_logical(logical: String) -> bool:
	if logical.is_empty():
		return false
	var leaf := logical.replace(" ", "_").to_lower()
	return leaf.begins_with("stand_work")


## Stand Work[_Gold|_Lumber] → 空格名 → 无后缀回退。
func _resolve_work_animation(body: Node, work_logical: String) -> String:
	var candidates: Array[String] = [
		work_logical.replace("_", " "),
		work_logical,
	]
	if work_logical != "Stand_Work":
		candidates.append("Stand Work")
		candidates.append("Stand_Work")
	for cand in candidates:
		var resolved := BuildingVisual.resolve_animation(body, cand)
		if not resolved.is_empty():
			return resolved
	return ""


func _process(_delta: float) -> void:
	if not _building_work:
		set_process(false)
		return
	_reveal_work_tools(get_parent())


func _snap_work_geosets() -> void:
	var body := get_parent() as Node3D
	if body == null or _cache == null:
		return
	var anim := _logical if not _logical.is_empty() else "Stand_Work"
	if _cache.has_method("snap_geoset_visibility_for"):
		_cache.call("snap_geoset_visibility_for", body, anim)
	_reveal_work_tools(body)


## 施工：Attachment 改绑到手 + AxHandle 全局对齐到左手。
func _reveal_work_tools(body: Node) -> void:
	if body == null:
		return
	_retarget_hammer_attachment(body, true)
	var sk := _find_skeleton(body)
	if sk == null:
		return
	var ax := sk.find_bone(_HAMMER_BONE_IDLE)
	var hand := sk.find_bone(_HAMMER_BONE_WORK)
	if ax < 0:
		return
	if hand >= 0:
		var hand_g := sk.get_bone_global_pose(hand)
		var parent_i := sk.get_bone_parent(ax)
		var parent_g := Transform3D.IDENTITY
		if parent_i >= 0:
			parent_g = sk.get_bone_global_pose(parent_i)
		var local := parent_g.affine_inverse() * hand_g
		sk.set_bone_pose_position(ax, local.origin)
		sk.set_bone_pose_rotation(ax, local.basis.get_rotation_quaternion())
	sk.set_bone_pose_scale(ax, Vector3.ONE)


func _retarget_hammer_attachment(body: Node, to_hand: bool) -> void:
	for n in body.find_children("*", "BoneAttachment3D", true, false):
		var ba := n as BoneAttachment3D
		if ba == null:
			continue
		var nm := str(ba.name)
		var is_hammer := (
			nm == _HAMMER_BA_NAME
			or ba.bone_name == _HAMMER_BONE_IDLE
			or (nm.begins_with("Geoset_0_Group_") and ba.bone_name == _HAMMER_BONE_IDLE)
		)
		if not is_hammer:
			continue
		if to_hand:
			if not ba.has_meta(_META_HAMMER_BONE):
				ba.set_meta(_META_HAMMER_BONE, ba.bone_name)
			ba.bone_name = _HAMMER_BONE_WORK
			ba.visible = true
		else:
			var restore := str(ba.get_meta(_META_HAMMER_BONE, _HAMMER_BONE_IDLE))
			ba.bone_name = restore if not restore.is_empty() else _HAMMER_BONE_IDLE
		for c in ba.get_children():
			if c is Node3D:
				(c as Node3D).visible = true
				(c as Node3D).scale = Vector3.ONE


## Stand_Work*：把 AxHandle01 的 scale 轨改成 1，避免施工时锤子被缩没。
func _patch_work_tool_anim_tracks(body: Node) -> void:
	if body == null:
		return
	var ap := _find_animation_player(body)
	if ap == null:
		return
	for logical in ["Stand Work", "Stand_Work", "Stand_Work_Gold", "Stand_Work_Lumber"]:
		var resolved := BuildingVisual.resolve_animation(body, logical)
		if resolved.is_empty() or not ap.has_animation(resolved):
			continue
		var anim := ap.get_animation(resolved)
		if anim == null:
			continue
		for i in range(anim.get_track_count()):
			var ps := str(anim.track_get_path(i))
			if not ps.contains("AxHandle01"):
				continue
			var ttype := anim.track_get_type(i)
			var is_scale := (
				ps.ends_with(":scale")
				or ttype == Animation.TYPE_SCALE_3D
			)
			if not is_scale:
				continue
			for ki in range(anim.track_get_key_count(i)):
				anim.track_set_key_value(i, ki, Vector3.ONE)


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
			var loop := not _is_broken_loop_stand(anim_name)
			var ok := _cache.play_animation(body, anim_name, loop)
			if ok and _is_broken_loop_stand(anim_name):
				ap = _find_animation_player(body)
				if ap != null:
					_begin_stand_carry_pong(ap, anim_name)
			elif not _is_broken_loop_stand(anim_name):
				_clear_stand_carry_pong()
			return ok
		return false
	ap.active = true
	var anim := ap.get_animation(anim_name)
	if anim != null:
		# 官方 Peasant「Stand Gold/Lumber」Interval 首尾姿势差极大（~100 WC3 单位），
		# LOOP_LINEAR 硬绕回会手臂猛抽。改：播完倒放、再正放（ping-pong），连续无硬切。
		# Walk_Gold / Stand_Work_Gold 源数据首尾闭合，仍线性循环。
		if _is_broken_loop_stand(anim_name):
			anim.loop_mode = Animation.LOOP_NONE
		else:
			anim.loop_mode = Animation.LOOP_LINEAR
			_clear_stand_carry_pong()
	# custom_blend：从当前姿势交叉淡入到目标动画
	ap.play(anim_name, maxf(blend, 0.0))
	if _is_broken_loop_stand(anim_name):
		_begin_stand_carry_pong(ap, anim_name)
	return true


## 源 MDX 标了 looping 但首尾姿势不闭合的站立负资源序列。
func _is_broken_loop_stand(anim_or_logical: String) -> bool:
	var leaf := _anim_leaf(anim_or_logical).replace(" ", "_").to_lower()
	return leaf == "stand_gold" or leaf == "stand_lumber"


func _begin_stand_carry_pong(ap: AnimationPlayer, anim_name: String) -> void:
	_pong_ap = ap
	_pong_anim = anim_name
	_pong_back = false
	if ap.speed_scale < 0.0:
		ap.speed_scale = 1.0
	if not ap.animation_finished.is_connected(_on_stand_carry_pong_finished):
		ap.animation_finished.connect(_on_stand_carry_pong_finished)


func _clear_stand_carry_pong() -> void:
	if _pong_ap != null and is_instance_valid(_pong_ap) and _pong_ap.speed_scale < 0.0:
		_pong_ap.speed_scale = 1.0
	_pong_anim = ""
	_pong_back = false
	_pong_ap = null


func _on_stand_carry_pong_finished(anim_name: StringName) -> void:
	if _pong_anim.is_empty():
		return
	if _anim_leaf(str(anim_name)).to_lower() != _anim_leaf(_pong_anim).to_lower():
		return
	# 已离开负资源站立：不再来回
	if _moving or _building_work or _chopping:
		_clear_stand_carry_pong()
		return
	if not _is_broken_loop_stand(_logical_for(false, _carry)):
		_clear_stand_carry_pong()
		return
	var ap := _pong_ap
	if ap == null or not is_instance_valid(ap):
		ap = _find_animation_player(get_parent())
	if ap == null or not ap.has_animation(_pong_anim):
		_clear_stand_carry_pong()
		return
	_pong_ap = ap
	_pong_back = not _pong_back
	# 无 blend：首尾本就不接，交叉淡入反而糊；正放/倒放交接处姿势连续
	if _pong_back:
		ap.play_backwards(_pong_anim)
	else:
		ap.play(_pong_anim)


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


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f:
			return f
	return null
