class_name AvatarController
extends Node

## 天神下凡 AHav（Logic）：限时加血/加甲；Present 由 Catalog 路径驱动。

const ABIL_ID := "AHav"
const NODE_NAME := "AvatarController"
const ATTACH_NODE := "AvatarFxAttach"

var _left: float = 0.0
var _bonus_hp: float = 0.0
var _bonus_armor: float = 0.0
var _cache: MapModelCache = null


static func of(unit: Node3D) -> AvatarController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as AvatarController


static func ensure_on(unit: Node3D) -> AvatarController:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	if not unit_can_have(unit):
		return null
	var c := AvatarController.new()
	c.name = NODE_NAME
	unit.add_child(c)
	return c


static func unit_can_have(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	for abil_id in AbilityCatalog.ability_ids_for_unit(tid):
		if str(abil_id) == ABIL_ID:
			return true
	return false


func is_active() -> bool:
	return _left > 0.0


func activate(level: int, cache: MapModelCache = null) -> bool:
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return false
	if is_active():
		return false
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return false
	var lv := ab.clamp_level(level)
	_bonus_hp = maxf(ab.data_b_at(lv), 0.0)
	_bonus_armor = maxf(ab.data_a_at(lv), 0.0)
	_left = maxf(ab.duration_at(lv), 0.1)
	_cache = cache
	UnitLife.ensure(host)
	var mx := UnitLife.get_max_life(host)
	var life := UnitLife.get_life(host)
	UnitLife.set_life(host, life + _bonus_hp)
	host.set_meta(UnitLife.META_MAX_LIFE, mx + _bonus_hp)
	UnitStatusEffects.set_bonus_armor(host, _bonus_armor)
	AbilityAttachFxPresenter.sync_caster_abil(host, ABIL_ID, true, _cache, ATTACH_NODE)
	set_process(true)
	return true


func _process(delta: float) -> void:
	if delta <= 0.0 or _left <= 0.0:
		return
	_left -= delta
	if _left > 0.0:
		return
	_deactivate()


func _deactivate() -> void:
	_left = 0.0
	set_process(false)
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return
	if host.has_meta(UnitLife.META_MAX_LIFE):
		var mx := maxf(UnitLife.get_max_life(host) - _bonus_hp, 1.0)
		host.set_meta(UnitLife.META_MAX_LIFE, mx)
		UnitLife.set_life(host, mini(UnitLife.get_life(host), mx))
	_bonus_hp = 0.0
	_bonus_armor = 0.0
	UnitStatusEffects.set_bonus_armor(host, 0.0)
	AbilityAttachFxPresenter.sync_attach(host, ATTACH_NODE, "", false, _cache)


func _exit_tree() -> void:
	if is_active():
		_deactivate()
