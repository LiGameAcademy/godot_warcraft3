class_name Wc3UnitList
extends RefCounted

## 对应 map-parsed/*/units.json 的内存主存储（SoA 平行数组）。
## 单条请用 at(i) → Wc3UnitPlacement，不要手写 list.type_ids[i]。
## 存盘 to_dict() 仍输出 AoS（与现有 units.json 同形）。


var format_version: int = 8
var subversion: int = 11
## 解析诊断；非编辑权威。缺省 -1 表示未从 JSON 读到。
var bytes_remaining: int = -1

## 平行数组，长度恒为 count()。
var type_ids: PackedStringArray = PackedStringArray()
var variations: PackedInt32Array = PackedInt32Array()
var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var pos_z: PackedFloat32Array = PackedFloat32Array()
var angles: PackedFloat32Array = PackedFloat32Array()
var scale_x: PackedFloat32Array = PackedFloat32Array()
var scale_y: PackedFloat32Array = PackedFloat32Array()
var scale_z: PackedFloat32Array = PackedFloat32Array()
var flags: PackedInt32Array = PackedInt32Array()
var owners: PackedInt32Array = PackedInt32Array()
## 原始 unknown[2]；每元素 PackedByteArray 或 Array
var unknowns: Array = []
var hit_points: PackedInt32Array = PackedInt32Array()
var mana_points: PackedInt32Array = PackedInt32Array()
var item_table_ptrs: PackedInt32Array = PackedInt32Array()
var dropped_item_sets: Array = []
var gold_amounts: PackedInt32Array = PackedInt32Array()
var target_acquisitions: PackedFloat32Array = PackedFloat32Array()
var hero_levels: PackedInt32Array = PackedInt32Array()
var strengths: PackedInt32Array = PackedInt32Array()
var agilities: PackedInt32Array = PackedInt32Array()
var intelligences: PackedInt32Array = PackedInt32Array()
var inventories: Array = [] ## 每元素 Array
var abilities: Array = [] ## 每元素 Array
var randoms: Array = [] ## 每元素 Dictionary
var custom_colors: PackedInt32Array = PackedInt32Array()
var waygates: PackedInt32Array = PackedInt32Array()
var creation_numbers: PackedInt32Array = PackedInt32Array()
var skin_ids: PackedStringArray = PackedStringArray()


func count() -> int:
	return type_ids.size()


func is_valid() -> bool:
	var n := count()
	return (
		variations.size() == n
		and pos_x.size() == n
		and pos_y.size() == n
		and pos_z.size() == n
		and angles.size() == n
		and scale_x.size() == n
		and scale_y.size() == n
		and scale_z.size() == n
		and flags.size() == n
		and owners.size() == n
		and unknowns.size() == n
		and hit_points.size() == n
		and mana_points.size() == n
		and item_table_ptrs.size() == n
		and dropped_item_sets.size() == n
		and gold_amounts.size() == n
		and target_acquisitions.size() == n
		and hero_levels.size() == n
		and strengths.size() == n
		and agilities.size() == n
		and intelligences.size() == n
		and inventories.size() == n
		and abilities.size() == n
		and randoms.size() == n
		and custom_colors.size() == n
		and waygates.size() == n
		and creation_numbers.size() == n
		and skin_ids.size() == n
	)


func in_bounds(index: int) -> bool:
	return index >= 0 and index < count()


func at(index: int) -> Wc3UnitPlacement:
	if not in_bounds(index):
		return null
	return Wc3UnitPlacement.create(self, index)


func clear() -> void:
	type_ids.clear()
	variations.clear()
	pos_x.clear()
	pos_y.clear()
	pos_z.clear()
	angles.clear()
	scale_x.clear()
	scale_y.clear()
	scale_z.clear()
	flags.clear()
	owners.clear()
	unknowns.clear()
	hit_points.clear()
	mana_points.clear()
	item_table_ptrs.clear()
	dropped_item_sets.clear()
	gold_amounts.clear()
	target_acquisitions.clear()
	hero_levels.clear()
	strengths.clear()
	agilities.clear()
	intelligences.clear()
	inventories.clear()
	abilities.clear()
	randoms.clear()
	custom_colors.clear()
	waygates.clear()
	creation_numbers.clear()
	skin_ids.clear()
	bytes_remaining = -1


func append_dict(entry: Dictionary) -> int:
	var pos: Dictionary = entry.get("position", {}) as Dictionary
	var sc: Dictionary = entry.get("scale", {}) as Dictionary
	type_ids.append(str(entry.get("typeId", entry.get("id", ""))))
	variations.append(int(entry.get("variation", 0)))
	pos_x.append(float(pos.get("x", 0.0)))
	pos_y.append(float(pos.get("y", 0.0)))
	pos_z.append(float(pos.get("z", 0.0)))
	angles.append(float(entry.get("angle", 0.0)))
	scale_x.append(float(sc.get("x", 1.0)))
	scale_y.append(float(sc.get("y", 1.0)))
	scale_z.append(float(sc.get("z", 1.0)))
	flags.append(int(entry.get("flags", 0)))
	owners.append(int(entry.get("owner", entry.get("player", 12))))
	var unk: Variant = entry.get("unknown", [0, 0])
	unknowns.append(unk.duplicate() if typeof(unk) == TYPE_ARRAY else [0, 0])
	hit_points.append(int(entry.get("hitPoints", -1)))
	mana_points.append(int(entry.get("manaPoints", -1)))
	item_table_ptrs.append(int(entry.get("itemTablePtr", -1)))
	var drops: Variant = entry.get("droppedItemSets", [])
	dropped_item_sets.append(drops.duplicate() if typeof(drops) == TYPE_ARRAY else [])
	gold_amounts.append(int(entry.get("goldAmount", 0)))
	target_acquisitions.append(float(entry.get("targetAcquisition", -1.0)))
	hero_levels.append(int(entry.get("heroLevel", 1)))
	strengths.append(int(entry.get("strength", 0)))
	agilities.append(int(entry.get("agility", 0)))
	intelligences.append(int(entry.get("intelligence", 0)))
	var inv: Variant = entry.get("inventory", [])
	inventories.append(inv.duplicate() if typeof(inv) == TYPE_ARRAY else [])
	var ab: Variant = entry.get("abilities", [])
	abilities.append(ab.duplicate() if typeof(ab) == TYPE_ARRAY else [])
	var rnd: Variant = entry.get("random", {})
	randoms.append(rnd.duplicate() if typeof(rnd) == TYPE_DICTIONARY else {})
	custom_colors.append(int(entry.get("customColor", -1)))
	waygates.append(int(entry.get("waygate", -1)))
	creation_numbers.append(int(entry.get("creationNumber", count())))
	skin_ids.append(str(entry.get("skinId", "")))
	return count() - 1


func remove_at(index: int) -> bool:
	if not in_bounds(index):
		return false
	type_ids.remove_at(index)
	variations.remove_at(index)
	pos_x.remove_at(index)
	pos_y.remove_at(index)
	pos_z.remove_at(index)
	angles.remove_at(index)
	scale_x.remove_at(index)
	scale_y.remove_at(index)
	scale_z.remove_at(index)
	flags.remove_at(index)
	owners.remove_at(index)
	unknowns.remove_at(index)
	hit_points.remove_at(index)
	mana_points.remove_at(index)
	item_table_ptrs.remove_at(index)
	dropped_item_sets.remove_at(index)
	gold_amounts.remove_at(index)
	target_acquisitions.remove_at(index)
	hero_levels.remove_at(index)
	strengths.remove_at(index)
	agilities.remove_at(index)
	intelligences.remove_at(index)
	inventories.remove_at(index)
	abilities.remove_at(index)
	randoms.remove_at(index)
	custom_colors.remove_at(index)
	waygates.remove_at(index)
	creation_numbers.remove_at(index)
	skin_ids.remove_at(index)
	return true


## 用 units.json 单条 Dictionary 覆盖 index 槽位（保持顺序）。
func set_dict_at(index: int, entry: Dictionary) -> bool:
	if not in_bounds(index):
		return false
	var pos: Dictionary = entry.get("position", {}) as Dictionary
	var sc: Dictionary = entry.get("scale", {}) as Dictionary
	type_ids[index] = str(entry.get("typeId", entry.get("id", "")))
	variations[index] = int(entry.get("variation", 0))
	pos_x[index] = float(pos.get("x", 0.0))
	pos_y[index] = float(pos.get("y", 0.0))
	pos_z[index] = float(pos.get("z", 0.0))
	angles[index] = float(entry.get("angle", 0.0))
	scale_x[index] = float(sc.get("x", 1.0))
	scale_y[index] = float(sc.get("y", 1.0))
	scale_z[index] = float(sc.get("z", 1.0))
	flags[index] = int(entry.get("flags", 0))
	owners[index] = int(entry.get("owner", entry.get("player", 12)))
	var unk: Variant = entry.get("unknown", [0, 0])
	unknowns[index] = unk.duplicate() if typeof(unk) == TYPE_ARRAY else [0, 0]
	hit_points[index] = int(entry.get("hitPoints", -1))
	mana_points[index] = int(entry.get("manaPoints", -1))
	item_table_ptrs[index] = int(entry.get("itemTablePtr", -1))
	var drops: Variant = entry.get("droppedItemSets", [])
	dropped_item_sets[index] = drops.duplicate() if typeof(drops) == TYPE_ARRAY else []
	gold_amounts[index] = int(entry.get("goldAmount", 0))
	target_acquisitions[index] = float(entry.get("targetAcquisition", -1.0))
	hero_levels[index] = int(entry.get("heroLevel", 1))
	strengths[index] = int(entry.get("strength", 0))
	agilities[index] = int(entry.get("agility", 0))
	intelligences[index] = int(entry.get("intelligence", 0))
	var inv: Variant = entry.get("inventory", [])
	inventories[index] = inv.duplicate() if typeof(inv) == TYPE_ARRAY else []
	var ab: Variant = entry.get("abilities", [])
	abilities[index] = ab.duplicate() if typeof(ab) == TYPE_ARRAY else []
	var rnd: Variant = entry.get("random", {})
	randoms[index] = rnd.duplicate() if typeof(rnd) == TYPE_DICTIONARY else {}
	custom_colors[index] = int(entry.get("customColor", -1))
	waygates[index] = int(entry.get("waygate", -1))
	creation_numbers[index] = int(entry.get("creationNumber", creation_numbers[index]))
	skin_ids[index] = str(entry.get("skinId", ""))
	return true


func find_index_by_creation_number(cn: int) -> int:
	for i in range(count()):
		if int(creation_numbers[i]) == cn:
			return i
	return -1


## 按 typeId 计数（JSON `byTypeId`；派生）。
func rebuild_by_type_id() -> Dictionary:
	var by_type: Dictionary = {}
	for i in range(count()):
		var tid := str(type_ids[i])
		by_type[tid] = int(by_type.get(tid, 0)) + 1
	return by_type


## 按 owner 计数（JSON `byOwner`；键为字符串，与 map-parse 同形）。
func rebuild_by_owner() -> Dictionary:
	var by_owner: Dictionary = {}
	for i in range(count()):
		var key := str(int(owners[i]))
		by_owner[key] = int(by_owner.get(key, 0)) + 1
	return by_owner


static func from_dict(d: Dictionary) -> Wc3UnitList:
	var list := Wc3UnitList.new()
	list.format_version = int(d.get("formatVersion", 8))
	list.subversion = int(d.get("subversion", 11))
	if d.has("_bytesRemaining"):
		list.bytes_remaining = int(d.get("_bytesRemaining", 0))
	var arr: Variant = d.get("units", [])
	if typeof(arr) != TYPE_ARRAY:
		return list
	for item in arr as Array:
		if typeof(item) == TYPE_DICTIONARY:
			list.append_dict(item as Dictionary)
	if not list.is_valid():
		AppLog.warn(
			AppLog.Layer.DATA,
			"UnitList",
			"from_dict 长度不一致 count=%d" % list.count()
		)
	else:
		AppLog.debug(
			AppLog.Layer.DATA,
			"UnitList",
			"from_dict n=%d ver=%d" % [list.count(), list.format_version]
		)
	return list


func to_dict() -> Dictionary:
	var units: Array = []
	units.resize(count())
	for i in range(count()):
		units[i] = at(i).to_dict()
	var out := {
		"formatVersion": format_version,
		"subversion": subversion,
		"count": count(),
		"byTypeId": rebuild_by_type_id(),
		"byOwner": rebuild_by_owner(),
		"units": units,
	}
	if bytes_remaining >= 0:
		out["_bytesRemaining"] = bytes_remaining
	return out


func to_entries_array() -> Array:
	var out: Array = []
	out.resize(count())
	for i in range(count()):
		out[i] = at(i).to_dict()
	return out


static func load_json_path(res_or_abs: String) -> Wc3UnitList:
	var disk_path := RuntimeAssets.project_abs(res_or_abs)
	if not FileAccess.file_exists(disk_path):
		push_error("Wc3UnitList: 文件不存在 %s" % disk_path)
		return null
	var text := RuntimeAssets.read_utf8_text(disk_path)
	if text.is_empty():
		push_error("Wc3UnitList: 无法读取或含非法字符 %s" % disk_path)
		return null
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Wc3UnitList: JSON 根不是对象 %s" % disk_path)
		return null
	return from_dict(parsed as Dictionary)
