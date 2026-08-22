class_name UnitMana
extends RefCounted

## 单位运行时魔法（Logic）。英雄 P0：mana_n 缺省时用 mana0 作上限。

const META_MANA := "mana"
const META_MAX_MANA := "max_mana"


static func max_for_type(type_id: String) -> int:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return 0
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal == null:
		return 0
	if bal.mana_n > 0:
		return bal.mana_n
	if bal.mana0 > 0:
		return bal.mana0
	return 0


static func ensure(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta(META_MANA) and node.has_meta(META_MAX_MANA):
		return
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", ""))
	var mx := max_for_type(tid)
	if mx <= 0:
		return
	var start := mx
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal != null and bal.mana0 > 0:
		start = mini(bal.mana0, mx)
	node.set_meta(META_MAX_MANA, mx)
	node.set_meta(META_MANA, start)


static func has_mana(node: Node3D) -> bool:
	ensure(node)
	if node == null:
		return false
	return int(node.get_meta(META_MAX_MANA, 0)) > 0


static func get_mana(node: Node3D) -> int:
	ensure(node)
	if node == null:
		return 0
	return int(node.get_meta(META_MANA, 0))


static func get_max_mana(node: Node3D) -> int:
	ensure(node)
	if node == null:
		return 0
	return int(node.get_meta(META_MAX_MANA, 0))


static func spend(node: Node3D, amount: float) -> bool:
	ensure(node)
	if node == null:
		return false
	var cost := maxi(int(round(amount)), 0)
	if cost <= 0:
		return true
	if get_mana(node) < cost:
		return false
	node.set_meta(META_MANA, get_mana(node) - cost)
	return true


static func can_spend(node: Node3D, amount: float) -> bool:
	return get_mana(node) >= maxi(int(round(amount)), 0)
