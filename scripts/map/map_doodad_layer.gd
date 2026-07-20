class_name MapDoodadLayer
extends Node3D
## 静物 / 装饰物层。


@export var try_load_glb: bool = true
@export var multimesh_threshold: int = 8

var _catalog: Wc3IdCatalog
var _cache: MapModelCache


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache


func build(doodads_json: Dictionary) -> void:
	_clear_children()
	var doodads: Array = doodads_json.get("doodads", [])
	if doodads.is_empty():
		return

	var groups: Dictionary = {}
	for d in doodads:
		var type_id := str(d.get("id", ""))
		var variation := int(d.get("variation", 0))
		var key := "%s#%d" % [type_id, variation]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(d)

	var glb_groups := 0
	var ph_groups := 0
	for key_variant in groups.keys():
		var key := str(key_variant)
		var list: Array = groups[key]
		var parts: PackedStringArray = key.split("#")
		var type_id: String = parts[0] if parts.size() > 0 else ""
		var variation: int = int(parts[1]) if parts.size() > 1 else 0
		var glb := _catalog.converted_glb_path(type_id, variation) if try_load_glb else ""

		if not glb.is_empty() and list.size() >= multimesh_threshold:
			if _place_multimesh_group(type_id, variation, glb, list):
				glb_groups += 1
				continue

		if not glb.is_empty():
			for d in list:
				_place_doodad_instance(type_id, glb, d)
			glb_groups += 1
		else:
			for d in list:
				_place_doodad_placeholder(type_id, d)
			ph_groups += 1

	print("Doodad groups: glb=%d placeholder=%d" % [glb_groups, ph_groups])


func _place_multimesh_group(type_id: String, variation: int, glb: String, list: Array) -> bool:
	var mesh := _cache.mesh_from_glb(glb)
	if mesh == null:
		return false
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in range(list.size()):
		mm.set_instance_transform(i, _doodad_transform(list[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_%s_%d" % [type_id, variation]
	mmi.multimesh = mm
	add_child(mmi)
	return true


func _place_doodad_instance(type_id: String, glb: String, d: Dictionary) -> void:
	var node := _cache.instance_glb(glb)
	if node == null:
		_place_doodad_placeholder(type_id, d)
		return
	node.name = "%s_%s" % [type_id, str(d.get("creationNumber", 0))]
	_apply_doodad_xform(node, d, true)
	add_child(node)


func _place_doodad_placeholder(type_id: String, d: Dictionary) -> void:
	var node := MapPlaceholders.make_entity(type_id, -1, false)
	_apply_doodad_xform(node, d, false)
	node.scale *= 0.8
	add_child(node)


func _apply_doodad_xform(node: Node3D, d: Dictionary, multiply_imported_scale: bool) -> void:
	var pos: Dictionary = d.get("position", {})
	var scale_data: Dictionary = d.get("scale", {})
	var angle := float(d.get("angle", 0.0))
	node.position = Wc3Coords.wc3_xy_to_godot(
		float(pos.get("x", 0.0)),
		float(pos.get("y", 0.0)),
		float(pos.get("z", 0.0))
	)
	node.rotation.y = Wc3Coords.yaw_wc3_to_godot(angle)
	var sx := float(scale_data.get("x", 1.0))
	var sy := float(scale_data.get("y", 1.0))
	var sz := float(scale_data.get("z", 1.0))
	if multiply_imported_scale:
		var b := node.scale
		node.scale = Vector3(b.x * sx, b.y * sz, b.z * sy)
	else:
		node.scale = Vector3(sx, sz, sy)


func _doodad_transform(d: Dictionary) -> Transform3D:
	var pos: Dictionary = d.get("position", {})
	var scale_data: Dictionary = d.get("scale", {})
	var angle := float(d.get("angle", 0.0))
	var gpos := Wc3Coords.wc3_xy_to_godot(
		float(pos.get("x", 0.0)),
		float(pos.get("y", 0.0)),
		float(pos.get("z", 0.0))
	)
	var sx := float(scale_data.get("x", 1.0))
	var sy := float(scale_data.get("y", 1.0))
	var sz := float(scale_data.get("z", 1.0))
	var xf := Transform3D.IDENTITY
	xf = xf.scaled(Vector3(sx, sz, sy) * Wc3Coords.WORLD_SCALE)
	xf = xf.rotated(Vector3.UP, Wc3Coords.yaw_wc3_to_godot(angle))
	xf.origin = gpos
	return xf


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
