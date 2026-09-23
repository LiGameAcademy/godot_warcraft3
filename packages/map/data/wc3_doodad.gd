class_name Wc3Doodad
extends RefCounted

## 装饰物单条视图：指向 Wc3DoodadList 某一 index，读写即改 SoA。
## 不要脱离 List 长期缓存大量实例。


var list: Wc3DoodadList
var index: int = 0


var id: String:
	get:
		return str(list.ids[index])
	set(v):
		list.ids[index] = str(v)


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


## 由 angle 派生；写入时同步回弧度。
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


var life: int:
	get:
		return int(list.lives[index])
	set(v):
		list.lives[index] = v


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


## 与 doodads.json 单条同形（AoS 字典）。
func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"variation": variation,
		"position": {"x": pos_x, "y": pos_y, "z": pos_z},
		"angle": angle,
		"angleDegrees": angle_degrees,
		"scale": {"x": scale.x, "y": scale.y, "z": scale.z},
		"flags": flags,
		"life": life,
		"itemTablePtr": item_table_ptr,
		"droppedItemSets": dropped_item_sets.duplicate(),
		"creationNumber": creation_number,
	}
	if not skin_id.is_empty():
		d["skinId"] = skin_id
	return d


## Godot 世界坐标（已乘 WORLD_SCALE，Y-up）。
func godot_position() -> Vector3:
	return Wc3Coords.wc3_xy_to_godot(pos_x, pos_y, pos_z)


static func create(p_list: Wc3DoodadList, p_index: int) -> Wc3Doodad:
	var d := Wc3Doodad.new()
	d.list = p_list
	d.index = p_index
	return d
