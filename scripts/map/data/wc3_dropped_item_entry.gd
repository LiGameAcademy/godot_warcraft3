class_name Wc3DroppedItemEntry
extends RefCounted

## 死亡掉落单条：{ id: FourCC, chance: int }（doo-units 嵌套 sets 的元素）。


var id: String = ""
var chance: int = 100


static func from_dict(d: Dictionary) -> Wc3DroppedItemEntry:
	var e := Wc3DroppedItemEntry.new()
	e.id = str(d.get("id", "")).strip_edges()
	e.chance = int(d.get("chance", 100))
	return e


func to_dict() -> Dictionary:
	return {"id": id, "chance": chance}


## 一套掉落（互斥组）：Array[{id, chance}]
static func set_from_variant(v: Variant) -> Array[Wc3DroppedItemEntry]:
	var out: Array[Wc3DroppedItemEntry] = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for item in v as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e := from_dict(item as Dictionary)
		if e.id.is_empty():
			continue
		out.append(e)
	return out


static func set_to_array(entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if e is Wc3DroppedItemEntry:
			out.append((e as Wc3DroppedItemEntry).to_dict())
		elif typeof(e) == TYPE_DICTIONARY:
			out.append((e as Dictionary).duplicate(true))
	return out


## 完整 droppedItemSets：Array[Array[{id,chance}]]
static func sets_from_variant(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for set_v in v as Array:
		out.append(set_to_array(set_from_variant(set_v)))
	return out


## 是否配置了至少一件死亡掉落（用于头顶白环）。
static func has_any_drops(dropped_item_sets: Variant) -> bool:
	if typeof(dropped_item_sets) != TYPE_ARRAY:
		return false
	for set_v in dropped_item_sets as Array:
		if typeof(set_v) != TYPE_ARRAY:
			continue
		for item in set_v as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not str((item as Dictionary).get("id", "")).strip_edges().is_empty():
				return true
	return false


## 展平为「组# / 物品 / 几率」行，供 UI 列表。
static func flatten_rows(dropped_item_sets: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(dropped_item_sets) != TYPE_ARRAY:
		return rows
	var si := 0
	for set_v in dropped_item_sets as Array:
		si += 1
		for e in set_from_variant(set_v):
			rows.append({
				"set_index": si,
				"id": e.id,
				"chance": e.chance,
				"name": _item_display_name(e.id),
			})
	return rows


static func _item_display_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var store := tree.root.get_node_or_null("/root/Wc3DefStore")
		if store != null:
			if store.has_method("ensure_table"):
				store.ensure_table(ItemDef.TABLE_NAME)
			if store.has_method("get_row"):
				var row: Resource = store.get_row(ItemDef.TABLE_NAME, item_id)
				if row is ItemDef:
					return (row as ItemDef).display_name()
	return item_id
