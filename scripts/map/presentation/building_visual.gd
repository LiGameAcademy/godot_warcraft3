class_name BuildingVisual
extends RefCounted

## 建筑模型视觉：typeId 档位姿态 + 建造/训练阶段 → Sequence。
## 人族主城 htow/hkee/hcas 共用 TownHall.mdx（Stance = Upgrade First|Second）。
## 命名/播放委托 AnimSequenceResolver / AnimPlayback（编辑器与游戏共用）。
## 勿放 game/，避免 map→game 反向依赖。

const _TAG := "BuildingVisual"


enum Phase {
	IDLE = 0,
	BIRTH = 1,
	WORK = 2,
	UPGRADE_BIRTH = 3,
}

## 兼容旧调用。
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
		_:
			return AnimSequenceResolver.Activity.IDLE


## 逻辑动画名（WC3 Sequence 名，空格版）。
static func sequence_name(type_id: String, phase: int) -> String:
	var stance: int = AnimSequenceResolver.stance_for_building_type(type_id)
	var activity: int = _phase_to_activity(phase)
	return AnimSequenceResolver.sequence_name(activity, stance)


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
	var played: Dictionary = AnimPlayback.play_logical(
		root, want, 0.0, cache, activity, ["Stand"]
	)
	if bool(played.get("ok", false)):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"apply_phase ok type=%s → %s" % [type_id, str(played.get("played_as", want))]
		)
		return true
	var ok := cache.autoplay_stand(root, false)
	if ok:
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "apply_phase Stand fallback type=%s" % type_id)
		Wc3Pe2Particles.apply_sequence(root, "Stand")
	else:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"apply_phase 失败 type=%s want=%s" % [type_id, want]
		)
	return ok


static func apply_idle(cache: MapModelCache, root: Node, type_id: String) -> bool:
	return apply_phase(cache, root, type_id, Phase.IDLE)


static func resolve_animation(root: Node, logical_name: String) -> String:
	return AnimPlayback.resolve(root, logical_name)
