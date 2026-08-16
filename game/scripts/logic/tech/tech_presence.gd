class_name TechPresence
extends RefCounted

## 玩家已完工建筑/单位存在性（供 Requires 判定）。
## 升级链：需要 htow 时，hkee/hcas 也算满足（经典 Melee）。

## 人族竖切：祭坛只训大法师；兵营只训步兵/火枪手。
const VERTICAL_TRAINS := {
	"halt": ["Hamg"],
	"hbar": ["hfoo", "hrif"],
	"htow": ["hpea"],
	"hkee": ["hpea"],
	"hcas": ["hpea"],
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


## 场上英雄 + 训练队列中的英雄（开训即占名额）。
static func count_heroes_with_queues(unit_host: Node, owner_id: int) -> int:
	var n := count_heroes(unit_host, owner_id)
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
			if _HERO_IDS.has(uid):
				n += 1
	return n


static func is_hero_id(unit_id: String) -> bool:
	return _HERO_IDS.has(unit_id.strip_edges())


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
static func missing_requires(
	owned_buildings: Dictionary, requires: PackedStringArray
) -> PackedStringArray:
	var out := PackedStringArray()
	for r in requires:
		if not owns_requirement(owned_buildings, str(r)):
			out.append(str(r))
	return out


## 竖切：建筑 Trains ∩ 锁死表；无表则原样返回。
static func filter_vertical_trains(
	building_id: String, trains: PackedStringArray
) -> PackedStringArray:
	var allow = VERTICAL_TRAINS.get(building_id.strip_edges(), null)
	if allow == null:
		return trains
	var have: Dictionary = {}
	for t in trains:
		have[str(t)] = true
	var out := PackedStringArray()
	for a in allow:
		var id := str(a)
		if have.has(id):
			out.append(id)
	return out


## 显示名（命令卡 tip）；缺 Name 则回退 id。
static func display_name(unit_id: String) -> String:
	var row := CommandButtonCatalog.get_shared().get_unit_ui(unit_id)
	var n := str(row.get("name", "")).strip_edges()
	return n if not n.is_empty() else unit_id


static func requires_tip(missing: PackedStringArray) -> String:
	if missing.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for m in missing:
		parts.append(display_name(str(m)))
	return "需要：" + ", ".join(parts)
