class_name PortraitCamera
extends RefCounted
## Source portrait framing; never includes background boards or particle bounds.
const Tracks: GDScript = preload("portrait_camera_tracks.gd")
var _active_source: Dictionary = {}
const _FRAMING_FILL: float = 0.90
var _world: Node3D
var fallback_camera: Camera3D
var _source_cameras: Array = []

func configure(world: Node3D) -> void:
	_world = world

func _normalize_portrait_materials(model: Node3D) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if not mi.mesh is PrimitiveMesh:
			continue
		var primitive: PrimitiveMesh = mi.mesh as PrimitiveMesh
		var override: Material = mi.get_surface_override_material(0)
		if primitive.material != null or override == null:
			continue
		var local_mesh: PrimitiveMesh = primitive.duplicate() as PrimitiveMesh
		local_mesh.material = override
		mi.mesh = local_mesh
		mi.set_surface_override_material(0, null)


func _normalize_portrait_model_scale(root: Node3D) -> void:
	if root == null:
		return
	var local: AABB = _visual_aabb(root)
	# peasant_Portrait 等未烘焙 WC3 尺度（顶点 0~200）；战场 GLB 已乘 model_scale。
	if local.size.length() <= 12.0:
		return
	root.scale = Vector3.ONE * Wc3Coords.WORLD_SCALE


func _is_portrait_body_mesh(mi: MeshInstance3D) -> bool:
	var nm: String = str(mi.name).to_lower()
	if nm.contains("glow") or nm.contains("uber") or nm.contains("splat"):
		return false
	if nm.contains("billboard"):
		return false
	return nm.begins_with("geoset_") or nm.begins_with("mesh")


## 先使用源机位，再尝试旧烘焙相机，最后按身体包围盒取景。
func _fit_camera(root: Node3D, model_path: String) -> void:
	if root == null or _world == null:
		return
	_active_source = {}
	_source_cameras = root.get_meta("wc3_portrait_cameras", [])
	_set_model_cameras_current(root, false)
	# 烘焙 Camera01 的局部坐标常已是世界尺度（sidecar ×0.01），
	# 而网格仍是 WC3 厘米；若根节点再乘 WORLD_SCALE，相机会缩到模型里（民兵肖像）。
	# 仅当根未缩放时才直接用烘焙相机（网格与相机同一空间）。
	if not _source_cameras.is_empty():
		var source_camera: Camera3D = _ensure_fallback_camera()
		source_camera.current = true
		if _apply_mdx_camera_sidecar(source_camera, model_path):
			return
	var baked: Camera3D = _find_baked_camera(root)
	var root_scaled: bool = not root.scale.is_equal_approx(Vector3.ONE)
	if baked != null and not root_scaled:
		baked.current = true
		if fallback_camera != null and is_instance_valid(fallback_camera):
			fallback_camera.current = false
		return
	var cam: Camera3D = _ensure_fallback_camera()
	cam.current = true
	var global_aabb: AABB = _visual_aabb_global(root)
	# 已归一化 WC3 尺度（peasant_Portrait / Militia_Portrait 等）：sidecar 机位 ~1.6。
	if global_aabb.size.length() <= 3.0:
		if _apply_mdx_camera_sidecar(cam, model_path):
			return
	var local_aabb: AABB = _visual_aabb(root)
	if local_aabb.size.length() <= 12.0:
		if _apply_mdx_camera_sidecar(cam, model_path):
			return
	# 根已缩放但 sidecar 失败：仍优先 sidecar 语义（世界尺度），避免错误 AABB 取景
	if root_scaled and _apply_mdx_camera_sidecar(cam, model_path):
		return
	var aabb: AABB = global_aabb
	if aabb.size.length() < 1e-4:
		aabb = AABB(root.global_position + Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.2, 0.8))
	var center: Vector3 = aabb.get_center()
	center.y = aabb.position.y + aabb.size.y * 0.62
	var radius: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	radius = maxf(radius, 0.35)
	var dist: float = radius / maxf(tan(deg_to_rad(cam.fov * 0.5)), 0.05) * 1.15
	dist *= _FRAMING_FILL
	cam.global_position = center + Vector3(0.0, radius * 0.08, dist)
	cam.look_at(center, Vector3.UP)


func _visual_aabb_global(root: Node3D) -> AABB:
	var local: AABB = _visual_aabb(root)
	if local.size.length() < 1e-8:
		return AABB()
	return root.global_transform * local


func _ensure_fallback_camera() -> Camera3D:
	if fallback_camera != null and is_instance_valid(fallback_camera):
		return fallback_camera
	fallback_camera = Camera3D.new()
	fallback_camera.name = "FallbackPortraitCam"
	fallback_camera.fov = 30.0
	fallback_camera.current = false
	_world.add_child(fallback_camera)
	return fallback_camera


func _find_baked_camera(root: Node) -> Camera3D:
	if root == null:
		return null
	for prefer: String in ["Camera01", "PortraitCamera", "Camera"]:
		var n: Node = root.find_child(prefer, true, false)
		if n is Camera3D:
			return n as Camera3D
	var found: Array[Node] = root.find_children("*", "Camera3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Camera3D


## HUD 回退相机在 PortraitWorld（无额外 scale）；sidecar 坐标已是世界尺度。
func _apply_mdx_camera_sidecar(cam: Camera3D, model_path: String) -> bool:
	var data: Dictionary = {"cameras": _source_cameras} if not _source_cameras.is_empty() else _load_cameras_sidecar(model_path)
	if data.is_empty():
		return false
	var cams: Variant = data.get("cameras", [])
	if typeof(cams) != TYPE_ARRAY or (cams as Array).is_empty():
		return false
	var first: Variant = (cams as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = first
	_active_source = d
	var pos_v: Variant = d.get("position", null)
	var tgt_v: Variant = d.get("target", null)
	if typeof(pos_v) != TYPE_ARRAY or typeof(tgt_v) != TYPE_ARRAY:
		return false
	var pos_a: Array = pos_v
	var tgt_a: Array = tgt_v
	if pos_a.size() < 3 or tgt_a.size() < 3:
		return false
	var pos: Vector3 = Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	var tgt: Vector3 = Vector3(float(tgt_a[0]), float(tgt_a[1]), float(tgt_a[2]))
	cam.fov = clampf(float(d.get("fov_y_deg", 30.0)), 5.0, 120.0)
	var near_v: float = float(d.get("near", 0.01))
	var far_v: float = float(d.get("far", 100.0))
	if near_v > 0.0:
		cam.near = near_v
	if far_v > near_v:
		cam.far = far_v
	# 建筑 MDX 相机 far 常为 10，本体 AABB 更大时会被裁切。
	cam.far = maxf(cam.far, 48.0)
	# 基本机位先显示，随后按当前 Portrait 源时间更新平移和滚转。
	var eye: Vector3 = pos
	cam.global_position = eye
	if eye.distance_squared_to(tgt) > 1e-8:
		cam.look_at(tgt, Vector3.UP)
	return true


func _load_cameras_sidecar(model_path: String) -> Dictionary:
	if model_path.is_empty():
		return {}
	var logical: String = model_path
	if logical.begins_with("res://assets/asset-converted/"):
		logical = logical.substr("res://assets/asset-converted/".length())
	elif logical.begins_with("res://"):
		logical = logical.substr("res://".length())
	var stem: String = logical
	var lower: String = stem.to_lower()
	for ext: String in [".gltf", ".glb", ".scn"]:
		if lower.ends_with(ext):
			stem = stem.substr(0, stem.length() - ext.length())
			break
	var cam_logical: String = stem + ".cameras.json"
	var disk: String = RuntimeAssets.project_abs(RuntimeAssets.converted_path(cam_logical))
	if disk.is_empty() or not FileAccess.file_exists(disk):
		return {}
	var text: String = RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return {}
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _visual_aabb(root: Node3D) -> AABB:
	var aabb: AABB = AABB()
	var first: bool = true
	for c: Node in root.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = c as VisualInstance3D
		if vi == null or not vi.visible or vi is GPUParticles3D or bool(vi.get_meta("wc3_portrait_background", false)):
			continue
		var la: AABB = vi.get_aabb()
		var xf: Transform3D = vi.global_transform
		for i: int in range(8):
			var local: Vector3 = la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p: Vector3 = root.to_local(xf * local)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func _set_model_cameras_current(root: Node, on: bool) -> void:
	if root == null:
		return
	if root is Camera3D:
		(root as Camera3D).current = on
	for c: Node in root.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = on



func update_source_animation(player: AnimationPlayer) -> void:
	if _active_source.is_empty() or fallback_camera == null or player == null or not player.is_playing():
		return
	var animation: Animation = player.get_animation(player.current_animation)
	var interval: Array = animation.get_meta("source_interval_ms", [])
	if interval.size() != 2 or float(interval[1]) <= float(interval[0]):
		return
	var start: float = float(interval[0])
	var end: float = float(interval[1])
	var local_time: float = player.current_animation_position * 1000.0
	var frame: float = start + (fmod(local_time, end - start) if bool(animation.get_meta("source_looping", false)) else minf(local_time, end - start))
	var position: Array = _active_source.position
	var target: Array = _active_source.target
	var eye: Vector3 = Vector3(float(position[0]), float(position[1]), float(position[2])) + Tracks.sample(_active_source.get("translation"), frame, start, end)
	var aim: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) + Tracks.sample(_active_source.get("target_translation"), frame, start, end)
	fallback_camera.global_position = eye
	if eye.distance_squared_to(aim) > 1e-8:
		fallback_camera.look_at(aim, Vector3.UP)
		var roll: Vector3 = Tracks.sample(_active_source.get("rotation"), frame, start, end, true)
		fallback_camera.rotate_object_local(Vector3.FORWARD, roll.x)
