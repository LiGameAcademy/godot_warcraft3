class_name Wc3DoodadList
extends RefCounted

## 对应 map-parsed/*/doodads.json 的内存主存储（SoA 平行数组）。
## 单条请用 at(i) → Wc3Doodad，不要手写 list.ids[i]。
## 存盘 to_dict() 仍输出 AoS（与现有 doodads.json 同形）。


var format_version: int = 8
var subversion: int = 11
## doo 文件尾「特殊装饰物」段（与 doodads[] 并列，非 SoA 主表）。
var special_doodads: Array = []
## 解析诊断；非编辑权威。缺省 -1 表示未从 JSON 读到。
var bytes_remaining: int = -1

## 平行数组，长度恒为 count()。
var ids: PackedStringArray = PackedStringArray()
var variations: PackedInt32Array = PackedInt32Array()
var pos_x: PackedFloat32Array = PackedFloat32Array()
var pos_y: PackedFloat32Array = PackedFloat32Array()
var pos_z: PackedFloat32Array = PackedFloat32Array()
var angles: PackedFloat32Array = PackedFloat32Array()
var scale_x: PackedFloat32Array = PackedFloat32Array()
var scale_y: PackedFloat32Array = PackedFloat32Array()
var scale_z: PackedFloat32Array = PackedFloat32Array()
var flags: PackedInt32Array = PackedInt32Array()
var lives: PackedInt32Array = PackedInt32Array()
var item_table_ptrs: PackedInt32Array = PackedInt32Array()
## 每元素为 Array（掉落表）；稀疏结构不适合 Packed*
var dropped_item_sets: Array = []
var creation_numbers: PackedInt32Array = PackedInt32Array()
## 1.32+ 可选；缺省 ""。
var skin_ids: PackedStringArray = PackedStringArray()


func count() -> int:
	return ids.size()


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
		and lives.size() == n
		and item_table_ptrs.size() == n
		and dropped_item_sets.size() == n
		and creation_numbers.size() == n
		and skin_ids.size() == n
	)


func in_bounds(index: int) -> bool:
	return index >= 0 and index < count()


## 按需创建单条视图（非缓存；短生命周期持有即可）。
func at(index: int) -> Wc3Doodad:
	if not in_bounds(index):
		return null
	return Wc3Doodad.create(self, index)


func clear() -> void:
	ids.clear()
	variations.clear()
	pos_x.clear()
	pos_y.clear()
	pos_z.clear()
	angles.clear()
	scale_x.clear()
	scale_y.clear()
	scale_z.clear()
	flags.clear()
	lives.clear()
	item_table_ptrs.clear()
	dropped_item_sets.clear()
	creation_numbers.clear()
	skin_ids.clear()
	special_doodads.clear()
	bytes_remaining = -1


## 追加一条；返回新 index。entry 为 doodads.json 单条 Dictionary。
func append_dict(entry: Dictionary) -> int:
	var pos: Dictionary = entry.get("position", {}) as Dictionary
	var sc: Dictionary = entry.get("scale", {}) as Dictionary
	ids.append(str(entry.get("id", "")))
	variations.append(int(entry.get("variation", 0)))
	pos_x.append(float(pos.get("x", 0.0)))
	pos_y.append(float(pos.get("y", 0.0)))
	pos_z.append(float(pos.get("z", 0.0)))
	angles.append(float(entry.get("angle", 0.0)))
	scale_x.append(float(sc.get("x", 1.0)))
	scale_y.append(float(sc.get("y", 1.0)))
	scale_z.append(float(sc.get("z", 1.0)))
	flags.append(int(entry.get("flags", 0)))
	lives.append(int(entry.get("life", 100)))
	item_table_ptrs.append(int(entry.get("itemTablePtr", -1)))
	var drops: Variant = entry.get("droppedItemSets", [])
	dropped_item_sets.append(drops.duplicate() if typeof(drops) == TYPE_ARRAY else [])
	creation_numbers.append(int(entry.get("creationNumber", count())))
	skin_ids.append(str(entry.get("skinId", "")))
	return count() - 1


func remove_at(index: int) -> bool:
	if not in_bounds(index):
		return false
	ids.remove_at(index)
	variations.remove_at(index)
	pos_x.remove_at(index)
	pos_y.remove_at(index)
	pos_z.remove_at(index)
	angles.remove_at(index)
	scale_x.remove_at(index)
	scale_y.remove_at(index)
	scale_z.remove_at(index)
	flags.remove_at(index)
	lives.remove_at(index)
	item_table_ptrs.remove_at(index)
	dropped_item_sets.remove_at(index)
	creation_numbers.remove_at(index)
	skin_ids.remove_at(index)
	return true


## 用 doodads.json 单条 Dictionary 覆盖 index 槽位（保持顺序）。
func set_dict_at(index: int, entry: Dictionary) -> bool:
	if not in_bounds(index):
		return false
	var pos: Dictionary = entry.get("position", {}) as Dictionary
	var sc: Dictionary = entry.get("scale", {}) as Dictionary
	ids[index] = str(entry.get("id", ""))
	variations[index] = int(entry.get("variation", 0))
	pos_x[index] = float(pos.get("x", 0.0))
	pos_y[index] = float(pos.get("y", 0.0))
	pos_z[index] = float(pos.get("z", 0.0))
	angles[index] = float(entry.get("angle", 0.0))
	scale_x[index] = float(sc.get("x", 1.0))
	scale_y[index] = float(sc.get("y", 1.0))
	scale_z[index] = float(sc.get("z", 1.0))
	flags[index] = int(entry.get("flags", 0))
	lives[index] = int(entry.get("life", 100))
	item_table_ptrs[index] = int(entry.get("itemTablePtr", -1))
	var drops: Variant = entry.get("droppedItemSets", [])
	dropped_item_sets[index] = drops.duplicate() if typeof(drops) == TYPE_ARRAY else []
	creation_numbers[index] = int(entry.get("creationNumber", creation_numbers[index]))
	skin_ids[index] = str(entry.get("skinId", ""))
	return true


func find_index_by_creation_number(cn: int) -> int:
	for i in range(count()):
		if int(creation_numbers[i]) == cn:
			return i
	return -1


## 按 type id 计数（对应 JSON `byId`；派生，非权威）。
func rebuild_by_id() -> Dictionary:
	var by_id: Dictionary = {}
	for i in range(count()):
		var tid := str(ids[i])
		by_id[tid] = int(by_id.get(tid, 0)) + 1
	return by_id


static func _clone_special_doodads(src: Variant) -> Array:
	var out: Array = []
	if typeof(src) != TYPE_ARRAY:
		return out
	for item in src as Array:
		if typeof(item) == TYPE_DICTIONARY:
			out.append((item as Dictionary).duplicate(true))
	return out


## 从 doodads.json 根 Dictionary / doodads[] 加载。
static func from_dict(d: Dictionary) -> Wc3DoodadList:
	var list := Wc3DoodadList.new()
	list.format_version = int(d.get("formatVersion", 8))
	list.subversion = int(d.get("subversion", 11))
	list.special_doodads = _clone_special_doodads(d.get("specialDoodads", []))
	if d.has("_bytesRemaining"):
		list.bytes_remaining = int(d.get("_bytesRemaining", 0))
	var arr: Variant = d.get("doodads", [])
	if typeof(arr) != TYPE_ARRAY:
		return list
	for item in arr as Array:
		if typeof(item) == TYPE_DICTIONARY:
			list.append_dict(item as Dictionary)
	if not list.is_valid():
		AppLog.warn(
			AppLog.Layer.DATA,
			"DoodadList",
			"from_dict 长度不一致 count=%d" % list.count()
		)
	else:
		AppLog.debug(
			AppLog.Layer.DATA,
			"DoodadList",
			"from_dict n=%d special=%d ver=%d"
			% [list.count(), list.special_doodads.size(), list.format_version]
		)
	return list


## 与现有 doodads.json 同形（AoS）；平行数组拆回对象；`byId` 现算。
func to_dict() -> Dictionary:
	var doodads: Array = []
	doodads.resize(count())
	for i in range(count()):
		doodads[i] = at(i).to_dict()
	var out := {
		"formatVersion": format_version,
		"subversion": subversion,
		"count": count(),
		"byId": rebuild_by_id(),
		"doodads": doodads,
		"specialDoodads": _clone_special_doodads(special_doodads),
	}
	if bytes_remaining >= 0:
		out["_bytesRemaining"] = bytes_remaining
	return out


## 兼容旧代码：仅 doodads[]（无 header）。
func to_entries_array() -> Array:
	var out: Array = []
	out.resize(count())
	for i in range(count()):
		out[i] = at(i).to_dict()
	return out


static func load_json_path(res_or_abs: String) -> Wc3DoodadList:
	var disk_path := RuntimeAssets.project_abs(res_or_abs)
	if not FileAccess.file_exists(disk_path):
		push_error("Wc3DoodadList: 文件不存在 %s" % disk_path)
		return null
	var text := RuntimeAssets.read_utf8_text(disk_path)
	if text.is_empty():
		push_error("Wc3DoodadList: 无法读取或含非法字符 %s" % disk_path)
		return null
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Wc3DoodadList: JSON 根不是对象 %s" % disk_path)
		return null
	return from_dict(parsed as Dictionary)
