class_name TechPresence
extends RefCounted

## 玩家已完工建筑/单位存在性（供 Requires 判定）。
## 升级链：需要 htow 时，hkee/hcas 也算满足（经典 Melee）。

## 人族竖切：祭坛训四英雄；兵营只训步兵/火枪手。
const VERTICAL_TRAINS := {
	"halt": ["Hamg", "Hmkg", "Hpal", "Hblm"],
	"hbar": ["hfoo", "hrif"],
	"htow": ["hpea"],
	"hkee": ["hpea"],
	"hcas": ["hpea"],
}

## 人族竖切：兵营只研究顶盾。
const VERTICAL_RESEARCHES := {
	"hbar": ["Rhde"],
}

## Melee 简化：每位玩家同时场上英雄上限。
const MAX_HEROES_PER_PLAYER := 1

const _HERO_IDS := {
	"Hamg": true,
	"Hmkg": true,
	"Hpal": true,
	"Hblm": true,
}

## 需求 id → 可满足它的 typeId 集合（含自身）。
const _EQUIV := {
	"htow": ["htow", "hkee", "hcas"],
	"hkee": ["hkee", "hcas"],
	"hcas": ["hcas"],
}


static func is_hero_id(unit_id: String) -> bool:
	return bool(_HERO_IDS.get(unit_id.strip_edges(), false))


## unit_host 下、指定 owner、已完工建筑的 typeId → 数量。
static func collect_owned_buildings(unit_host: Node, owner_id: int) -> Dictionary:
	var out: Dictionary = {}
	if unit_host == null:
		return out
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty() or not BuildingCatalog.is_building(tid):
			continue
		if bool(node.get_meta("under_construction", false)):
			continue
		out[tid] = int(out.get(tid, 0)) + 1
	return out


## 场上英雄数量（人族四英雄 id）。
static func count_heroes(unit_host: Node, owner_id: int) -> int:
	var n := 0
	if unit_host == null:
		return 0
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var tid := str(d.get("typeId", "")).strip_edges()
		if _HERO_IDS.has(tid):
			n += 1
	return n


## 场上英雄 + 训练队列中的英雄 + 阵亡待复活（占英雄名额，对齐 WC3）。
static func count_heroes_with_queues(unit_host: Node, owner_id: int) -> int:
	var n := count_heroes(unit_host, owner_id)
	n += HeroDeathRegistry.dead_count(owner_id)
	if unit_host == null:
		return n
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var q := (c as Node3D).get_node_or_null("TrainQueue") as TrainQueue
		if q == null:
			continue
		for e in q.snapshot():
			var uid := str((e as Dictionary).get("unit_id", ""))
			# 复活队列已从 DeathRegistry 取出，不再计入 dead_count，需在此补回
			if _HERO_IDS.has(uid):
				n += 1
	return n


static func is_upgrade_queued(unit_host: Node, owner_id: int, upgrade_id: String) -> bool:
	var want := upgrade_id.strip_edges()
	if unit_host == null or want.is_empty():
		return false
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var q := (c as Node3D).get_node_or_null("TrainQueue") as TrainQueue
		if q == null:
			continue
		for e in q.snapshot():
			if str((e as Dictionary).get("unit_id", "")) == want:
				return true
	return false


## 玩家是否已满足 required_id（含升级链等价）。
static func owns_requirement(owned_buildings: Dictionary, required_id: String) -> bool:
	var rid := required_id.strip_edges()
	if rid.is_empty():
		return true
	var alts: Array = _EQUIV.get(rid, [rid])
	for a in alts:
		if int(owned_buildings.get(str(a), 0)) > 0:
			return true
	return false


## 未满足的 Requires 列表（保持原顺序）。
## researched：upgradeid→level；require_levels：upgradeid→最低等级（缺省 1）。
static func missing_requires(
	owned_buildings: Dictionary,
	requires: PackedStringArray,
	researched: Dictionary = {},
	require_levels: Dictionary = {}
) -> PackedStringArray:
	var out := PackedStringArray()
	for r in requires:
		var rid := str(r)
		var need := maxi(int(require_levels.get(rid, 1)), 1)
		if int(researched.get(rid, 0)) >= need:
			continue
		# 建筑类需求：仅当要求等级为 1 时可用场上建筑等价满足
		if need <= 1 and owns_requirement(owned_buildings, rid):
			continue
		out.append(rid)
	return out


## 竖切：建筑 Trains ∩ 锁死表；无表则原样返回。
static func filter_vertical_trains(
	building_id: String, trains: PackedStringArray
) -> PackedStringArray:
	return _filter_vertical_ids(building_id, trains, VERTICAL_TRAINS)


## 竖切：建筑 Researches ∩ 锁死表；无表则原样返回。
static func filter_vertical_researches(
	building_id: String, researches: PackedStringArray
) -> PackedStringArray:
	return _filter_vertical_ids(building_id, researches, VERTICAL_RESEARCHES)


static func _filter_vertical_ids(
	building_id: String, ids: PackedStringArray, table: Dictionary
) -> PackedStringArray:
	var allow = table.get(building_id.strip_edges(), null)
	if allow == null:
		return ids
	var have: Dictionary = {}
	for t in ids:
		have[str(t)] = true
	var out := PackedStringArray()
	for a in allow:
		var id := str(a)
		if have.has(id):
			out.append(id)
	return out


## 显示名（命令卡 tip）；缺 Name 则回退 id。
static func display_name(unit_id: String) -> String:
	var cat := CommandButtonCatalog.get_shared()
	var row := cat.get_unit_ui(unit_id)
	var n := str(row.get("name", "")).strip_edges()
	if n.is_empty():
		row = cat.get_upgrade_ui(unit_id)
		n = str(row.get("name", "")).strip_edges()
	return n if not n.is_empty() else unit_id


static func requires_tip(missing: PackedStringArray) -> String:
	if missing.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for m in missing:
		parts.append(display_name(str(m)))
	return "需要：" + ", ".join(parts)


static func get_upgrade(upgrade_id: String) -> UpgradeDataDef:
	var uid := upgrade_id.strip_edges()
	if uid.is_empty():
		return null
	var store := _def_store()
	if store == null or not store.has_method("ensure_table") or not store.has_method("get_row"):
		return null
	store.ensure_table(UpgradeDataDef.TABLE_NAME)
	return store.get_row(UpgradeDataDef.TABLE_NAME, uid) as UpgradeDataDef


static func is_upgrade_id(upgrade_id: String) -> bool:
	return get_upgrade(upgrade_id) != null


static func upgrade_gold(upgrade_id: String) -> int:
	var d := get_upgrade(upgrade_id)
	return int(round(d.goldbase)) if d != null else 0


static func upgrade_lumber(upgrade_id: String) -> int:
	var d := get_upgrade(upgrade_id)
	return int(round(d.lumberbase)) if d != null else 0


static func upgrade_time(upgrade_id: String) -> float:
	var d := get_upgrade(upgrade_id)
	return d.timebase if d != null else 0.0


static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")
