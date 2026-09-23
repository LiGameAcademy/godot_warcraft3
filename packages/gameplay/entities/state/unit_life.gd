class_name UnitLife
extends RefCounted

## 单位/建筑运行时生命（Logic）。挂在 Node3D meta 上，供 HUD / 血条 / 建造进度共用。
## 权威 max：UnitBalanceDef.hp + 英雄力量加成；地图 hitPoints 为出生百分比（-1=满血）。

const META_LIFE := "life"
const META_MAX_LIFE := "max_life"
const META_UNDER_CONSTRUCTION := "under_construction"
const HERO_HP_PER_STRENGTH := 25.0


static func max_hp_for_type(type_id: String, hero_level: int = 1) -> float:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return 1.0
	var store := _def_store()
	if store == null:
		return 1.0
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	var base := 1.0
	if bal != null:
		base = float(bal.hp) if bal.hp > 0 else maxf(float(bal.real_hp), 1.0)
		if TechPresence.is_hero_id(tid):
			var strength := floorf(float(bal.str_base) + float(maxi(hero_level, 1) - 1) * bal.st_rplus + 0.00001)
			base += maxf(strength, 0.0) * HERO_HP_PER_STRENGTH
	return base


static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## 确保节点有 life/max_life；已有则不动。
static func ensure(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta(META_LIFE) and node.has_meta(META_MAX_LIFE):
		return
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", ""))
	var max_hp := max_hp_for_type(tid, AbilityCatalog.hero_level_of(node))
	var pct := float(d.get("hitPoints", -1.0))
	if pct < 0.0:
		pct = 100.0
	pct = clampf(pct, 0.0, 100.0)
	node.set_meta(META_MAX_LIFE, max_hp)
	node.set_meta(META_LIFE, max_hp * pct / 100.0)


## 等级变化后保持已受伤害量；死亡英雄不能因上限增加而复活。
static func sync_hero_max(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tid := str(node.get_meta("unit_data", {}).get("typeId", ""))
	if not TechPresence.is_hero_id(tid):
		return
	ensure(node)
	var old_max := get_max_life(node)
	var current := get_life(node)
	var new_max := max_hp_for_type(tid, AbilityCatalog.hero_level_of(node))
	node.set_meta(META_MAX_LIFE, new_max)
	node.set_meta(META_LIFE, clampf(current + new_max - old_max, 0.0, new_max) if current > 0.0 else 0.0)


static func get_life(node: Node3D) -> float:
	ensure(node)
	if node == null:
		return 0.0
	return float(node.get_meta(META_LIFE, 0.0))


static func get_max_life(node: Node3D) -> float:
	ensure(node)
	if node == null:
		return 1.0
	return maxf(float(node.get_meta(META_MAX_LIFE, 1.0)), 1.0)


static func ratio(node: Node3D) -> float:
	var mx := get_max_life(node)
	if mx <= 0.0:
		return 0.0
	return clampf(get_life(node) / mx, 0.0, 1.0)


static func set_life(node: Node3D, life: float) -> void:
	ensure(node)
	if node == null:
		return
	var mx := get_max_life(node)
	node.set_meta(META_LIFE, clampf(life, 0.0, mx))


## 回血（不超过上限；死亡/满血时无效果）。
static func regenerate(node: Node3D, amount: float) -> void:
	if node == null or amount <= 0.0:
		return
	ensure(node)
	var cur := get_life(node)
	if cur <= 0.0:
		return
	var mx := get_max_life(node)
	if cur >= mx:
		return
	set_life(node, cur + amount)


static func set_ratio(node: Node3D, r: float) -> void:
	ensure(node)
	if node == null:
		return
	set_life(node, get_max_life(node) * clampf(r, 0.0, 1.0))


static func is_under_construction(node: Node3D) -> bool:
	return node != null and bool(node.get_meta(META_UNDER_CONSTRUCTION, false))


static func set_under_construction(node: Node3D, on: bool) -> void:
	if node == null:
		return
	node.set_meta(META_UNDER_CONSTRUCTION, on)
