class_name DefendController
extends Node

## 步兵顶盾开关（Logic）。
## - 解锁看 PlayerStock.has_upgrade(Rhde)；本组件只负责开/关
## - Present：Unit Stance.DEFEND
## - 移速：Navigator.speed_mul ← 1 − Adef.DataC
## - 穿刺：DamagePipeline 乘 Adef.DataA（承受比例）

const ABIL_ID := "Adef"
const UPGRADE_ID := "Rhde"

signal changed(active: bool)

var _active: bool = false


func is_active() -> bool:
	return _active


func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	_apply_speed()
	_apply_visual()
	changed.emit(_active)


func toggle() -> bool:
	set_active(not _active)
	return _active


func speed_mul() -> float:
	if not _active:
		return 1.0
	return clampf(1.0 - data_speed_loss(), 0.05, 1.0)


func data_pierce_taken() -> float:
	var ab := _abil()
	if ab == null:
		return 0.3
	return clampf(ab.data_a1, 0.0, 4.0)


func data_speed_loss() -> float:
	var ab := _abil()
	if ab == null:
		return 0.3
	return clampf(ab.data_c1, 0.0, 0.95)


static func of(unit: Node3D) -> DefendController:
	if unit == null or not is_instance_valid(unit):
		return null
	return unit.get_node_or_null("DefendController") as DefendController


static func is_defending(unit: Node3D) -> bool:
	var c := of(unit)
	return c != null and c.is_active()


## 穿刺伤害承受比例；未顶盾 = 1。
static func pierce_taken_factor(unit: Node3D) -> float:
	var c := of(unit)
	if c == null or not c.is_active():
		return 1.0
	return c.data_pierce_taken()


static func unit_has_abil(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return false
	return CommandButtonCatalog.get_shared().get_abil_list(tid).find(ABIL_ID) >= 0


func _apply_speed() -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var nav := body.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.speed_mul = speed_mul()


func _apply_visual() -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var vis := Unit.of(body)
	if vis == null:
		return
	vis.set_stance(
		AnimSequenceResolver.Stance.DEFEND if _active else AnimSequenceResolver.Stance.DEFAULT
	)


func _abil() -> AbilityDataDef:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var store: Node = tree.root.get_node_or_null("Wc3DefStore")
	if store == null or not store.has_method("ensure_table"):
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, ABIL_ID) as AbilityDataDef
