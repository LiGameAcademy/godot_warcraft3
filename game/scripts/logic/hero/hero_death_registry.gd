class_name HeroDeathRegistry
extends RefCounted

## 英雄阵亡登记（Logic）：祭坛复活 / HUD 角标的数据源（Present 后置）。

const REVIVE_BASE_COST := 250
const REVIVE_BASE_SEC := 120.0

## owner_id → Array[{ type_id, level, owner, died_at }]
static var _dead_by_owner: Dictionary = {}


static func register_death(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var ud: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(ud.get("typeId", "")).strip_edges()
	if not TechPresence.is_hero_id(tid):
		return
	var owner := int(ud.get("owner", 0))
	var lv := AbilityCatalog.hero_level_of(unit)
	if not _dead_by_owner.has(owner):
		_dead_by_owner[owner] = []
	var list: Array = _dead_by_owner[owner]
	list.append({
		"type_id": tid,
		"level": maxi(lv, 1),
		"owner": owner,
		"died_at": Time.get_ticks_msec(),
		"ability_levels": HeroSkill.ability_levels(unit).duplicate(true),
		"hero_xp": HeroProgression.xp_of(unit),
	})
	_dead_by_owner[owner] = list


static func dead_heroes(owner_id: int) -> Array:
	return (_dead_by_owner.get(owner_id, []) as Array).duplicate(true)


static func dead_count(owner_id: int) -> int:
	return (_dead_by_owner.get(owner_id, []) as Array).size()


## 取出一只待复活英雄（同 type 优先最早阵亡）；成功返回 entry，否则空 Dictionary。
static func take_for_revive(owner_id: int, type_id: String) -> Dictionary:
	var want := type_id.strip_edges()
	if want.is_empty() or not _dead_by_owner.has(owner_id):
		return {}
	var list: Array = _dead_by_owner[owner_id]
	for i in range(list.size()):
		var e: Dictionary = list[i]
		if str(e.get("type_id", "")) != want:
			continue
		list.remove_at(i)
		_dead_by_owner[owner_id] = list
		if list.is_empty():
			_dead_by_owner.erase(owner_id)
		return e
	return {}


## 复活取消/失败时把登记写回（保持阵亡队列）。
static func restore_dead(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var owner := int(entry.get("owner", 0))
	var tid := str(entry.get("type_id", "")).strip_edges()
	if tid.is_empty() or not TechPresence.is_hero_id(tid):
		return
	if not _dead_by_owner.has(owner):
		_dead_by_owner[owner] = []
	var list: Array = _dead_by_owner[owner]
	list.append(entry)
	_dead_by_owner[owner] = list


static func revive_cost(level: int) -> int:
	return REVIVE_BASE_COST + maxi(level, 1) * 50


static func revive_time_sec(level: int) -> float:
	return REVIVE_BASE_SEC + float(maxi(level, 1) - 1) * 30.0


static func clear_owner(owner_id: int) -> void:
	_dead_by_owner.erase(owner_id)
