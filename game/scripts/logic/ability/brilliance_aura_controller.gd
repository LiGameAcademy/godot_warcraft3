class_name BrillianceAuraController
extends Node

## 辉煌光环 AHab（Logic）：Area 内友军每秒 DataA 回蓝；被动，学会即生效。

const ABIL_ID := "AHab"
const NODE_NAME := "BrillianceAuraController"

var _unit_host_cb: Callable = Callable()
var _cache: MapModelCache = null
var _beneficiary_fx: Dictionary = {}


static func of(unit: Node3D) -> BrillianceAuraController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as BrillianceAuraController


static func ensure_on(unit: Node3D) -> BrillianceAuraController:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	var c := BrillianceAuraController.new()
	c.name = NODE_NAME
	unit.add_child(c)
	return c


static func unit_can_have(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	for abil_id in AbilityCatalog.ability_ids_for_unit(tid):
		if str(abil_id) == ABIL_ID:
			return true
	return false


func configure(unit_host_cb: Callable, cache: MapModelCache = null) -> void:
	_unit_host_cb = unit_host_cb
	_cache = cache
	set_process(true)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		set_process(false)
		return
	var lv := AbilityCatalog.level_for(host, ABIL_ID)
	var ab := AbilityCatalog.data(ABIL_ID)
	if lv <= 0 or ab == null or not unit_can_have(host):
		BrillianceAuraPresenter.sync_caster(host, false, _cache)
		BrillianceAuraPresenter.clear_beneficiaries(_beneficiary_fx)
		set_process(false)
		return
	var rate := maxf(ab.data_a_at(lv), 0.0)
	var radius := maxf(ab.area_at(lv), 1.0)
	var unit_host: Node = _unit_host_cb.call() as Node if _unit_host_cb.is_valid() else null
	if unit_host == null or rate <= 0.0:
		return
	var center := Wc3Coords.godot_to_wc3_xy(host.global_position)
	var allies := CombatQuery.units_friendly_in_radius(unit_host, host, center, radius)
	BrillianceAuraPresenter.sync_caster(host, true, _cache)
	BrillianceAuraPresenter.sync_beneficiaries(host, allies, _cache, _beneficiary_fx)
	for n in allies:
		if n is Node3D and UnitMana.has_mana(n as Node3D):
			UnitMana.regenerate(n as Node3D, rate * delta)


func _exit_tree() -> void:
	BrillianceAuraPresenter.clear_beneficiaries(_beneficiary_fx)
	var host := get_parent() as Node3D
	if host != null and is_instance_valid(host):
		BrillianceAuraPresenter.sync_caster(host, false, _cache)
