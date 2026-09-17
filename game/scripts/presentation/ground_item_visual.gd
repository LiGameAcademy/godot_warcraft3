class_name GroundItemVisual
extends RefCounted

## 地面道具表现与屏幕命中。
## 优先走已烘焙 .scn / .gltf；失败时用金色小箱子占位。

const LABEL_HEIGHT := 0.72
const PICK_PAD_PX := 28.0


static func attach(ground: GroundItem, cache: MapModelCache = null) -> void:
	if ground == null or not is_instance_valid(ground) or ground.item == null:
		return
	# 清旧表现（重复 attach / 热重载）
	for c in ground.get_children():
		c.queue_free()
	var visual := _instance_model(ground.item.type_id, cache)
	if visual != null:
		ground.add_child(visual)
		var d := ItemCatalog.data(ground.item.type_id)
		var s := d.scale if d != null and d.scale > 0.0 else 1.0
		# .scn 子节点通常已带 0.01；只叠 ItemDef.scale，不再乘 WORLD_SCALE
		if not is_equal_approx(s, 1.0):
			visual.scale *= s
		AnimPlayback.play_logical(visual, "Stand", 0.0, cache)
	else:
		ground.add_child(_make_placeholder())
	ground.add_child(_make_label(ItemCatalog.title(ground.item.type_id)))


static func pick_at(host: Node, camera: Camera3D, screen: Vector2) -> GroundItem:
	if host == null or camera == null:
		return null
	var best: GroundItem
	var distance := PICK_PAD_PX
	for child in host.get_children():
		if not child is GroundItem or child.claimed or camera.is_position_behind(child.global_position):
			continue
		var foot: Vector2 = camera.unproject_position(child.global_position)
		var center: Vector2 = camera.unproject_position(child.global_position + Vector3.UP * 0.4)
		var score := minf(foot.distance_to(screen), center.distance_to(screen))
		if score < distance:
			distance = score
			best = child
	return best


static func _instance_model(type_id: String, cache: MapModelCache) -> Node3D:
	if cache == null:
		return null
	var logical := ItemCatalog.model_path(type_id)
	if logical.is_empty():
		return null
	# 优先 .gltf（外链贴图），再 .glb；instance_glb 会自动吃同目录 .scn
	var path := ItemCatalog.resolved_model_path(type_id)
	if path.is_empty():
		path = RuntimeAssets.converted_path(logical)
	if path.is_empty():
		return null
	return cache.instance_glb(path)


static func _make_placeholder() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.48, 0.32, 0.36)
	mesh.mesh = box
	mesh.position.y = 0.18
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.68, 0.18)
	material.metallic = 0.4
	mesh.material_override = material
	return mesh


static func _make_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position.y = LABEL_HEIGHT
	label.font_size = 22
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 4
	label.outline_modulate = Color(0, 0, 0, 0.75)
	label.modulate = Color(1.0, 0.9, 0.55)
	return label
