class_name UnitPortraitView
extends SubViewportContainer

## HUD 3D 肖像：SubViewport + Portrait.scn；无 MDX Camera 时用启发式机位。

const PORTRAIT_SIZE := Vector2i(96, 96)

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _light: DirectionalLight3D
var _model_root: Node3D
var _cache: MapModelCache = null
var _catalog: Wc3IdCatalog = null
var _type_id: String = ""


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(PORTRAIT_SIZE)
	_ensure_viewport()


func configure(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	_cache = cache
	_catalog = catalog


func clear_portrait() -> void:
	_type_id = ""
	_clear_model()


func show_type(type_id: String, owner_id: int = 0) -> void:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		clear_portrait()
		return
	if tid == _type_id and _model_root != null and is_instance_valid(_model_root):
		return
	_type_id = tid
	_ensure_viewport()
	_clear_model()
	if _cache == null or _catalog == null:
		return
	var path := _catalog.portrait_glb_path(tid)
	if path.is_empty():
		path = _catalog.converted_glb_path(tid)
	if path.is_empty():
		return
	var inst: Node3D = _cache.instance_glb(path) as Node3D
	if inst == null:
		return
	_model_root = inst
	_world.add_child(inst)
	var color_i := MapUnitLayer.resolve_team_color_index(tid, owner_id)
	_cache.apply_team_color(inst, color_i, tid != "sloc")
	_fit_camera(inst)
	# 播 Stand / Portrait 动画若有
	_try_play_idle(inst)


func _ensure_viewport() -> void:
	if _vp != null and is_instance_valid(_vp):
		return
	_vp = SubViewport.new()
	_vp.name = "PortraitViewport"
	_vp.size = PORTRAIT_SIZE
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)
	_world = Node3D.new()
	_world.name = "PortraitWorld"
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.name = "PortraitCam"
	_cam.current = true
	_cam.fov = 30.0
	_world.add_child(_cam)
	_light = DirectionalLight3D.new()
	_light.name = "PortraitLight"
	_light.light_energy = 1.1
	_light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	_world.add_child(_light)
	var fill := OmniLight3D.new()
	fill.name = "PortraitFill"
	fill.light_energy = 0.35
	fill.omni_range = 8.0
	fill.position = Vector3(-1.2, 1.0, 1.5)
	_world.add_child(fill)


func _clear_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null


func _fit_camera(root: Node3D) -> void:
	if _cam == null or root == null:
		return
	var aabb := _visual_aabb(root)
	if aabb.size.length() < 1e-4:
		aabb = AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.2, 0.8))
	var center := aabb.position + aabb.size * 0.5
	# 略偏上，更像头像构图
	center.y = aabb.position.y + aabb.size.y * 0.62
	var radius := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	radius = maxf(radius, 0.35)
	var dist := radius / maxf(tan(deg_to_rad(_cam.fov * 0.5)), 0.05) * 1.15
	var cam_pos := center + Vector3(0.0, radius * 0.08, dist)
	_cam.global_position = cam_pos
	_cam.look_at(center, Vector3.UP)


func _visual_aabb(root: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for c in root.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var la := vi.get_aabb()
		var xf := vi.global_transform
		# 转世界后再回到 root 局部
		var corners: Array[Vector3] = []
		for i in range(8):
			var local := la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			corners.append(root.to_local(xf * local))
		for p in corners:
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func _try_play_idle(root: Node3D) -> void:
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var player := n as AnimationPlayer
		if player == null:
			continue
		for prefer in ["Portrait", "Stand", "Stand - 1", "Birth"]:
			if player.has_animation(prefer):
				player.play(prefer)
				return
		var list := player.get_animation_list()
		if list.size() > 0:
			player.play(list[0])
		return
