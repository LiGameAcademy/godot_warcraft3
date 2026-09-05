class_name UnitMana
extends RefCounted

## 单位运行时魔法（Logic）。
## 英雄：上限 = 智力 × 12（WC3）；非英雄：mana_n / mana0。
## 自然回蓝见 `UnitRegen`（本类 `regenerate` 供自然回复与光环共用）。

const META_MANA := "mana"
const META_MAX_MANA := "max_mana"
const HERO_MANA_PER_INT := 12


static func intelligence_at_level(bal: UnitBalanceDef, hero_level: int) -> float:
	if bal == null:
		return 0.0
	var lv := maxi(hero_level, 1)
	return float(bal.int_base) + float(lv - 1) * bal.in_tplus


static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


static func max_for_hero_type(type_id: String, hero_level: int = 1) -> int:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return 0
	var store := _def_store()
	if store == null:
		return 0
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal == null:
		return 0
	var intel := intelligence_at_level(bal, hero_level)
	return maxi(int(floor(intel * float(HERO_MANA_PER_INT))), 0)


static func max_for_type(type_id: String, hero_level: int = 1) -> int:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return 0
	if TechPresence.is_hero_id(tid):
		return max_for_hero_type(tid, hero_level)
	var store := _def_store()
	if store == null:
		return 0
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal == null:
		return 0
	if bal.mana_n > 0:
		return bal.mana_n
	if bal.mana0 > 0:
		return bal.mana0
	return 0


## 英雄升级后刷新魔法上限（当前蓝量 += 增量，不超过新上限）。
static func sync_hero_max(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if not TechPresence.is_hero_id(tid):
		return
	ensure(node)
	var old_max := get_max_mana(node)
	var new_max := max_for_hero_type(tid, AbilityCatalog.hero_level_of(node))
	if new_max <= 0:
		return
	var cur := get_mana(node)
	node.set_meta(META_MAX_MANA, new_max)
	if new_max > old_max:
		node.set_meta(META_MANA, mini(cur + (new_max - old_max), new_max))
	else:
		node.set_meta(META_MANA, mini(cur, new_max))


static func ensure(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta(META_MANA) and node.has_meta(META_MAX_MANA):
		return
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var hl := AbilityCatalog.hero_level_of(node) if TechPresence.is_hero_id(tid) else 1
	var mx := max_for_type(tid, hl)
	if mx <= 0:
		return
	var start := mx
	var store := _def_store()
	var bal: UnitBalanceDef = null
	if store != null:
		store.ensure_table(UnitBalanceDef.TABLE_NAME)
		bal = store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal != null and bal.mana0 > 0 and not TechPresence.is_hero_id(tid):
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


## 回蓝（支持小数累积，不超过上限）。
static func regenerate(node: Node3D, amount: float) -> void:
	if node == null or amount <= 0.0:
		return
	ensure(node)
	if not has_mana(node):
		return
	const ACC_KEY := "mana_regen_accum"
	var acc := float(node.get_meta(ACC_KEY, 0.0)) + amount
	var gain := int(floor(acc))
	if gain <= 0:
		node.set_meta(ACC_KEY, acc)
		return
	acc -= float(gain)
	node.set_meta(ACC_KEY, acc)
	var mx := get_max_mana(node)
	node.set_meta(META_MANA, mini(get_mana(node) + gain, mx))
