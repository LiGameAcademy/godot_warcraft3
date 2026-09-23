class_name Wc3UnitPlacement
extends RefCounted

## 单位放置单条视图：指向 Wc3UnitList 某一 index，读写即改 SoA。
## 不要脱离 List 长期缓存大量实例。


var list: Wc3UnitList
var index: int = 0


var type_id: String:
	get:
		return str(list.type_ids[index])
	set(v):
		list.type_ids[index] = str(v)


## 别名：部分调用方习惯用 id。
var id: String:
	get:
		return type_id
	set(v):
		type_id = v


var variation: int:
	get:
		return int(list.variations[index])
	set(v):
		list.variations[index] = v


var position: Vector3:
	get:
		return Vector3(list.pos_x[index], list.pos_y[index], list.pos_z[index])
	set(v):
		list.pos_x[index] = v.x
		list.pos_y[index] = v.y
		list.pos_z[index] = v.z


var pos_x: float:
	get:
		return float(list.pos_x[index])
	set(v):
		list.pos_x[index] = v


var pos_y: float:
	get:
		return float(list.pos_y[index])
	set(v):
		list.pos_y[index] = v


var pos_z: float:
	get:
		return float(list.pos_z[index])
	set(v):
		list.pos_z[index] = v


var angle: float:
	get:
		return float(list.angles[index])
	set(v):
		list.angles[index] = v


var angle_degrees: float:
	get:
		return rad_to_deg(float(list.angles[index]))
	set(v):
		list.angles[index] = deg_to_rad(v)


var scale: Vector3:
	get:
		return Vector3(list.scale_x[index], list.scale_y[index], list.scale_z[index])
	set(v):
		list.scale_x[index] = v.x
		list.scale_y[index] = v.y
		list.scale_z[index] = v.z


var flags: int:
	get:
		return int(list.flags[index])
	set(v):
		list.flags[index] = v


var owner: int:
	get:
		return int(list.owners[index])
	set(v):
		list.owners[index] = v


var unknown: Array:
	get:
		var v: Variant = list.unknowns[index]
		return v as Array if typeof(v) == TYPE_ARRAY else [0, 0]
	set(v):
		list.unknowns[index] = v.duplicate() if typeof(v) == TYPE_ARRAY else [0, 0]


var hit_points: int:
	get:
		return int(list.hit_points[index])
	set(v):
		list.hit_points[index] = v


var mana_points: int:
	get:
		return int(list.mana_points[index])
	set(v):
		list.mana_points[index] = v


var item_table_ptr: int:
	get:
		return int(list.item_table_ptrs[index])
	set(v):
		list.item_table_ptrs[index] = v


var dropped_item_sets: Array:
	get:
		var v: Variant = list.dropped_item_sets[index]
		return v as Array if typeof(v) == TYPE_ARRAY else []
	set(v):
		list.dropped_item_sets[index] = v.duplicate() if typeof(v) == TYPE_ARRAY else []


var gold_amount: int:
	get:
		return int(list.gold_amounts[index])
	set(v):
		list.gold_amounts[index] = v


var target_acquisition: float:
	get:
		return float(list.target_acquisitions[index])
	set(v):
		list.target_acquisitions[index] = v


var hero_level: int:
	get:
		return int(list.hero_levels[index])
	set(v):
		list.hero_levels[index] = v


var strength: int:
	get:
		return int(list.strengths[index])
	set(v):
		list.strengths[index] = v


var agility: int:
	get:
		return int(list.agilities[index])
	set(v):
		list.agilities[index] = v


var intelligence: int:
	get:
		return int(list.intelligences[index])
	set(v):
		list.intelligences[index] = v


var inventory: Array:
	get:
		var v: Variant = list.inventories[index]
		return v as Array if typeof(v) == TYPE_ARRAY else []
	set(v):
		list.inventories[index] = v.duplicate() if typeof(v) == TYPE_ARRAY else []


var abilities: Array:
	get:
		var v: Variant = list.abilities[index]
		return v as Array if typeof(v) == TYPE_ARRAY else []
	set(v):
		list.abilities[index] = v.duplicate() if typeof(v) == TYPE_ARRAY else []


var random: Dictionary:
	get:
		var v: Variant = list.randoms[index]
		return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}
	set(v):
		list.randoms[index] = v.duplicate() if typeof(v) == TYPE_DICTIONARY else {}


var custom_color: int:
	get:
		return int(list.custom_colors[index])
	set(v):
		list.custom_colors[index] = v


var waygate: int:
	get:
		return int(list.waygates[index])
	set(v):
		list.waygates[index] = v


var creation_number: int:
	get:
		return int(list.creation_numbers[index])
	set(v):
		list.creation_numbers[index] = v


var skin_id: String:
	get:
		return str(list.skin_ids[index])
	set(v):
		list.skin_ids[index] = str(v)


func is_valid() -> bool:
	return list != null and list.in_bounds(index)


func to_dict() -> Dictionary:
	var d := {
		"typeId": type_id,
		"variation": variation,
		"position": {"x": pos_x, "y": pos_y, "z": pos_z},
		"angle": angle,
		"angleDegrees": angle_degrees,
		"scale": {"x": scale.x, "y": scale.y, "z": scale.z},
		"flags": flags,
		"owner": owner,
		"unknown": unknown.duplicate(),
		"hitPoints": hit_points,
		"manaPoints": mana_points,
		"itemTablePtr": item_table_ptr,
		"droppedItemSets": dropped_item_sets.duplicate(),
		"goldAmount": gold_amount,
		"targetAcquisition": target_acquisition,
		"heroLevel": hero_level,
		"strength": strength,
		"agility": agility,
		"intelligence": intelligence,
		"inventory": inventory.duplicate(),
		"abilities": abilities.duplicate(),
		"random": random.duplicate(),
		"customColor": custom_color,
		"waygate": waygate,
		"creationNumber": creation_number,
	}
	if not skin_id.is_empty():
		d["skinId"] = skin_id
	return d


func godot_position() -> Vector3:
	return Wc3Coords.wc3_xy_to_godot(pos_x, pos_y, pos_z)


static func create(p_list: Wc3UnitList, p_index: int) -> Wc3UnitPlacement:
	var u := Wc3UnitPlacement.new()
	u.list = p_list
	u.index = p_index
	return u
