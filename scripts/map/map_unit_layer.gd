class_name MapUnitLayer
extends Node3D
## 单位 / 建筑层。


@export var try_load_glb: bool = true

var _catalog: Wc3IdCatalog
var _cache: MapModelCache


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache


func build(units_json: Dictionary) -> void:
	_clear_children()
	var loaded := 0
	var placeholder := 0
	for u in units_json.get("units", []):
		var type_id := str(u.get("typeId", ""))
		var variation := int(u.get("variation", 0))
		var pos: Dictionary = u.get("position", {})
		var owner_id := int(u.get("owner", 12))
		var angle := float(u.get("angle", 0.0))
		var scale_data: Dictionary = u.get("scale", {})
		var gpos := Wc3Coords.wc3_xy_to_godot(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0)),
			float(pos.get("z", 0.0))
		)
		var node := _make_unit_node(type_id, variation, owner_id)
		if node.get_meta("is_placeholder", false):
			placeholder += 1
		else:
			loaded += 1
			var sx := float(scale_data.get("x", 1.0))
			var sy := float(scale_data.get("y", 1.0))
			var sz := float(scale_data.get("z", 1.0))
			var b := node.scale
			node.scale = Vector3(b.x * sx, b.y * sz, b.z * sy)
		node.name = "%s_%s" % [type_id, str(u.get("creationNumber", 0))]
		node.position = gpos
		node.rotation.y = Wc3Coords.yaw_wc3_to_godot(angle)
		add_child(node)
	print("Units: glb=%d placeholder=%d" % [loaded, placeholder])


func _make_unit_node(type_id: String, variation: int, owner_id: int) -> Node3D:
	if try_load_glb:
		var glb := _catalog.converted_glb_path(type_id, variation)
		if not glb.is_empty():
			var inst := _cache.instance_glb(glb)
			if inst:
				inst.set_meta("is_placeholder", false)
				_cache.autoplay_stand(inst)
				return inst
	var ph := MapPlaceholders.make_entity(type_id, owner_id, true)
	ph.set_meta("is_placeholder", true)
	return ph


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
