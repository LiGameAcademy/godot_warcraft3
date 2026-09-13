class_name GroundItemVisual
extends RefCounted

## 地面表现与屏幕命中。缺少已转换模型时使用金色小箱子。
static func attach(ground: GroundItem, cache: MapModelCache = null) -> void:
	var logical := ItemCatalog.model_path(ground.item.type_id)
	var path := RuntimeAssets.resolve_model_scene(logical)
	var visual: Node3D
	if cache != null and not path.is_empty():
		visual = cache.instance_glb(RuntimeAssets.converted_path(logical))
	if visual != null:
		ground.add_child(visual)
		visual.scale *= ItemCatalog.data(ground.item.type_id).scale
		AnimPlayback.play_logical(visual, "Stand", 0.0, cache)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.48, 0.32, 0.36)
		mesh.mesh = box
		mesh.position.y = 0.18
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.68, 0.18)
		material.metallic = 0.4
		mesh.material_override = material
		ground.add_child(mesh)
	var label := Label3D.new()
	label.text = ItemCatalog.title(ground.item.type_id)
	label.position.y = 0.85
	label.font_size = 26
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color(1.0, 0.87, 0.4)
	ground.add_child(label)

static func pick_at(host: Node, camera: Camera3D, screen: Vector2) -> GroundItem:
	if host == null or camera == null:
		return null
	var best: GroundItem
	var distance := 26.0
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
