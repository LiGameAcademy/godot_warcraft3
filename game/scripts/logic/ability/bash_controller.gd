class_name BashController
extends Node

## 重击 AHbh（Logic）：攻击命中时概率眩晕 + 额外伤害。

const ABIL_ID := "AHbh"
const NODE_NAME := "BashController"


static func of(unit: Node3D) -> BashController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as BashController


static func ensure_on(unit: Node3D) -> BashController:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	if not unit_can_have(unit):
		return null
	var c := BashController.new()
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


func _ready() -> void:
	var ac := get_parent().get_node_or_null("AttackController") as AttackController
	if ac != null and not ac.damage_applied.is_connected(_on_damage_applied):
		ac.damage_applied.connect(_on_damage_applied)


func _on_damage_applied(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	if str(result.get("source_kind", "")) == "spell":
		return
	var host := get_parent() as Node3D
	var target: Node3D = result.get("target") as Node3D
	if host == null or target == null or not is_instance_valid(target):
		return
	var lv := AbilityCatalog.level_for(host, ABIL_ID)
	if lv <= 0:
		return
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return
	var chance := clampf(ab.data_a_at(lv), 0.0, 100.0)
	if chance <= 0.0:
		return
	if randf() * 100.0 > chance:
		return
	var bonus := maxf(ab.data_c_at(lv), 0.0)
	if bonus > 0.0:
		UnitLife.set_life(target, maxf(0.0, UnitLife.get_life(target) - bonus))
	var stun_sec := UnitStatusEffects.stun_duration_for(ab, lv, target)
	if stun_sec > 0.0:
		UnitStatusEffects.apply_stun(target, stun_sec)
