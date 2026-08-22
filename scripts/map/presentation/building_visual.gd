class_name BuildingVisual
extends RefCounted

## 建筑表现策略：typeId 档位姿态 + 建造/训练 Phase → 逻辑 Sequence，再交给模型门面播放。
##
## ## 分层
## - 本类是**静态工具**（非 Node），Director / 编辑器调用；勿放 `game/`，避免 map→game 反向依赖。
## - 播放优先走 [Wc3ModelScene] → [Wc3AnimPlayer]；无门面时回退 [AnimPlayback]。
## - 人族主城 `htow`/`hkee`/`hcas` 共用 TownHall.mdx（Stance = Upgrade First|Second）。
##
## ## 职责边界
## - **做**：Phase↔Activity 映射、`is_building`、播 Birth/Work/Idle/Death。
## - **不做**：训练队列状态、扣资源；挂点/AP 查找（用 Wc3ModelScene / Wc3AnimPlayer）。

const _TAG := "BuildingVisual"


## 建筑视觉阶段（由建造进度 / 训练队列等驱动，再映射到 Activity）。
enum Phase {
	IDLE = 0, ## 待机 Stand（含主城档位后缀）。
	BIRTH = 1, ## 建造出现。
	WORK = 2, ## 训练/工作烟等 Stand Work。
	UPGRADE_BIRTH = 3, ## 升级过程出现（仍走 Birth 活动）。
	DEATH = 4, ## 销毁（金矿塌陷等）。
}

## 兼容旧调用：typeId → 逻辑名后缀（空格开头）。
const TOWN_HALL_TIER := {
	"htow": "",
	"hkee": " Upgrade First",
	"hcas": " Upgrade Second",
}

## typeId → is_building；点选遍历全图时避免反复查 DefStore。
static var _is_building_cache: Dictionary = {}


static func _wc3_def_store() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var tree := ml as SceneTree
	if tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## 是否建筑单位（主城档位表 + UnitBalance.isbldg）。
static func is_building(type_id: String) -> bool:
	if type_id.is_empty() or type_id == "sloc":
		return false
	if _is_building_cache.has(type_id):
		return bool(_is_building_cache[type_id])
	var result := false
	if AnimSequenceResolver.TOWN_HALL_STANCE.has(type_id):
		result = true
	else:
		var store: Node = _wc3_def_store()
		if store != null and store.has_method("ensure_table"):
			store.ensure_table(UnitBalanceDef.TABLE_NAME)
			var row: Resource = store.get_row(UnitBalanceDef.TABLE_NAME, type_id)
			if row is UnitBalanceDef:
				result = (row as UnitBalanceDef).isbldg
	_is_building_cache[type_id] = result
	return result


static func town_hall_tier_suffix(type_id: String) -> String:
	return AnimSequenceResolver.town_hall_tier_suffix(type_id)


static func _phase_to_activity(phase: int) -> int:
	match phase:
		Phase.BIRTH, Phase.UPGRADE_BIRTH:
			return AnimSequenceResolver.Activity.BIRTH
		Phase.WORK:
			return AnimSequenceResolver.Activity.WORK
		Phase.DEATH:
			return AnimSequenceResolver.Activity.DEATH
		_:
			return AnimSequenceResolver.Activity.IDLE


## 逻辑动画名（WC3 Sequence 名，空格版）。
static func sequence_name(type_id: String, phase: int) -> String:
	var stance: int = AnimSequenceResolver.stance_for_building_type(type_id)
	var activity: int = _phase_to_activity(phase)
	return AnimSequenceResolver.sequence_name(activity, stance)


## 按 Phase 播放；成功后可 snap geosetvis。失败则 Stand 回退。
static func apply_phase(
	cache: MapModelCache, root: Node, type_id: String, phase: int = Phase.IDLE
) -> bool:
	if cache == null or root == null:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"apply_phase 忽略：cache/root 空 type=%s phase=%s" % [type_id, phase]
		)
		return false
	var want := sequence_name(type_id, phase)
	var activity: int = _phase_to_activity(phase)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"apply_phase type=%s phase=%s want=%s" % [type_id, phase, want]
	)
	var model := Wc3ModelScene.find_on(root)
	var played: Dictionary
	if model != null:
		played = model.play_logical(want, 0.0, cache, activity, ["Stand"])
	else:
		played = AnimPlayback.play_logical(root, want, 0.0, cache, activity, ["Stand"])
	var snap_root: Node = model if model != null else root
	if bool(played.get("ok", false)):
		var played_as := str(played.get("played_as", want))
		if cache != null and cache.has_method("snap_geoset_visibility_for"):
			cache.call("snap_geoset_visibility_for", snap_root, played_as)
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"apply_phase ok type=%s → %s" % [type_id, played_as]
		)
		return true
	var ok := cache.autoplay_stand(root, false)
	if ok:
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "apply_phase Stand fallback type=%s" % type_id)
		if cache.has_method("snap_stand_geoset_visibility"):
			cache.call("snap_stand_geoset_visibility", snap_root)
		Wc3Pe2Particles.apply_sequence(snap_root, "Stand")
	else:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"apply_phase 失败 type=%s want=%s" % [type_id, want]
		)
	return ok


static func apply_idle(cache: MapModelCache, root: Node, type_id: String) -> bool:
	return apply_phase(cache, root, type_id, Phase.IDLE)


## 建筑销毁（金矿塌陷等）：单次 Death，失败不回退 Stand。返回 `{ok, duration}`。
static func play_death(cache: MapModelCache, root: Node, type_id: String = "") -> Dictionary:
	var out := {"ok": false, "duration": 0.0}
	if root == null:
		return out
	var want := sequence_name(type_id, Phase.DEATH) if not type_id.is_empty() else "Death"
	var model := Wc3ModelScene.find_on(root)
	var played: Dictionary
	if model != null:
		played = model.play_logical(
			want, 0.0, cache, AnimSequenceResolver.Activity.DEATH, ["Death"]
		)
	else:
		played = AnimPlayback.play_logical(
			root, want, 0.0, cache, AnimSequenceResolver.Activity.DEATH, ["Death"]
		)
	if not bool(played.get("ok", false)):
		return out
	out["ok"] = true
	var ap: AnimationPlayer = null
	if model != null:
		ap = model.animation_player()
	else:
		ap = AnimPlayback.find_animation_player(root)
	if ap != null and not str(ap.current_animation).is_empty():
		out["duration"] = maxf(ap.current_animation_length, 0.0)
	return out


## 解析逻辑名 → 库内动画路径（优先经模型门面）。
static func resolve_animation(root: Node, logical_name: String) -> String:
	var model := Wc3ModelScene.find_on(root)
	if model != null:
		return model.resolve_logical(logical_name)
	return AnimPlayback.resolve(root, logical_name)
