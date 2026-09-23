class_name HeroDeathRegistry
extends RefCounted

## 英雄阵亡登记（Logic）：祭坛复活 / HUD 角标的数据源（Present 后置）。

const GameConstants = preload("res://addons/rts_gameplay/catalog/melee_game_constants.gd")

## owner_id → Array[{ type_id, level, owner, died_at }]
static var _dead_by_owner: Dictionary = {}


## 当前人族对战的祭坛入口；命令卡与下单共用，扩展种族时在此增加支持。
static func can_revive_at(building_id: String) -> bool:
	return building_id.strip_edges() == "halt"


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
		"inventory": Inventory.of(unit).snapshot() if Inventory.of(unit) != null else {},
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


## 祭坛规则读取当前导入版本的 MiscGame，与单位原价同源。
## 使用英雄原始训练价格；首英雄免费政策不改变复活报价。
static func revive_cost(level: int, type_id: String) -> int:
	var original := maxi(BuildingCatalog.get_gold_cost(type_id), 0)
	var lv := clampi(level, 1, HeroProgression.MAX_HERO_LEVEL)
	return GameConstants.revive_gold(original, lv)


static func revive_time_sec(level: int, type_id: String) -> float:
	var original := maxf(BuildingCatalog.get_build_time(type_id), 0.0)
	var lv := clampi(level, 1, HeroProgression.MAX_HERO_LEVEL)
	return GameConstants.revive_seconds(original, lv)


static func clear_owner(owner_id: int) -> void:
	_dead_by_owner.erase(owner_id)
